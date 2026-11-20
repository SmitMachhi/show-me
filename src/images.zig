// Pictures the reviewer attaches to notes. Each is stored once, named by the hash of
// its bytes, in <state>/images. The agent gets the file path, never the bytes.
// Limits: 10 MiB each, and PNG, JPEG or WebP only. The first bytes decide the type;
// the name and the Content-Type header are ignored.
// Not built: removal of old pictures. The folder only grows.
const std = @import("std");
const reviews = @import("reviews.zig");
const Shared = reviews.Shared;

pub const max_bytes = 10 * 1024 * 1024;
const hex_len = 24;

fn extension(bytes: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, bytes, "\x89PNG\r\n\x1a\n")) return "png";
    if (std.mem.startsWith(u8, bytes, "\xff\xd8\xff")) return "jpg";
    if (bytes.len > 12 and std.mem.eql(u8, bytes[0..4], "RIFF") and std.mem.eql(u8, bytes[8..12], "WEBP")) return "webp";
    return null;
}

// An id is "<24 hex>.<png|jpg|webp>". Ids arrive from the browser and become file
// names, so nothing else may pass.
pub fn valid(id: []const u8) bool {
    if (id.len < hex_len + 4 or id[hex_len] != '.') return false;
    for (id[0..hex_len]) |c| {
        if (!std.ascii.isDigit(c) and !(c >= 'a' and c <= 'f')) return false;
    }
    const ext = id[hex_len + 1 ..];
    return std.mem.eql(u8, ext, "png") or std.mem.eql(u8, ext, "jpg") or std.mem.eql(u8, ext, "webp");
}

pub fn mime(id: []const u8) []const u8 {
    if (std.mem.endsWith(u8, id, "png")) return "image/png";
    return if (std.mem.endsWith(u8, id, "jpg")) "image/jpeg" else "image/webp";
}

// Saves one picture and returns its id.
pub fn store(sh: *Shared, arena: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    const ext = extension(bytes) orelse return error.NotAnImage;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const id = try std.fmt.allocPrint(arena, "{s}.{s}", .{ std.fmt.bytesToHex(digest[0 .. hex_len / 2].*, .lower), ext });
    const dir = try sh.dir.createDirPathOpen(sh.io, "images", .{});
    defer dir.close(sh.io);
    dir.access(sh.io, id, .{}) catch try dir.writeFile(sh.io, .{ .sub_path = id, .data = bytes });
    return id;
}

pub fn read(sh: *Shared, arena: std.mem.Allocator, id: []const u8) ![]const u8 {
    if (!valid(id)) return error.FileNotFound;
    const path = try std.fs.path.join(arena, &.{ "images", id });
    return sh.dir.readFileAlloc(sh.io, path, arena, .limited(max_bytes));
}

// In one note, replaces each picture id under "images" with the file's real path.
// An id that is not valid or not stored is dropped.
pub fn resolve(sh: *Shared, arena: std.mem.Allocator, note: *std.json.Value) !void {
    if (note.* != .object) return;
    const list = note.object.getPtr("images") orelse return;
    if (list.* != .array) return;
    var paths: std.json.Array = .init(arena);
    for (list.array.items) |item| {
        if (item != .string or !valid(item.string)) continue;
        const rel = try std.fs.path.join(arena, &.{ "images", item.string });
        const real = sh.dir.realPathFileAlloc(sh.io, rel, arena) catch continue;
        try paths.append(.{ .string = real });
    }
    list.* = .{ .array = paths };
}

test "only image bytes and well-formed ids pass" {
    try std.testing.expectEqualStrings("png", extension("\x89PNG\r\n\x1a\n....").?);
    try std.testing.expectEqualStrings("jpg", extension("\xff\xd8\xff\xe0").?);
    try std.testing.expectEqualStrings("webp", extension("RIFF\x00\x00\x00\x00WEBPVP8 ").?);
    try std.testing.expect(extension("<svg onload=alert(1)>") == null);
    try std.testing.expect(valid("0123456789abcdef01234567.png"));
    try std.testing.expect(!valid("../../daemon.json") and !valid("0123456789abcdef01234567.exe"));
}
