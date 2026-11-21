// What the browser loads: the review page, the page-side script, the reviewed file
// with its sibling files, and the reload event stream.
// Limit: file changes are found by checking the modified time every 200 ms.
const std = @import("std");
const reviews = @import("reviews.zig");
const events = @import("events.zig");
const graphs = @import("graphs.zig");
const exporter = @import("export.zig");
const Io = std.Io;
const Request = std.http.Server.Request;
const Header = std.http.Header;

const ui_html = @embedFile("ui.html");
// Order matters: selector.js, card.js and target.js define what inject.js and layout.js call.
const script_tag = "\n<script src=\"/selector.js\"></script><script src=\"/card.js\"></script><script src=\"/target.js\"></script><script src=\"/inject.js\"></script><script src=\"/meta.js\"></script><script src=\"/drafts.js\"></script>" ++
    "<script src=\"/draw.js\"></script><script src=\"/graph.js\"></script><script src=\"/changes.js\"></script><script src=\"/layout.js\"></script>\n";
const max_file_bytes = 64 * 1024 * 1024;
// Sent with every reviewed file, so one opened outside the review frame still has no origin.
const sandbox: Header = .{ .name = "content-security-policy", .value = "sandbox allow-scripts allow-forms allow-popups allow-modals" };
const no_store: Header = .{ .name = "cache-control", .value = "no-store" };
const html: Header = .{ .name = "content-type", .value = "text/html; charset=utf-8" };

// What the frame shows while the page file is gone. The watcher reloads the frame when
// the file is back, so the page returns with no click.
fn missing(arena: std.mem.Allocator, file: []const u8) ![]const u8 {
    var safe: std.ArrayList(u8) = .empty;
    for (file) |c| switch (c) {
        '<' => try safe.appendSlice(arena, "&lt;"),
        '>' => try safe.appendSlice(arena, "&gt;"),
        '&' => try safe.appendSlice(arena, "&amp;"),
        else => try safe.append(arena, c),
    };
    return std.fmt.allocPrint(arena, "<!doctype html><meta charset=\"utf-8\"><title>Page file missing</title>" ++
        "<body style=\"font:15px/1.5 system-ui,sans-serif;margin:40px;color:#555\"><p>The page file is missing:</p>" ++
        "<p><code>{s}</code></p><p>The page comes back here when the file is back.</p>", .{safe.items});
}

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

// Files built into the program. Serves one and returns true, or returns false.
pub fn asset(req: *Request, path: []const u8) !bool {
    const files = [_][3][]const u8{
        .{ "/inject.js", @embedFile("inject.js"), "text/javascript" },
        .{ "/target.js", @embedFile("target.js"), "text/javascript" },
        .{ "/meta.js", @embedFile("meta.js"), "text/javascript" },
        .{ "/drafts.js", @embedFile("drafts.js"), "text/javascript" },
        .{ "/ui-drafts.js", @embedFile("ui-drafts.js"), "text/javascript" },
        .{ "/graph.js", @embedFile("graph.js"), "text/javascript" },
        .{ "/draw.js", @embedFile("draw.js"), "text/javascript" },
        .{ "/card.js", @embedFile("card.js"), "text/javascript" },
        .{ "/ui-view.js", @embedFile("ui-view.js"), "text/javascript" },
        .{ "/ui-bar.js", @embedFile("ui-bar.js"), "text/javascript" },
        .{ "/ui-images.js", @embedFile("ui-images.js"), "text/javascript" },
        .{ "/ui-sketch.js", @embedFile("ui-sketch.js"), "text/javascript" },
        .{ "/ui-changes.js", @embedFile("ui-changes.js"), "text/javascript" },
        .{ "/changes.js", @embedFile("changes.js"), "text/javascript" },
        .{ "/layout.js", @embedFile("layout.js"), "text/javascript" },
        .{ "/selector.js", @embedFile("selector.js"), "text/javascript" },
        .{ "/ui-log.js", @embedFile("ui-log.js"), "text/javascript" },
        .{ "/ui-layout.js", @embedFile("ui-layout.js"), "text/javascript" },
        .{ "/ui-anchors.js", @embedFile("ui-anchors.js"), "text/javascript" },
        .{ "/ui-stream.js", @embedFile("ui-stream.js"), "text/javascript" },
        .{ "/ui-tabs.js", @embedFile("ui-tabs.js"), "text/javascript" },
        .{ "/ui-queue.js", @embedFile("ui-queue.js"), "text/javascript" },
        .{ "/ui.js", @embedFile("ui.js"), "text/javascript" },
        .{ "/ui.css", @embedFile("ui.css"), "text/css" },
    };
    for (files) |f| {
        if (!std.mem.eql(u8, path, f[0])) continue;
        try respond(req, .ok, f[1], &.{ .{ .name = "content-type", .value = f[2] }, no_store });
        return true;
    }
    return false;
}

pub fn mime(path: []const u8) []const u8 {
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
    const data = Io.Dir.cwd().readFileAlloc(sh.io, path, arena, .limited(max_file_bytes)) catch {
        if (sub.len > 0) return respond(req, .not_found, "not found\n", &.{});
        return respond(req, .not_found, try missing(arena, file), &.{ html, sandbox, no_store });
    };
    var body = data;
    if (sub.len > 0) events.loaded(sh, key, path);
    if (sub.len == 0) {
        const drawn = try graphs.expand(.{ .io = sh.io, .dir = sh.dir, .env = sh.env }, arena, data);
        body = try std.mem.concat(arena, u8, &.{ drawn.html, script_tag });
    }
    return respond(req, .ok, body, &.{ .{ .name = "content-type", .value = mime(path) }, sandbox, no_store });
}

// Resolves a sibling file. Returns null unless its real path is inside the reviewed file's folder.
pub fn confine(io: Io, arena: std.mem.Allocator, file: []const u8, sub: []const u8) !?[]const u8 {
    const root = std.fs.path.dirname(file) orelse return null;
    const rel = std.Uri.percentDecodeInPlace(try arena.dupe(u8, sub));
    if (std.mem.findAny(u8, rel, "\\:") != null or std.mem.find(u8, rel, "..") != null) return null;
    const joined = try std.fs.path.join(arena, &.{ root, rel });
    const real = Io.Dir.cwd().realPathFileAlloc(io, joined, arena) catch return null;
    const inside = real.len > root.len and std.mem.startsWith(u8, real, root) and std.fs.path.isSep(real[root.len]);
    return if (inside) real else null;
}

// The standalone copy of the reviewed page, sent as one file to save.
pub fn download(sh: *reviews.Shared, req: *Request, arena: std.mem.Allocator, key: reviews.Key) !void {
    const file = try reviews.fileOf(sh, arena, key);
    const source = try Io.Dir.cwd().readFileAlloc(sh.io, file, arena, .limited(max_file_bytes));
    const body = (try exporter.page(.{ .io = sh.io, .dir = sh.dir, .env = sh.env }, arena, file, source)).html;
    const name = std.fs.path.stem(file);
    const disposition = try std.fmt.allocPrint(arena, "attachment; filename=\"{s}.export.html\"", .{name});
    return respond(req, .ok, body, &.{
        .{ .name = "content-type", .value = "text/html; charset=utf-8" },
        .{ .name = "content-disposition", .value = disposition },
    });
}
