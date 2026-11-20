// `show-me` with no command: every review on this machine, and which ones have notes
// the agent has not read. One agent session can pick up where another one stopped.
// One line per review: state, unread count, file. Read straight from the logs on disk,
// so it works when the daemon is not running.
const std = @import("std");
const state = @import("state.zig");
const reviews = @import("reviews.zig");
const client = @import("client.zig");
const Io = std.Io;

pub fn run(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const d = state.dir(io, arena, init.environ_map);
    var out: std.ArrayList(u8) = .empty;
    var dir = d.openDir(io, ".", .{ .iterate = true }) catch return;
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".jsonl")) continue;
        const log = dir.readFileAlloc(io, entry.name, arena, .limited(64 * 1024 * 1024)) catch continue;
        const head = log[0 .. std.mem.findScalar(u8, log, '\n') orelse log.len];
        const Head = struct { file: []const u8 };
        const parsed = std.json.parseFromSliceLeaky(Head, arena, head, .{ .ignore_unknown_fields = true }) catch continue;
        const status = if (reviews.endedBy(log) != null) "ended" else "open";
        out.print(arena, "{s}  {d} unread  {s}\n", .{ status, reviews.unread(log), parsed.file }) catch return;
    }
    const daemon = if (client.running(io, d)) "running" else "stopped";
    const none = if (out.items.len == 0) "no reviews yet\n" else "";
    const text = std.fmt.allocPrint(arena, "daemon {s}\n{s}{s}run `show-me --help` for commands\n", .{ daemon, out.items, none }) catch return;
    Io.File.stdout().writeStreamingAll(io, text) catch {};
}
