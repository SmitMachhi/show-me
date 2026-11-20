// show-me: one program that is both the command line tool and the daemon.
// `serve` is internal: `open` starts it in the background when needed.
const std = @import("std");
const state = @import("state.zig");
const daemon = @import("daemon.zig");
const client = @import("client.zig");
const reviews = @import("reviews.zig");
const Io = std.Io;

const usage =
    \\usage:
    \\  show-me open <file.html>   show the page for review, return at once
    \\  show-me wait <file.html>   block until the reviewer sends notes, print them
    \\  show-me stop               end the background daemon
    \\  show-me --version
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const cmd = if (args.len > 1) args[1] else "";
    if (std.mem.eql(u8, cmd, "serve")) return daemon.serve(init);
    if (std.mem.eql(u8, cmd, "open")) return open(init, args);
    if (std.mem.eql(u8, cmd, "wait")) return wait(init, args);
    if (std.mem.eql(u8, cmd, "stop")) return stop(init);
    if (std.mem.eql(u8, cmd, "--version")) return say(io, state.version ++ "\n");
    std.debug.print("{s}", .{usage});
    std.process.exit(2);
}

fn say(io: Io, text: []const u8) void {
    Io.File.stdout().writeStreamingAll(io, text) catch {};
}

// Checks the file argument and returns its real path. Two spellings of one file are one review.
fn realFile(init: std.process.Init, args: []const []const u8, cmd: []const u8) []const u8 {
    if (args.len < 3) state.fail("{s} needs one file. Example: show-me {s} plan.html", .{ cmd, cmd });
    const file = args[2];
    const is_html = std.ascii.endsWithIgnoreCase(file, ".html") or std.ascii.endsWithIgnoreCase(file, ".htm");
    if (!is_html) state.fail("'{s}' is not an .html file. show-me reviews HTML pages only.", .{file});
    return Io.Dir.cwd().realPathFileAlloc(init.io, file, init.arena.allocator()) catch
        state.fail("cannot read '{s}'. Check the path.", .{file});
}

fn open(init: std.process.Init, args: []const []const u8) void {
    const arena = init.arena.allocator();
    const path = realFile(init, args, "open");
    const port = client.ensureDaemon(init);
    const res = client.call(init.io, arena, port, "POST", "/reviews", path) catch |e|
        state.fail("the daemon did not answer: {t}. Run `show-me stop`, then retry.", .{e});
    if (res.status != 200) state.fail("the daemon refused the file: {s}", .{res.body});
    say(init.io, std.fmt.allocPrint(arena, "http://127.0.0.1:{d}/r/{s}\n", .{ port, res.body }) catch return);
}

fn wait(init: std.process.Init, args: []const []const u8) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const path = realFile(init, args, "wait");
    const d = state.dir(io, arena, init.environ_map);
    const info = if (client.running(io, d)) state.readInfo(io, arena, d) else null;
    const port = (info orelse state.fail("no review is open. Run: show-me open {s}", .{args[2]})).port;
    const key = reviews.keyOf(path);
    const res = client.call(io, arena, port, "GET", "/wait/" ++ key, "") catch |e|
        state.fail("lost the daemon while waiting: {t}. Run the same wait again. No notes are lost.", .{e});
    if (res.status != 200) state.fail("no review is open for this file. Run: show-me open {s}", .{args[2]});
    const split = std.mem.findScalar(u8, res.body, '\n') orelse res.body.len;
    say(io, res.body[@min(split + 1, res.body.len)..]);
    // Ack only after the notes are printed. A crash before this line redelivers them.
    _ = client.call(io, arena, port, "POST", "/ack/" ++ key, res.body[0..split]) catch {};
}

fn stop(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const d = state.dir(io, arena, init.environ_map);
    if (!client.running(io, d)) return say(io, "show-me is not running\n");
    const info = state.readInfo(io, arena, d) orelse
        state.fail("the daemon is running but daemon.json is missing. End the show-me process by hand.", .{});
    _ = client.call(io, arena, info.port, "POST", "/shutdown", "") catch {};
    say(io, "stopped\n");
}
