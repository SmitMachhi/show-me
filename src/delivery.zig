// Hands undelivered notes to the agent's `wait` command.
// One review has one listener: the newest `wait` owns it, and an older one is told to
// stop. A re-run after one killed `wait` therefore works at once, and two agents never
// both act on one note.
// When the last browser tab of one review closes and none comes back within the grace
// time, `wait` reports that instead of blocking forever, so the agent can ask the
// person. A review that no tab has shown yet is not "closed": the person may still
// be on the way to the link.
const std = @import("std");
const reviews = @import("reviews.zig");
const presence = @import("presence.zig");
const Io = std.Io;
const Shared = reviews.Shared;
const Key = reviews.Key;
const Request = std.http.Server.Request;

pub const closed_note = "{\"kind\":\"closed\",\"note\":\"No browser tab shows this review. Ask the person to open it again, or end the review.\"}\n";

// What one heartbeat found. Exactly one of these.
const Beat = union(enum) { notes: []const u8, idle, replaced };

// Makes the caller the owner of the review and wakes the older owner, which then stops.
fn claim(sh: *Shared, key: Key) !u64 {
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    sh.turns += 1;
    try sh.owners.put(std.heap.page_allocator, key, sh.turns);
    sh.changed.broadcast(sh.io);
    return sh.turns;
}

// Notes past the last ack, or idle after at most two seconds with none.
// The owner check and the read happen under one lock, so a replaced wait never delivers.
fn beat(sh: *Shared, arena: std.mem.Allocator, key: Key, turn: u64, seen_size: *u64) !Beat {
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    if (sh.owners.get(key) != turn) return .replaced;
    const size = reviews.logSize(sh, key) orelse return error.FileNotFound;
    if (size != seen_size.*) {
        seen_size.* = size;
        if (try pending(arena, try reviews.readLog(sh, arena, key))) |out| return .{ .notes = out };
    }
    const two_seconds: Io.Timeout = .{ .duration = .{ .raw = .{ .nanoseconds = 2 * std.time.ns_per_s }, .clock = .awake } };
    sh.changed.waitTimeout(sh.io, &sh.mutex, two_seconds) catch {};
    return .idle;
}

// Seconds with no tab before `wait` reports that nobody shows the review.
fn graceSeconds(sh: *Shared) i96 {
    const text = sh.env.get("SHOW_ME_GRACE_SECONDS") orelse return 20;
    return std.fmt.parseInt(i96, text, 10) catch 20;
}

// Holds the agent's request open until notes exist. One space goes out every two
// seconds: when that write fails the agent's command is gone. The first line of the
// answer says what follows: one note count, "replaced" or "closed".
pub fn serve(sh: *Shared, req: *Request, arena: std.mem.Allocator, key: Key) !void {
    var buf: [64]u8 = undefined;
    var body = try req.respondStreaming(&buf, .{
        .respond_options = .{ .keep_alive = false, .transfer_encoding = .none },
    });
    const turn = try claim(sh, key);
    const slot = presence.join(sh, &sh.waiters, key);
    defer presence.leave(sh, &sh.waiters, slot);
    const grace = graceSeconds(sh) * std.time.ns_per_s;
    var seen_size: u64 = std.math.maxInt(u64);
    var no_tab_since: ?i96 = null;
    while (true) {
        const text: []const u8 = switch (try beat(sh, arena, key, turn, &seen_size)) {
            .notes => |notes| notes,
            .replaced => "replaced\n",
            .idle => idle: {
                const now = Io.Clock.now(.awake, sh.io).nanoseconds;
                if (!presence.left(sh, key)) no_tab_since = null else if (no_tab_since == null) no_tab_since = now;
                if (no_tab_since) |since| if (now - since >= grace) break :idle "closed\n" ++ closed_note;
                break :idle " ";
            },
        };
        try body.writer.writeAll(text);
        try body.writer.flush();
        try body.flush();
        if (!std.mem.eql(u8, text, " ")) return;
    }
}

// How many notes the agent has not confirmed yet.
pub fn unread(log: []const u8) usize {
    var notes: usize = 0;
    var acked: usize = 0;
    var lines = std.mem.splitScalar(u8, log, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, reviews.note_prefix)) notes += 1;
        if (!std.mem.startsWith(u8, line, reviews.ack_prefix)) continue;
        acked = std.fmt.parseInt(usize, line[reviews.ack_prefix.len .. line.len - 1], 10) catch acked;
    }
    return notes -| acked;
}

// Returns "<total>\n" then one undelivered note per line, or null when all are acked.
fn pending(arena: std.mem.Allocator, log: []const u8) !?[]const u8 {
    var notes: std.ArrayList([]const u8) = .empty;
    var acked: usize = 0;
    var lines = std.mem.splitScalar(u8, log, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, reviews.note_prefix)) {
            try notes.append(arena, line[reviews.note_prefix.len .. line.len - 1]);
        } else if (std.mem.startsWith(u8, line, reviews.ack_prefix)) {
            acked = std.fmt.parseInt(usize, line[reviews.ack_prefix.len .. line.len - 1], 10) catch acked;
        }
    }
    if (notes.items.len <= acked) return null;
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "{d}\n", .{notes.items.len});
    for (notes.items[acked..]) |note| {
        try out.print(arena, "{s}\n", .{note});
    }
    return out.items;
}

test "pending returns only notes past the last ack" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const np = reviews.note_prefix;
    const ap = reviews.ack_prefix;
    const log = "{\"t\":\"open\",\"file\":\"x\"}\n" ++ np ++ "1}\n" ++ np ++ "2}\n" ++ ap ++ "1}\n" ++
        "{\"t\":\"id\",\"v\":\"abc\"}\n" ++ np ++ "{\"a\":3}}\n";
    try std.testing.expectEqualStrings("3\n2\n{\"a\":3}\n", (try pending(arena, log)).?);
    try std.testing.expect(try pending(arena, log ++ ap ++ "3}\n") == null);
    try std.testing.expectEqual(@as(usize, 2), unread(log));
}
