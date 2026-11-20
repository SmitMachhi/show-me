// show-me: one program that is both the command line tool and the daemon.
// `serve` is internal: `open` starts it in the background when needed.
const std = @import("std");
const builtin = @import("builtin");
const state = @import("state.zig");
const daemon = @import("daemon.zig");
const client = @import("client.zig");
const agent = @import("agent.zig");
const graphs = @import("graphs.zig");
const lint = @import("lint.zig");
const exporter = @import("export.zig");
const list = @import("list.zig");
const setup = @import("setup.zig");
const Io = std.Io;

const usage =
    \\usage:
    \\  show-me open <file.html> [--no-open] [--reopen]
    \\                             check the page, show it for review, return at once
    \\  show-me wait <file.html> [--reply "text"]
    \\                             show the reply, block until notes arrive, print them
    \\  show-me reply <file.html> "text"   show one reply to the reviewer
    \\  show-me end <file.html>    end the review
    \\  show-me check <file.html>  check diagrams and writing rules, report each problem
    \\  show-me export <file.html> [--out <path>]
    \\                             write one file that opens without show-me
    \\  show-me setup [folder]     write the agent skill (default ~/.claude/skills/show-me)
    \\  show-me stop               end the background daemon
    \\  show-me --version
    \\
;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const cmd = if (args.len > 1) args[1] else "";
    if (args.len < 2) return list.run(init);
    if (std.mem.eql(u8, cmd, "serve")) return daemon.serve(init);
    if (std.mem.eql(u8, cmd, "open")) return open(init, args);
    if (std.mem.eql(u8, cmd, "wait")) return agent.wait(init, args);
    if (std.mem.eql(u8, cmd, "reply")) return agent.reply(init, args);
    if (std.mem.eql(u8, cmd, "end")) return agent.end(init, args);
    if (std.mem.eql(u8, cmd, "check")) return check(init, args);
    if (std.mem.eql(u8, cmd, "export")) return exportPage(init, args);
    if (std.mem.eql(u8, cmd, "setup")) return setup.run(init, args);
    if (std.mem.eql(u8, cmd, "stop")) return stop(init);
    if (std.mem.eql(u8, cmd, "--version")) return agent.say(init.io, state.version ++ "\n");
    if (std.mem.eql(u8, cmd, "--help")) return agent.say(init.io, usage);
    std.debug.print("{s}", .{usage});
    std.process.exit(2);
}

fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args[@min(args.len, 3)..]) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
}

// Draws the diagrams and checks the words. Reports each failure and exits 1 on any,
// so a broken page never reaches the reviewer.
fn checkPage(init: std.process.Init, path: []const u8) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const html = Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(64 * 1024 * 1024)) catch |e|
        state.fail("cannot read '{s}': {t}", .{ path, e });
    const ctx: graphs.Ctx = .{ .io = io, .dir = state.dir(io, arena, init.environ_map), .env = init.environ_map };
    const drawn = graphs.expand(ctx, arena, html) catch |e|
        state.fail("cannot draw the diagrams: {t}", .{e});
    var rules_buf: [4096]u8 = undefined;
    const rules = lint.parseRules(ctx.dir.readFile(io, "rules", &rules_buf) catch "");
    if (rules.unknown) |name| state.fail("unknown rule '{s}' in the rules file in the state folder.", .{name});
    const words = lint.run(arena, html, rules) catch |e| state.fail("cannot check the words: {t}", .{e});
    if (drawn.errors.len + words.len == 0) return;
    std.debug.print("{s}{s}", .{ drawn.errors, words });
    state.fail("fix each line listed above, then run the command again.", .{});
}

fn check(init: std.process.Init, args: []const []const u8) void {
    checkPage(init, agent.realFile(init, args, "check"));
    agent.say(init.io, "ok\n");
}

// Writes one file that opens without show-me. Default name: plan.html -> plan.export.html.
fn exportPage(init: std.process.Init, args: []const []const u8) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const path = agent.realFile(init, args, "export");
    checkPage(init, path);
    const html = Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(64 * 1024 * 1024)) catch |e|
        state.fail("cannot read '{s}': {t}", .{ path, e });
    const ctx: graphs.Ctx = .{ .io = io, .dir = state.dir(io, arena, init.environ_map), .env = init.environ_map };
    const out = exporter.page(ctx, arena, path, html) catch |e| state.fail("cannot export: {t}", .{e});
    const custom = args.len > 4 and std.mem.eql(u8, args[3], "--out");
    const stem = path[0 .. path.len - std.fs.path.extension(path).len];
    const dest = if (custom) args[4] else std.fmt.allocPrint(arena, "{s}.export.html", .{stem}) catch return;
    Io.Dir.cwd().writeFile(io, .{ .sub_path = dest, .data = out }) catch |e|
        state.fail("cannot write '{s}': {t}", .{ dest, e });
    agent.say(io, std.fmt.allocPrint(arena, "{s}\n", .{dest}) catch return);
}

fn open(init: std.process.Init, args: []const []const u8) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const path = agent.realFile(init, args, "open");
    checkPage(init, path);
    const port = client.ensureDaemon(init);
    const res = client.call(io, arena, port, "POST", "/reviews", path) catch |e|
        state.fail("the daemon did not answer: {t}. Run `show-me stop`, then retry.", .{e});
    // The answer is "<key> <open tabs> <open|reviewer|agent>".
    var parts = std.mem.splitScalar(u8, res.body, ' ');
    const key = parts.next() orelse "";
    const tabs = parts.next() orelse "0";
    const ended = parts.next() orelse "open";
    if (res.status != 200 or key.len != 16) state.fail("the daemon refused the file: {s}", .{res.body});
    if (std.mem.eql(u8, ended, "reviewer") and !hasFlag(args, "--reopen")) {
        state.fail("the reviewer ended this review. Open it again only if they ask: show-me open {s} --reopen", .{args[2]});
    }
    if (!std.mem.eql(u8, ended, "open")) {
        _ = client.call(io, arena, port, "POST", std.fmt.allocPrint(arena, "/start/{s}", .{key}) catch return, "") catch {};
    }
    const url = std.fmt.allocPrint(arena, "http://127.0.0.1:{d}/r/{s}\n", .{ port, key }) catch return;
    if (std.mem.eql(u8, tabs, "0") and !hasFlag(args, "--no-open")) browse(io, url[0 .. url.len - 1]);
    agent.say(io, url);
}

// Opens the default browser. Failure is not fatal: the URL is printed either way.
fn browse(io: Io, url: []const u8) void {
    const argv: []const []const u8 = switch (builtin.os.tag) {
        .windows => &.{ "cmd", "/c", "start", "", url },
        .macos => &.{ "open", url },
        else => &.{ "xdg-open", url },
    };
    _ = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
        .create_no_window = true,
    }) catch std.debug.print("show-me: could not open the browser. Open the address below by hand.\n", .{});
}

fn stop(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const d = state.dir(io, arena, init.environ_map);
    if (!client.running(io, d)) return agent.say(io, "show-me is not running\n");
    const info = state.readInfo(io, arena, d) orelse
        state.fail("the daemon is running but daemon.json is missing. End the show-me process by hand.", .{});
    _ = client.call(io, arena, info.port, "POST", "/shutdown", "") catch {};
    agent.say(io, "stopped\n");
}
