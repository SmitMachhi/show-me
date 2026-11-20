// One review = one HTML file = one append-only log, <key>.jsonl, in the state folder.
// Lines: {"t":"open","file":..}, {"t":"note","data":..}, {"t":"ack","n":N},
// {"t":"reply","text":..}. Notes past the last ack are undelivered. A reader that dies
// before its ack gets them again, so delivery is at-least-once and nothing is lost.
// Limits: one changed log is reread whole, and all reviews share one wake-up signal.
const std = @import("std");
const presence = @import("presence.zig");
const Io = std.Io;

pub const Key = [16]u8;
pub const max_note_bytes = 256 * 1024;
const max_log_bytes = 64 * 1024 * 1024;
const note_prefix = "{\"t\":\"note\",\"data\":";
pub const ack_prefix = "{\"t\":\"ack\",\"n\":";
pub const reply_prefix = "{\"t\":\"reply\",\"text\":";

pub const Shared = struct {
    io: Io,
    dir: Io.Dir,
    mutex: Io.Mutex = .init,
    changed: Io.Condition = .init,
    tabs: presence.Table = @splat(null),
    waiters: presence.Table = @splat(null),
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
    const f = try sh.dir.createFile(sh.io, &logName(key), .{ .truncate = false });
    defer f.close(sh.io);
    try f.writePositionalAll(sh.io, lines, try f.length(sh.io));
}

// The body comes from a browser. Reparse it so each log line is one valid JSON line.
// One array becomes one note per item, written in one append.
pub fn send(sh: *Shared, arena: std.mem.Allocator, key: Key, body: []const u8) !void {
    const value = try std.json.parseFromSliceLeaky(std.json.Value, arena, body, .{});
    const items: []const std.json.Value = if (value == .array) value.array.items else &.{value};
    var lines: std.ArrayList(u8) = .empty;
    for (items) |item| {
        const data = try std.json.Stringify.valueAlloc(arena, item, .{});
        try lines.print(arena, "{s}{s}}}\n", .{ note_prefix, data });
    }
    try append(sh, key, lines.items);
    sh.changed.broadcast(sh.io);
}

pub fn ack(sh: *Shared, arena: std.mem.Allocator, key: Key, n: usize) !void {
    try append(sh, key, try std.fmt.allocPrint(arena, "{s}{d}}}\n", .{ ack_prefix, n }));
}

pub fn reply(sh: *Shared, arena: std.mem.Allocator, key: Key, text: []const u8) !void {
    const json = try std.json.Stringify.valueAlloc(arena, text, .{});
    try append(sh, key, try std.fmt.allocPrint(arena, "{s}{s}}}\n", .{ reply_prefix, json }));
}

// Returns "<total>\n" then one undelivered note per line. Returns null after two seconds
// with none, so the caller can check that the agent's command is still there, then call
// again. `seen_size` skips the reread while the log has not grown.
pub fn waitBeat(sh: *Shared, arena: std.mem.Allocator, key: Key, seen_size: *u64) !?[]const u8 {
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    const size = logSize(sh, key) orelse return error.FileNotFound;
    if (size != seen_size.*) {
        seen_size.* = size;
        if (try pending(arena, try readLog(sh, arena, key))) |out| return out;
    }
    const beat: Io.Timeout = .{ .duration = .{ .raw = .{ .nanoseconds = 2 * std.time.ns_per_s }, .clock = .awake } };
    sh.changed.waitTimeout(sh.io, &sh.mutex, beat) catch {};
    return null;
}

fn pending(arena: std.mem.Allocator, log: []const u8) !?[]const u8 {
    var notes: std.ArrayList([]const u8) = .empty;
    var acked: usize = 0;
    var lines = std.mem.splitScalar(u8, log, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, note_prefix)) {
            try notes.append(arena, line[note_prefix.len .. line.len - 1]);
        } else if (std.mem.startsWith(u8, line, ack_prefix)) {
            acked = std.fmt.parseInt(usize, line[ack_prefix.len .. line.len - 1], 10) catch acked;
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
    const log = "{\"t\":\"open\",\"file\":\"x\"}\n" ++ note_prefix ++ "1}\n" ++ note_prefix ++ "2}\n" ++
        ack_prefix ++ "1}\n" ++ note_prefix ++ "{\"a\":3}}\n";
    try std.testing.expectEqualStrings("3\n2\n{\"a\":3}\n", (try pending(arena, log)).?);
    try std.testing.expect(try pending(arena, log ++ ack_prefix ++ "3}\n") == null);
    try std.testing.expect(parseKey("../../etc/passwd!") == null);
    try std.testing.expect(parseKey("0123456789abcdef") != null);
}
