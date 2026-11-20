// The long-lived process. Serves loopback HTTP until told to stop.
// Limits: one thread per connection, loopback only, no TLS.
const std = @import("std");
const builtin = @import("builtin");
const state = @import("state.zig");
const Io = std.Io;
const net = Io.net;
const Request = std.http.Server.Request;

pub fn serve(init: std.process.Init) !void {
    const io = init.io;
    const d = state.dir(io, init.arena.allocator(), init.environ_map);
    const lock = state.lockFile(io, d);
    const stdout = Io.File.stdout();
    if (!try lock.tryLock(io, .exclusive)) {
        // Another daemon won the race. The caller only needs to know one is up.
        return stdout.writeStreamingAll(io, "ready\n");
    }
    const port = state.port(init.environ_map);
    const addr: net.IpAddress = try .parseIp4("127.0.0.1", port);
    // SO_REUSEADDR lets a restart rebind on POSIX. On Windows it would allow a double bind.
    var server = addr.listen(io, .{ .reuse_address = builtin.os.tag != .windows }) catch |e|
        state.fail("cannot listen on 127.0.0.1:{d}: {t}. Set SHOW_ME_PORT to a free port.", .{ port, e });
    try state.writeInfo(io, d, port);
    stdout.writeStreamingAll(io, "ready\n") catch {};
    while (true) {
        const s = server.accept(io) catch continue;
        const t = std.Thread.spawn(.{ .stack_size = 256 * 1024 }, handle, .{ io, s, port }) catch {
            s.close(io);
            continue;
        };
        t.detach();
    }
}

fn handle(io: Io, s: net.Stream, port: u16) void {
    defer s.close(io);
    var in_buf: [8192]u8 = undefined;
    var out_buf: [4096]u8 = undefined;
    var in = s.reader(io, &in_buf);
    var out = s.writer(io, &out_buf);
    var http = std.http.Server.init(&in.interface, &out.interface);
    var req = http.receiveHead() catch return;
    route(&req, port) catch {};
}

fn route(req: *Request, port: u16) !void {
    if (!allowed(req, port)) {
        return req.respond("forbidden\n", .{ .status = .forbidden, .keep_alive = false });
    }
    const target = req.head.target;
    const path = target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len];
    const method = req.head.method;
    if (method == .GET and std.mem.eql(u8, path, "/health")) {
        return req.respond(state.version, .{ .keep_alive = false });
    }
    if (method == .POST and std.mem.eql(u8, path, "/shutdown")) {
        try req.respond("bye\n", .{ .keep_alive = false });
        std.process.exit(0);
    }
    return req.respond("not found\n", .{ .status = .not_found, .keep_alive = false });
}

// DNS-rebinding and cross-site guard: Host must name this server, and a request that
// writes must not carry another site's Origin. The CLI sends no Origin.
fn allowed(req: *const Request, port: u16) bool {
    var names: [2][32]u8 = undefined;
    const a = std.fmt.bufPrint(&names[0], "127.0.0.1:{d}", .{port}) catch unreachable;
    const b = std.fmt.bufPrint(&names[1], "localhost:{d}", .{port}) catch unreachable;
    var host_ok = false;
    var origin_ok = true;
    var it = req.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "host")) {
            host_ok = std.mem.eql(u8, h.value, a) or std.mem.eql(u8, h.value, b);
        } else if (std.ascii.eqlIgnoreCase(h.name, "origin")) {
            const site = if (std.mem.startsWith(u8, h.value, "http://")) h.value[7..] else "";
            origin_ok = std.mem.eql(u8, site, a) or std.mem.eql(u8, site, b);
        }
    }
    return host_ok and (origin_ok or req.head.method == .GET);
}
