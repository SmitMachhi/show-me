// What a short-lived command needs from the daemon: make sure one runs, and call it.
const std = @import("std");
const builtin = @import("builtin");
const state = @import("state.zig");
const Io = std.Io;
const net = Io.net;

pub fn running(io: Io, d: Io.Dir) bool {
    const lock = state.lockFile(io, d);
    defer lock.close(io);
    const free = lock.tryLock(io, .exclusive) catch return true;
    if (free) lock.unlock(io);
    return !free;
}

// Returns the port of a daemon of this exact version, starting or replacing one if needed.
pub fn ensureDaemon(init: std.process.Init) u16 {
    const io = init.io;
    const arena = init.arena.allocator();
    const d = state.dir(io, arena, init.environ_map);
    if (!running(io, d)) spawnDaemon(io);
    var info = waitInfo(io, arena, d);
    if (std.mem.eql(u8, info.version, state.version)) return info.port;

    // An older or newer daemon is up. Its state is on disk, so replace it.
    _ = call(io, info.port, "POST", "/shutdown", &.{}) catch {};
    var tries: u32 = 0;
    while (running(io, d)) : (tries += 1) {
        if (tries == 400) state.fail("the running show-me daemon did not stop. End it, then retry.", .{});
        pause(io);
    }
    spawnDaemon(io);
    info = waitInfo(io, arena, d);
    return info.port;
}

fn pause(io: Io) void {
    Io.sleep(io, .{ .nanoseconds = 5 * std.time.ns_per_ms }, .awake) catch {};
}

fn waitInfo(io: Io, arena: std.mem.Allocator, d: Io.Dir) state.Info {
    var tries: u32 = 0;
    while (tries < 400) : (tries += 1) {
        if (state.readInfo(io, arena, d)) |info| return info;
        pause(io);
    }
    state.fail("the daemon started but wrote no daemon.json. Run `show-me serve` to see why.", .{});
}

// Starts `show-me serve` detached and waits for its "ready" line.
fn spawnDaemon(io: Io) void {
    var path: [Io.Dir.max_path_bytes]u8 = undefined;
    const n = std.process.executablePath(io, &path) catch |e|
        state.fail("cannot find the show-me program path: {t}", .{e});
    var child = std.process.spawn(io, .{
        .argv = &.{ path[0..n], "serve" },
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .ignore,
        .create_no_window = true,
        .pgid = if (builtin.os.tag == .windows) null else 0,
    }) catch |e| state.fail("cannot start the daemon: {t}", .{e});
    var line: [16]u8 = undefined;
    var bufs = [_][]u8{&line};
    const got = child.stdout.?.readStreaming(io, &bufs) catch 0;
    if (!std.mem.startsWith(u8, line[0..got], "ready")) {
        state.fail("the daemon did not start. Run `show-me serve` to see why.", .{});
    }
}

// One HTTP request to the daemon. Returns the response body inside `buf`.
pub fn call(io: Io, port: u16, method: []const u8, path: []const u8, buf: []u8) ![]const u8 {
    const addr: net.IpAddress = try .parseIp4("127.0.0.1", port);
    const s = try addr.connect(io, .{ .mode = .stream });
    defer s.close(io);
    var out_buf: [512]u8 = undefined;
    var w = s.writer(io, &out_buf);
    try w.interface.print(
        "{s} {s} HTTP/1.1\r\nHost: 127.0.0.1:{d}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        .{ method, path, port },
    );
    try w.interface.flush();
    var in_buf: [8192]u8 = undefined;
    var sr = s.reader(io, &in_buf);
    const r = &sr.interface;
    while (r.buffered().len < in_buf.len) r.fillMore() catch break;
    const all = r.buffered();
    const head_end = std.mem.find(u8, all, "\r\n\r\n") orelse return error.BadResponse;
    const body = all[head_end + 4 ..];
    const len = @min(body.len, buf.len);
    @memcpy(buf[0..len], body[0..len]);
    return buf[0..len];
}
