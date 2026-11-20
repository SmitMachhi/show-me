// What the browser loads: the review page, the page-side script, the reviewed file
// with its sibling files, and the reload event stream.
// Limit: file changes are found by checking the modified time every 200 ms.
const std = @import("std");
const reviews = @import("reviews.zig");
const Io = std.Io;
const Request = std.http.Server.Request;
const Header = std.http.Header;

const ui_html = @embedFile("ui.html");
const inject_js = @embedFile("inject.js");
const script_tag = "\n<script src=\"/inject.js\"></script>\n";
const max_file_bytes = 64 * 1024 * 1024;
// Sent with every reviewed file, so one opened outside the review frame still has no origin.
const sandbox: Header = .{ .name = "content-security-policy", .value = "sandbox allow-scripts allow-forms allow-popups allow-modals" };
const no_store: Header = .{ .name = "cache-control", .value = "no-store" };

fn respond(req: *Request, status: std.http.Status, body: []const u8, headers: []const Header) !void {
    return req.respond(body, .{ .status = status, .keep_alive = false, .extra_headers = headers });
}

pub fn page(req: *Request) !void {
    return respond(req, .ok, ui_html, &.{
        .{ .name = "content-type", .value = "text/html; charset=utf-8" },
        .{ .name = "x-frame-options", .value = "DENY" },
        no_store,
    });
}

pub fn script(req: *Request) !void {
    return respond(req, .ok, inject_js, &.{ .{ .name = "content-type", .value = "text/javascript" }, no_store });
}

fn mime(path: []const u8) []const u8 {
    const types = [_][2][]const u8{
        .{ ".html", "text/html; charset=utf-8" }, .{ ".htm", "text/html; charset=utf-8" },
        .{ ".css", "text/css" },                  .{ ".js", "text/javascript" },
        .{ ".mjs", "text/javascript" },           .{ ".json", "application/json" },
        .{ ".svg", "image/svg+xml" },             .{ ".png", "image/png" },
        .{ ".jpg", "image/jpeg" },                .{ ".jpeg", "image/jpeg" },
        .{ ".gif", "image/gif" },                 .{ ".webp", "image/webp" },
        .{ ".woff2", "font/woff2" },              .{ ".txt", "text/plain; charset=utf-8" },
    };
    for (types) |t| {
        if (std.ascii.endsWithIgnoreCase(path, t[0])) return t[1];
    }
    return "application/octet-stream";
}

// `sub` is the URL path after /a/<key>/. Empty means the reviewed file itself.
pub fn artifact(sh: *reviews.Shared, req: *Request, arena: std.mem.Allocator, key: reviews.Key, sub: []const u8) !void {
    const file = try reviews.fileOf(sh, arena, key);
    const path = if (sub.len == 0) file else (try confine(sh.io, arena, file, sub)) orelse
        return respond(req, .not_found, "not found\n", &.{});
    const data = Io.Dir.cwd().readFileAlloc(sh.io, path, arena, .limited(max_file_bytes)) catch
        return respond(req, .not_found, "not found\n", &.{});
    const body = if (sub.len == 0) try std.mem.concat(arena, u8, &.{ data, script_tag }) else data;
    return respond(req, .ok, body, &.{ .{ .name = "content-type", .value = mime(path) }, sandbox, no_store });
}

// Resolves a sibling file. Returns null unless its real path is inside the reviewed file's folder.
fn confine(io: Io, arena: std.mem.Allocator, file: []const u8, sub: []const u8) !?[]const u8 {
    const root = std.fs.path.dirname(file) orelse return null;
    const rel = std.Uri.percentDecodeInPlace(try arena.dupe(u8, sub));
    if (std.mem.findAny(u8, rel, "\\:") != null or std.mem.find(u8, rel, "..") != null) return null;
    const joined = try std.fs.path.join(arena, &.{ root, rel });
    const real = Io.Dir.cwd().realPathFileAlloc(io, joined, arena) catch return null;
    const inside = real.len > root.len and std.mem.startsWith(u8, real, root) and std.fs.path.isSep(real[root.len]);
    return if (inside) real else null;
}

// Server-sent events. One "reload" each time the reviewed file changes.
pub fn events(sh: *reviews.Shared, req: *Request, arena: std.mem.Allocator, key: reviews.Key) !void {
    const file = try reviews.fileOf(sh, arena, key);
    var buf: [256]u8 = undefined;
    var body = try req.respondStreaming(&buf, .{ .respond_options = .{
        .extra_headers = &.{ .{ .name = "content-type", .value = "text/event-stream" }, no_store },
    } });
    const tab = reviews.tabOpen(sh, key);
    defer reviews.tabClose(sh, tab);
    var last = modified(sh.io, file);
    var tick: u32 = 0;
    while (true) : (tick += 1) {
        Io.sleep(sh.io, .{ .nanoseconds = 200 * std.time.ns_per_ms }, .awake) catch return;
        const now = modified(sh.io, file);
        // The comment line every 5 s is how one closed tab gets noticed.
        const msg = if (now != last) "data: reload\n\n" else if (tick % 25 == 0) ": ping\n\n" else continue;
        last = now;
        body.writer.writeAll(msg) catch return;
        // Two buffers sit between here and the socket: the body's, then the connection's.
        body.writer.flush() catch return;
        body.flush() catch return;
    }
}

fn modified(io: Io, file: []const u8) i96 {
    const stat = Io.Dir.cwd().statFile(io, file, .{}) catch return 0;
    return stat.mtime.nanoseconds;
}
