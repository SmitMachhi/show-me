// Where show-me keeps its files, and how one process tells if the daemon is alive.
// The daemon holds an exclusive lock on daemon.lock for its whole life. A free lock
// means no daemon. This never needs a network probe (slow on Windows when nothing listens).
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Env = std.process.Environ.Map;

pub const version = "0.0.8";
pub const default_port: u16 = 4388;

pub const Info = struct { port: u16, version: []const u8 };

pub fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("show-me: " ++ fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn port(env: *const Env) u16 {
    const text = env.get("SHOW_ME_PORT") orelse return default_port;
    return std.fmt.parseInt(u16, text, 10) catch
        fail("SHOW_ME_PORT must be a port number, got '{s}'", .{text});
}

// Opens the state folder, creating it on first use. SHOW_ME_STATE_DIR overrides ~/.show-me.
pub fn dir(io: Io, arena: std.mem.Allocator, env: *const Env) Io.Dir {
    const path = env.get("SHOW_ME_STATE_DIR") orelse blk: {
        const home_key = if (builtin.os.tag == .windows) "USERPROFILE" else "HOME";
        const home = env.get(home_key) orelse
            fail("{s} is not set. Set SHOW_ME_STATE_DIR to a folder show-me can write to.", .{home_key});
        break :blk std.fs.path.join(arena, &.{ home, ".show-me" }) catch fail("out of memory", .{});
    };
    return Io.Dir.cwd().createDirPathOpen(io, path, .{}) catch |e|
        fail("cannot create state folder '{s}': {t}", .{ path, e });
}

pub fn lockFile(io: Io, d: Io.Dir) Io.File {
    return d.createFile(io, "daemon.lock", .{ .truncate = false }) catch |e|
        fail("cannot open daemon.lock in the state folder: {t}", .{e});
}

pub fn writeInfo(io: Io, d: Io.Dir, p: u16) !void {
    var buf: [96]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, "{{\"port\":{d},\"version\":\"{s}\"}}\n", .{ p, version });
    try d.writeFile(io, .{ .sub_path = "daemon.json", .data = text });
}

pub fn readInfo(io: Io, arena: std.mem.Allocator, d: Io.Dir) ?Info {
    var buf: [256]u8 = undefined;
    const text = d.readFile(io, "daemon.json", &buf) catch return null;
    return std.json.parseFromSliceLeaky(Info, arena, text, .{ .ignore_unknown_fields = true }) catch null;
}
