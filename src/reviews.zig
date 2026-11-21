// One review = one HTML file = one append-only log, <key>.jsonl, in the state folder.
// Lines: {"t":"open","file":..}, {"t":"note","data":..}, {"t":"ack","n":N},
// {"t":"reply","text":..}. Notes past the last ack are undelivered. A reader that dies
// before its ack gets them again, so delivery is at-least-once and nothing is lost.
// One {"t":"id","v":..} line comes before each note the browser gave one id, so the
// same note sent twice (one retry after one lost answer) is stored once.
// One {"t":"at","ms":..} line comes before each later event: its time in Unix ms.
// One {"t":"working"} line says the page file changed after delivery (presence.zig).
// Limits: one changed log is reread whole, and all reviews share one wake-up signal.
const std = @import("std");
const presence = @import("presence.zig");
const images = @import("images.zig");
const Io = std.Io;

pub const Key = [16]u8;
pub const max_note_bytes = 256 * 1024;
const max_log_bytes = 64 * 1024 * 1024;
pub const note_prefix = "{\"t\":\"note\",\"data\":";
const id_prefix = "{\"t\":\"id\",\"v\":\"";
pub const ack_prefix = "{\"t\":\"ack\",\"n\":";
pub const reply_prefix = "{\"t\":\"reply\",\"text\":";
const end_prefix = "{\"t\":\"end\",\"by\":";
const start_line = "{\"t\":\"start\"}\n";

pub const Shared = struct {
    io: Io,
    dir: Io.Dir,
    env: *const std.process.Environ.Map,
    mutex: Io.Mutex = .init,
    changed: Io.Condition = .init,
    tabs: presence.Table = @splat(null),
    waiters: presence.Table = @splat(null),
    // The turn of the newest `wait` for each review. Only that wait may deliver.
    owners: std.AutoHashMapUnmanaged(Key, u64) = .empty,
    turns: u64 = 0,
    // Reviews that one browser tab has shown since the daemon started.
    shown: std.AutoHashMapUnmanaged(Key, void) = .empty,
};

// The key is derived from the real path, so it is an address, not a secret.
pub fn keyOf(real_path: []const u8) Key {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(real_path, &digest, .{});
    return std.fmt.bytesToHex(digest[0..8].*, .lower);
}

// Keys arrive in URLs. Only 16 lowercase hex characters may become a file name.
pub fn parseKey(text: []const u8) ?Key {
    if (text.len != 16) return null;
    for (text) |c| {
        if (!std.ascii.isDigit(c) and !(c >= 'a' and c <= 'f')) return null;
    }
    return text[0..16].*;
}

fn logName(key: Key) [22]u8 {
    return (key ++ ".jsonl").*;
}

pub fn exists(sh: *Shared, key: Key) bool {
    return logSize(sh, key) != null;
}

pub fn logSize(sh: *Shared, key: Key) ?u64 {
    const stat = sh.dir.statFile(sh.io, &logName(key), .{}) catch return null;
    return stat.size;
}

pub fn readLog(sh: *Shared, arena: std.mem.Allocator, key: Key) ![]const u8 {
    return sh.dir.readFileAlloc(sh.io, &logName(key), arena, .limited(max_log_bytes));
}

// The reviewed file's real path, read back from the first log line.
pub fn fileOf(sh: *Shared, arena: std.mem.Allocator, key: Key) ![]const u8 {
    const text = try readLog(sh, arena, key);
    const line = text[0 .. std.mem.findScalar(u8, text, '\n') orelse text.len];
    const Head = struct { file: []const u8 };
    return (try std.json.parseFromSliceLeaky(Head, arena, line, .{ .ignore_unknown_fields = true })).file;
}

pub fn register(sh: *Shared, arena: std.mem.Allocator, real_path: []const u8) !Key {
    const key = keyOf(real_path);
    if (exists(sh, key)) return key;
    const file = try std.json.Stringify.valueAlloc(arena, real_path, .{});
    try append(sh, key, try std.fmt.allocPrint(arena, "{{\"t\":\"open\",\"file\":{s}}}\n", .{file}));
    return key;
}

fn append(sh: *Shared, key: Key, lines: []const u8) !void {
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    try appendLocked(sh, key, lines);
}

// The time line that goes before one event.
pub fn stamp(sh: *Shared, arena: std.mem.Allocator) ![]const u8 {
    const ms = @divFloor(Io.Clock.now(.real, sh.io).nanoseconds, std.time.ns_per_ms);
    return std.fmt.allocPrint(arena, "{{\"t\":\"at\",\"ms\":{d}}}\n", .{ms});
}

// Appends one event after its time line.
fn appendStamped(sh: *Shared, arena: std.mem.Allocator, key: Key, lines: []const u8) !void {
    try append(sh, key, try std.mem.concat(arena, u8, &.{ try stamp(sh, arena), lines }));
}

pub fn appendLocked(sh: *Shared, key: Key, lines: []const u8) !void {
    const f = try sh.dir.createFile(sh.io, &logName(key), .{ .truncate = false });
    defer f.close(sh.io);
    try f.writePositionalAll(sh.io, lines, try f.length(sh.io));
}

// The note's id line, or "" when the browser gave no usable id. The id leaves the note,
// so the agent never reads it. Only letters, digits and "-" are kept, up to 64 of them.
fn takeId(arena: std.mem.Allocator, note: *std.json.Value) ![]const u8 {
    if (note.* != .object) return "";
    const kv = note.object.fetchOrderedRemove("id") orelse return "";
    if (kv.value != .string or kv.value.string.len == 0 or kv.value.string.len > 64) return "";
    for (kv.value.string) |c| if (!std.ascii.isAlphanumeric(c) and c != '-') return "";
    return std.fmt.allocPrint(arena, "{s}{s}\"}}\n", .{ id_prefix, kv.value.string });
}

// The body comes from a browser. Reparse it so each log line is one valid JSON line.
// One array becomes one note per item, written in one append. A note whose id is
// already in the log is skipped; the check and the write share one lock.
pub fn send(sh: *Shared, arena: std.mem.Allocator, key: Key, body: []const u8) !void {
    const value = try std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{});
    const items: []const std.json.Value = if (value == .array) value.array.items else &.{value};
    var ids: std.ArrayList([]const u8) = .empty;
    var notes: std.ArrayList([]const u8) = .empty;
    for (items) |item| {
        var note = item;
        try ids.append(arena, try takeId(arena, &note));
        try images.resolve(sh, arena, &note);
        const data = try std.json.Stringify.valueAlloc(arena, note, .{});
        try notes.append(arena, try std.fmt.allocPrint(arena, "{s}{s}}}\n", .{ note_prefix, data }));
    }
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    const log = try readLog(sh, arena, key);
    var lines: std.ArrayList(u8) = .empty;
    for (ids.items, notes.items) |id, note| {
        if (id.len > 0 and std.mem.find(u8, log, id) != null) continue;
        if (id.len > 0 and std.mem.find(u8, lines.items, id) != null) continue;
        try lines.appendSlice(arena, id);
        try lines.appendSlice(arena, note);
    }
    if (lines.items.len > 0) try appendLocked(sh, key, try std.mem.concat(arena, u8, &.{ try stamp(sh, arena), lines.items }));
    sh.changed.broadcast(sh.io);
}

pub fn ack(sh: *Shared, arena: std.mem.Allocator, key: Key, n: usize) !void {
    try appendStamped(sh, arena, key, try std.fmt.allocPrint(arena, "{s}{d}}}\n", .{ ack_prefix, n }));
}

pub fn reply(sh: *Shared, arena: std.mem.Allocator, key: Key, text: []const u8) !void {
    const json = try std.json.Stringify.valueAlloc(arena, text, .{});
    try appendStamped(sh, arena, key, try std.fmt.allocPrint(arena, "{s}{s}}}\n", .{ reply_prefix, json }));
}

// Ends the review. When the reviewer ends it, the agent learns of it as one last note.
pub fn end(sh: *Shared, arena: std.mem.Allocator, key: Key, by_reviewer: bool) !void {
    const who = if (by_reviewer) "reviewer" else "agent";
    const last = if (by_reviewer) note_prefix ++ "{\"kind\":\"end\",\"note\":\"The reviewer ended the review.\"}}\n" else "";
    try appendStamped(sh, arena, key, try std.fmt.allocPrint(arena, "{s}{s}\"{s}\"}}\n", .{ last, end_prefix, who }));
    sh.changed.broadcast(sh.io);
}

pub fn start(sh: *Shared, key: Key) !void {
    try append(sh, key, start_line);
}

// Who ended the review, or null while it is open. One later start line reopens it.
pub fn endedBy(log: []const u8) ?[]const u8 {
    var by: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, log, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, end_prefix)) by = line[end_prefix.len + 1 .. line.len - 2];
        if (std.mem.eql(u8, line, start_line[0 .. start_line.len - 1])) by = null;
    }
    return by;
}
test "keys and note ids" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expect(parseKey("../../etc/passwd!") == null);
    try std.testing.expect(parseKey("0123456789abcdef") != null);
    var note = try std.json.parseFromSliceLeaky(std.json.Value, arena, "{\"id\":\"a-1\",\"note\":\"x\"}", .{});
    try std.testing.expectEqualStrings(id_prefix ++ "a-1\"}\n", try takeId(arena, &note));
    try std.testing.expect(note.object.get("id") == null);
    var bad = try std.json.parseFromSliceLeaky(std.json.Value, arena, "{\"id\":\"a\\\"}\",\"note\":\"x\"}", .{});
    try std.testing.expectEqualStrings("", try takeId(arena, &bad));
}
