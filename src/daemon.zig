// The long-lived process. Serves loopback HTTP until told to stop.
// Limits: one thread per connection, loopback only, no TLS.
const std = @import("std");
const builtin = @import("builtin");
const state = @import("state.zig");
const reviews = @import("reviews.zig");
const pages = @import("pages.zig");
const presence = @import("presence.zig");
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
    var shared: reviews.Shared = .{ .io = io, .dir = d };
    while (true) {
        const s = server.accept(io) catch continue;
        const t = std.Thread.spawn(.{ .stack_size = 256 * 1024 }, handle, .{ &shared, s, port }) catch {
            s.close(io);
            continue;
        };
        t.detach();
    }
}

fn handle(sh: *reviews.Shared, s: net.Stream, port: u16) void {
    defer s.close(sh.io);
    var in_buf: [8192]u8 = undefined;
    var out_buf: [4096]u8 = undefined;
    var in = s.reader(sh.io, &in_buf);
    var out = s.writer(sh.io, &out_buf);
    var http = std.http.Server.init(&in.interface, &out.interface);
    var req = http.receiveHead() catch return;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    route(sh, &req, port, arena.allocator()) catch {};
}

fn reply(req: *Request, status: std.http.Status, text: []const u8) !void {
    return req.respond(text, .{ .status = status, .keep_alive = false });
}

fn route(sh: *reviews.Shared, req: *Request, port: u16, arena: std.mem.Allocator) !void {
    if (!allowed(req, port)) return reply(req, .forbidden, "forbidden\n");
    const method = req.head.method;
    const target = req.head.target;
    // Reading the body invalidates the head, so copy the path out first.
    const path = try arena.dupe(u8, target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len]);
    var body: []const u8 = "";
    if (method == .POST) {
        var body_buf: [4096]u8 = undefined;
        const r = try req.readerExpectContinue(&body_buf);
        body = r.allocRemaining(arena, .limited(reviews.max_note_bytes)) catch
            return reply(req, .payload_too_large, "body too large\n");
    }
    if (method == .GET and std.mem.eql(u8, path, "/health")) return reply(req, .ok, state.version);
    if (method == .POST and std.mem.eql(u8, path, "/shutdown")) {
        try reply(req, .ok, "bye\n");
        std.process.exit(0);
    }
    if (method == .GET and std.mem.eql(u8, path, "/inject.js")) return pages.script(req);
    if (method == .POST and std.mem.eql(u8, path, "/reviews")) {
        const key = reviews.register(sh, arena, body) catch return reply(req, .bad_request, "bad path\n");
        // Key, then how many browser tabs already show this review.
        return reply(req, .ok, try std.fmt.allocPrint(arena, "{s} {d}", .{ key, presence.count(sh, &sh.tabs, key) }));
    }
    return routeReview(sh, req, arena, method, path, body);
}

// Routes of the form /<action>/<key>.
fn routeReview(
    sh: *reviews.Shared,
    req: *Request,
    arena: std.mem.Allocator,
    method: std.http.Method,
    path: []const u8,
    body: []const u8,
) !void {
    const slash = std.mem.findScalarPos(u8, path, 1, '/') orelse return reply(req, .not_found, "not found\n");
    const action = path[1..slash];
    const rest = path[slash + 1 ..];
    const key = reviews.parseKey(rest[0..@min(rest.len, 16)]) orelse return reply(req, .not_found, "not found\n");
    if (!reviews.exists(sh, key)) return reply(req, .not_found, "no such review\n");
    const is = struct {
        fn is(a: []const u8, b: []const u8) bool {
            return std.mem.eql(u8, a, b);
        }
    }.is;
    if (method == .GET and is(action, "a")) {
        return pages.artifact(sh, req, arena, key, std.mem.trimStart(u8, rest[16..], "/"));
    }
    if (rest.len != 16) return reply(req, .not_found, "not found\n");
    if (method == .GET) {
        if (is(action, "r")) return pages.page(req);
        if (is(action, "events")) return pages.events(sh, req, arena, key);
        if (is(action, "log")) return reply(req, .ok, try reviews.readLog(sh, arena, key));
        if (is(action, "wait")) return wait(sh, req, arena, key);
    } else if (is(action, "send")) {
        reviews.send(sh, arena, key, body) catch return reply(req, .bad_request, "body must be JSON\n");
        return reply(req, .ok, "ok\n");
    } else if (is(action, "reply")) {
        try reviews.reply(sh, arena, key, body);
        return reply(req, .ok, "ok\n");
    } else if (is(action, "ack")) {
        const n = std.fmt.parseInt(usize, std.mem.trim(u8, body, " \r\n"), 10) catch
            return reply(req, .bad_request, "body must be a number\n");
        try reviews.ack(sh, arena, key, n);
        return reply(req, .ok, "ok\n");
    }
    return reply(req, .not_found, "not found\n");
}

// Holds the agent's request open until notes exist. One space goes out every two
// seconds: when that write fails the agent's command is gone, and the reviewer stops
// being told that one agent listens.
fn wait(sh: *reviews.Shared, req: *Request, arena: std.mem.Allocator, key: reviews.Key) !void {
    var buf: [64]u8 = undefined;
    var body = try req.respondStreaming(&buf, .{
        .respond_options = .{ .keep_alive = false, .transfer_encoding = .none },
    });
    const slot = presence.join(sh, &sh.waiters, key);
    defer presence.leave(sh, &sh.waiters, slot);
    var seen_size: u64 = std.math.maxInt(u64);
    while (true) {
        const notes = try reviews.waitBeat(sh, arena, key, &seen_size);
        try body.writer.writeAll(notes orelse " ");
        try body.writer.flush();
        try body.flush();
        if (notes != null) return;
    }
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
