// Who is connected to one review, and what the reviewer is told about the agent.
// Every state comes from one fact the daemon can see. Nothing is announced by the agent.
const std = @import("std");
const reviews = @import("reviews.zig");
const Shared = reviews.Shared;
const Key = reviews.Key;

// One slot per connection. A full table only undercounts.
pub const Table = [32]?Key;

pub fn join(sh: *Shared, table: *Table, key: Key) ?usize {
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    for (table, 0..) |*slot, i| {
        if (slot.* != null) continue;
        slot.* = key;
        return i;
    }
    return null;
}

// Records that one tab has shown the review. Only then can "no tab" mean "the person left".
pub fn markShown(sh: *Shared, key: Key) void {
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    sh.shown.put(std.heap.page_allocator, key, {}) catch {};
}

// True when one tab showed the review before and no tab shows it now.
pub fn left(sh: *Shared, key: Key) bool {
    if (count(sh, &sh.tabs, key) > 0) return false;
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    return sh.shown.contains(key);
}

pub fn leave(sh: *Shared, table: *Table, slot: ?usize) void {
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    if (slot) |i| table[i] = null;
}

pub fn count(sh: *Shared, table: *const Table, key: Key) usize {
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    var n: usize = 0;
    for (table) |slot| {
        if (slot) |k| n += @intFromBool(std.mem.eql(u8, &k, &key));
    }
    return n;
}

pub const State = enum { nobody, listening, working };

// listening: one `wait` command holds its connection open.
// working: notes were delivered and no reply came after them.
pub fn state(sh: *Shared, key: Key, delivered_unanswered: bool) State {
    if (count(sh, &sh.waiters, key) > 0) return .listening;
    return if (delivered_unanswered) .working else .nobody;
}

// True when the last ack in the log comes after the last reply.
pub fn deliveredUnanswered(log: []const u8) bool {
    var result = false;
    var lines = std.mem.splitScalar(u8, log, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, reviews.ack_prefix)) result = true;
        if (std.mem.startsWith(u8, line, reviews.reply_prefix)) result = false;
    }
    return result;
}

const working_line = "{\"t\":\"working\"}";

// True when notes were delivered, no reply came after them, and no working line either.
fn needsWorking(log: []const u8) bool {
    var result = false;
    var lines = std.mem.splitScalar(u8, log, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, reviews.ack_prefix)) result = true;
        if (std.mem.startsWith(u8, line, reviews.reply_prefix) or std.mem.eql(u8, line, working_line)) result = false;
    }
    return result;
}

// Called when the page file changes. The first change after delivery means the agent
// works on the notes: one working line goes into the log, so each note shows "Working".
// Every open tab watches the file, so the check and the write share one lock.
pub fn markWorking(sh: *Shared, key: Key) void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    const log = reviews.readLog(sh, arena, key) catch return;
    if (!needsWorking(log)) return;
    const stamp = reviews.stamp(sh, arena) catch return;
    reviews.appendLocked(sh, key, std.mem.concat(arena, u8, &.{ stamp, working_line ++ "\n" }) catch return) catch {};
}

test "one working line between delivery and reply" {
    const ack = reviews.ack_prefix ++ "1}\n";
    const reply = reviews.reply_prefix ++ "\"done\"}\n";
    try std.testing.expect(!needsWorking(""));
    try std.testing.expect(needsWorking(ack));
    try std.testing.expect(!needsWorking(ack ++ working_line ++ "\n"));
    try std.testing.expect(!needsWorking(ack ++ reply));
    try std.testing.expect(needsWorking(ack ++ working_line ++ "\n" ++ reply ++ ack));
}

test "working only between delivery and reply" {
    const ack = reviews.ack_prefix ++ "1}\n";
    const reply = reviews.reply_prefix ++ "\"done\"}\n";
    try std.testing.expect(!deliveredUnanswered(""));
    try std.testing.expect(deliveredUnanswered(ack));
    try std.testing.expect(!deliveredUnanswered(ack ++ reply));
    try std.testing.expect(deliveredUnanswered(ack ++ reply ++ ack));
}
