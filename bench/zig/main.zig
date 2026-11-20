// Benchmark mini-daemon. Spec: bench/README is the harness; routes /health /wait /send /quit.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const net = Io.net;

const max_body = 64 * 1024;

// Shared /wait state: a generation counter and the last POST /send body.
var mutex: Io.Mutex = .init;
var cond: Io.Condition = .init;
var gen: u64 = 0;
var msg: [max_body]u8 = undefined;
var msg_len: usize = 0;

fn respond(io: Io, s: net.Stream, code: []const u8, body: []const u8) void {
    var wbuf: [256]u8 = undefined;
    var w = s.writer(io, &wbuf);
    const out = &w.interface;
    out.print("HTTP/1.1 {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ code, body.len }) catch return;
    out.writeAll(body) catch return;
    out.flush() catch return;
}

fn contentLength(head: []const u8) usize {
    const key = "\ncontent-length:";
    const i = std.ascii.findIgnoreCase(head, key) orelse return 0;
    const rest = head[i + key.len ..];
    const end = std.mem.find(u8, rest, "\r") orelse rest.len;
    return std.fmt.parseInt(usize, std.mem.trim(u8, rest[0..end], " \t"), 10) catch 0;
}

fn handle(io: Io, s: net.Stream) void {
    defer s.close(io);
    var buf: [max_body + 8192]u8 = undefined;
    var sr = s.reader(io, &buf);
    const r = &sr.interface;
    // Nothing is ever consumed from the reader, so buffered() is the whole request so far.
    const head_end = while (true) {
        if (std.mem.find(u8, r.buffered(), "\r\n\r\n")) |i| break i + 4;
        if (r.buffered().len == buf.len) return;
        r.fillMore() catch return;
    };
    const head = r.buffered()[0..head_end];

    if (std.mem.startsWith(u8, head, "GET /health")) {
        respond(io, s, "200 OK", "ok");
    } else if (std.mem.startsWith(u8, head, "GET /wait")) {
        mutex.lockUncancelable(io);
        const seen = gen;
        while (gen == seen) cond.waitUncancelable(io, &mutex);
        const n = msg_len;
        @memcpy(buf[0..n], msg[0..n]); // the request buffer is free now; copy under the lock
        mutex.unlock(io);
        respond(io, s, "200 OK", buf[0..n]);
    } else if (std.mem.startsWith(u8, head, "POST /send")) {
        const len = @min(contentLength(head), max_body, buf.len - head_end);
        r.fill(head_end + len) catch {}; // short body: use what arrived
        const all = r.buffered();
        const body = all[head_end..@min(all.len, head_end + len)];
        mutex.lockUncancelable(io);
        gen += 1;
        msg_len = body.len;
        @memcpy(msg[0..body.len], body);
        cond.broadcast(io);
        mutex.unlock(io);
        respond(io, s, "200 OK", "ok");
    } else if (std.mem.startsWith(u8, head, "GET /quit")) {
        respond(io, s, "200 OK", "bye");
        s.close(io);
        std.process.exit(0);
    } else {
        respond(io, s, "404 Not Found", "no");
    }
}

fn ping(io: Io, addr: *const net.IpAddress) !void {
    const s = try addr.connect(io, .{ .mode = .stream });
    defer s.close(io);
    var wbuf: [128]u8 = undefined;
    var w = s.writer(io, &wbuf);
    try w.interface.writeAll("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n");
    try w.interface.flush();
    var rbuf: [4096]u8 = undefined;
    var sr = s.reader(io, &rbuf);
    const r = &sr.interface;
    while (r.buffered().len < rbuf.len) r.fillMore() catch break; // read until EOF
    if (std.mem.find(u8, r.buffered(), "200") == null) return error.BadStatus;
    try Io.File.stdout().writeStreamingAll(io, "ok\n");
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) std.process.exit(2);
    const port = try std.fmt.parseInt(u16, args[2], 10);
    const addr: net.IpAddress = try .parseIp4("127.0.0.1", port);

    if (std.mem.eql(u8, args[1], "ping")) {
        ping(io, &addr) catch std.process.exit(1);
        return;
    }

    // SO_REUSEADDR lets a restart rebind through TIME_WAIT on POSIX; on Windows it would allow a double bind.
    var server = try addr.listen(io, .{ .reuse_address = builtin.os.tag != .windows });
    try Io.File.stdout().writeStreamingAll(io, "ready\n");
    while (true) {
        const s = server.accept(io) catch continue;
        const t = std.Thread.spawn(.{ .stack_size = 512 * 1024 }, handle, .{ io, s }) catch {
            s.close(io);
            continue;
        };
        t.detach();
    }
}
