// show-me: one program that is both the command line tool and the daemon.
// Usage: show-me open <file.html> | stop | --version. `serve` is internal.
const std = @import("std");
const state = @import("state.zig");
const daemon = @import("daemon.zig");
const client = @import("client.zig");
const Io = std.Io;

const usage =
    \\usage:
    \\  show-me open <file.html>   show the page for review
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
    if (std.mem.eql(u8, cmd, "stop")) return stop(init);
    if (std.mem.eql(u8, cmd, "--version")) return say(io, state.version ++ "\n", .{});
    std.debug.print("{s}", .{usage});
    std.process.exit(2);
}

fn say(io: Io, comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
    Io.File.stdout().writeStreamingAll(io, text) catch {};
}

fn open(init: std.process.Init, args: []const []const u8) void {
    if (args.len < 3) state.fail("open needs one file. Example: show-me open plan.html", .{});
    const file = args[2];
    const is_html = std.ascii.endsWithIgnoreCase(file, ".html") or std.ascii.endsWithIgnoreCase(file, ".htm");
    if (!is_html) state.fail("'{s}' is not an .html file. show-me reviews HTML pages only.", .{file});
    Io.Dir.cwd().access(init.io, file, .{}) catch
        state.fail("cannot read '{s}'. Check the path.", .{file});
    const port = client.ensureDaemon(init);
    say(init.io, "http://127.0.0.1:{d}/\n", .{port});
}

fn stop(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const d = state.dir(io, arena, init.environ_map);
    if (!client.running(io, d)) return say(io, "show-me is not running\n", .{});
    const info = state.readInfo(io, arena, d) orelse
        state.fail("the daemon is running but daemon.json is missing. End the show-me process by hand.", .{});
    _ = client.call(io, info.port, "POST", "/shutdown", &.{}) catch {};
    say(io, "stopped\n", .{});
}
