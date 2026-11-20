// Decides who sent one request. This is the daemon's trust boundary.
// Host must name this server, which stops DNS rebinding. One request that writes must
// not carry another site's Origin, which stops other web pages from sending notes.
const std = @import("std");
const Request = std.http.Server.Request;

// command: no Origin header, so it is the show-me program or one local tool.
// browser: the review page, served by this daemon.
pub const Caller = enum { refused, command, browser };

pub fn caller(req: *const Request, port: u16) Caller {
    var names: [2][32]u8 = undefined;
    const a = std.fmt.bufPrint(&names[0], "127.0.0.1:{d}", .{port}) catch unreachable;
    const b = std.fmt.bufPrint(&names[1], "localhost:{d}", .{port}) catch unreachable;
    var host_ok = false;
    var has_origin = false;
    var origin_ok = true;
    var it = req.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, "host")) {
            host_ok = std.mem.eql(u8, h.value, a) or std.mem.eql(u8, h.value, b);
        } else if (std.ascii.eqlIgnoreCase(h.name, "origin")) {
            const site = if (std.mem.startsWith(u8, h.value, "http://")) h.value[7..] else "";
            has_origin = true;
            origin_ok = std.mem.eql(u8, site, a) or std.mem.eql(u8, site, b);
        }
    }
    if (!host_ok) return .refused;
    if (!origin_ok and req.head.method != .GET) return .refused;
    return if (has_origin) .browser else .command;
}
