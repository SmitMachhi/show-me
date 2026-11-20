// The long-lived process. Serves loopback HTTP until told to stop.
// Limits: one thread per connection, loopback only, no TLS.
const std = @import("std");
const builtin = @import("builtin");
const state = @import("state.zig");
const reviews = @import("reviews.zig");
const pages = @import("pages.zig");
const presence = @import("presence.zig");
const guard = @import("guard.zig");
const images = @import("images.zig");
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
    var shared: reviews.Shared = .{ .io = io, .dir = d, .env = init.environ_map };
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

const Call = struct {
    sh: *reviews.Shared,
    req: *Request,
    arena: std.mem.Allocator,
    from: guard.Caller,
    body: []const u8 = "",
};

fn is(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn route(sh: *reviews.Shared, req: *Request, port: u16, arena: std.mem.Allocator) !void {
    var c: Call = .{ .sh = sh, .req = req, .arena = arena, .from = guard.caller(req, port) };
    if (c.from == .refused) return reply(req, .forbidden, "forbidden\n");
    const method = req.head.method;
    const target = req.head.target;
    // Reading the body invalidates the head, so copy the path out first.
    const path = try arena.dupe(u8, target[0 .. std.mem.findScalar(u8, target, '?') orelse target.len]);
    if (method == .POST) {
        var body_buf: [4096]u8 = undefined;
        const r = try req.readerExpectContinue(&body_buf);
        const is_image = std.mem.startsWith(u8, path, "/image/");
        const limit: usize = if (is_image) images.max_bytes else reviews.max_note_bytes;
        c.body = r.allocRemaining(arena, .limited(limit)) catch
            return reply(req, .payload_too_large, "body too large\n");
    }
    if (method == .GET and is(path, "/health")) return reply(req, .ok, state.version);
    if (method == .POST and is(path, "/shutdown")) {
        try reply(req, .ok, "bye\n");
        std.process.exit(0);
    }
    if (method == .GET and try pages.asset(req, path)) return;
    if (method == .POST and is(path, "/reviews")) return register(c);

    // Everything else has the form /<action>/<key>.
    const slash = std.mem.findScalarPos(u8, path, 1, '/') orelse return reply(req, .not_found, "not found\n");
    const rest = path[slash + 1 ..];
    const key = reviews.parseKey(rest[0..@min(rest.len, 16)]) orelse return reply(req, .not_found, "not found\n");
    if (!reviews.exists(sh, key)) return reply(req, .not_found, "no such review\n");
    const action = path[1..slash];
    if (method == .GET and is(action, "a")) {
        return pages.artifact(sh, req, arena, key, std.mem.trimStart(u8, rest[16..], "/"));
    }
    if (method == .GET and is(action, "image")) {
        const id = std.mem.trimStart(u8, rest[16..], "/");
        const bytes = images.read(sh, arena, id) catch return reply(req, .not_found, "not found\n");
        return req.respond(bytes, .{ .keep_alive = false, .extra_headers = &.{
            .{ .name = "content-type", .value = images.mime(id) },
            .{ .name = "x-content-type-options", .value = "nosniff" },
        } });
    }
    if (rest.len != 16) return reply(req, .not_found, "not found\n");
    return if (method == .GET) get(c, action, key) else post(c, action, key);
}

// Answers with the key, how many browser tabs already show the review, and who ended it.
fn register(c: Call) !void {
    const key = reviews.register(c.sh, c.arena, c.body) catch return reply(c.req, .bad_request, "bad path\n");
    const ended = reviews.endedBy(try reviews.readLog(c.sh, c.arena, key)) orelse "open";
    const tabs = presence.count(c.sh, &c.sh.tabs, key);
    return reply(c.req, .ok, try std.fmt.allocPrint(c.arena, "{s} {d} {s}", .{ key, tabs, ended }));
}

fn get(c: Call, action: []const u8, key: reviews.Key) !void {
    if (is(action, "r")) return pages.page(c.req);
    if (is(action, "events")) return pages.events(c.sh, c.req, c.arena, key);
    if (is(action, "log")) return reply(c.req, .ok, try reviews.readLog(c.sh, c.arena, key));
    if (is(action, "export")) return pages.download(c.sh, c.req, c.arena, key);
    if (is(action, "wait")) return wait(c.sh, c.req, c.arena, key);
    return reply(c.req, .not_found, "not found\n");
}

fn post(c: Call, action: []const u8, key: reviews.Key) !void {
    if (is(action, "send")) {
        if (reviews.endedBy(try reviews.readLog(c.sh, c.arena, key)) != null) {
            return reply(c.req, .conflict, "the review has ended\n");
        }
        reviews.send(c.sh, c.arena, key, c.body) catch return reply(c.req, .bad_request, "body must be JSON\n");
    } else if (is(action, "image")) {
        const id = images.store(c.sh, c.arena, c.body) catch
            return reply(c.req, .unsupported_media_type, "only PNG, JPEG and WebP pictures\n");
        return reply(c.req, .ok, id);
    } else if (is(action, "reply")) {
        try reviews.reply(c.sh, c.arena, key, c.body);
    } else if (is(action, "end")) {
        try reviews.end(c.sh, c.arena, key, c.from == .browser);
    } else if (is(action, "start")) {
        try reviews.start(c.sh, key);
    } else if (is(action, "ack")) {
        const n = std.fmt.parseInt(usize, std.mem.trim(u8, c.body, " \r\n"), 10) catch
            return reply(c.req, .bad_request, "body must be a number\n");
        try reviews.ack(c.sh, c.arena, key, n);
    } else {
        return reply(c.req, .not_found, "not found\n");
    }
    return reply(c.req, .ok, "ok\n");
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
