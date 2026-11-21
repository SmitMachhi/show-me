// The live events of one review, one stream per open tab: the page changed, the log
// grew, the agent's state changed. "The page" is the HTML file and every local file it
// loaded through show-me (stylesheets, scripts, images), so an edit to any of them
// reloads the page and counts as the agent working.
const std = @import("std");
const reviews = @import("reviews.zig");
const presence = @import("presence.zig");
const Io = std.Io;
const Request = std.http.Server.Request;

// The local files one review's page loaded. A full list only stops watching new ones.
pub const Files = struct {
    n: usize = 0,
    paths: [32][]const u8 = undefined,
};

// Records that the page of `key` loaded the file at `path`. Called when the daemon
// serves one file from the page's folder.
pub fn loaded(sh: *reviews.Shared, key: reviews.Key, path: []const u8) void {
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    const entry = sh.loaded.getOrPut(std.heap.page_allocator, key) catch return;
    if (!entry.found_existing) entry.value_ptr.* = .{};
    const files = entry.value_ptr;
    for (files.paths[0..files.n]) |p| if (std.mem.eql(u8, p, path)) return;
    if (files.n == files.paths.len) return;
    files.paths[files.n] = std.heap.page_allocator.dupe(u8, path) catch return;
    files.n += 1;
}

// The modification times of the page file and of each file it loaded, in the order the
// files were first loaded. Files are only added at the end, so index i is one file.
const Times = struct {
    n: usize = 0,
    t: [33]i96 = undefined,

    // True when one file that both lists hold has one new time. One file that the page
    // loads for the first time is not one change: its first fetch is not one edit.
    fn changed(a: Times, b: Times) bool {
        for (0..@min(a.n, b.n)) |i| if (a.t[i] != b.t[i]) return true;
        return false;
    }
};

fn pageTimes(sh: *reviews.Shared, key: reviews.Key, file: []const u8) Times {
    var paths: [33][]const u8 = undefined;
    paths[0] = file;
    var n: usize = 1;
    {
        sh.mutex.lockUncancelable(sh.io);
        defer sh.mutex.unlock(sh.io);
        if (sh.loaded.get(key)) |files| {
            for (files.paths[0..files.n]) |p| {
                paths[n] = p;
                n += 1;
            }
        }
    }
    var times: Times = .{ .n = n };
    for (paths[0..n], 0..) |p, i| {
        const stat = Io.Dir.cwd().statFile(sh.io, p, .{}) catch null;
        times.t[i] = if (stat) |st| st.mtime.nanoseconds else 0;
    }
    return times;
}

// What one open tab is watching. A change in any field becomes one event.
const Watch = struct {
    times: Times,
    log_size: u64,
    state: presence.State,
    working: bool,

    fn now(sh: *reviews.Shared, key: reviews.Key, file: []const u8, prev: ?Watch) Watch {
        const log_size = reviews.logSize(sh, key) orelse 0;
        // The log is reread only when it grew.
        var working = if (prev) |p| p.working else false;
        if (prev == null or prev.?.log_size != log_size) {
            var tmp = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer tmp.deinit();
            const log = reviews.readLog(sh, tmp.allocator(), key) catch "";
            working = presence.deliveredUnanswered(log);
        }
        return .{
            .times = pageTimes(sh, key, file),
            .log_size = log_size,
            .state = presence.state(sh, key, working),
            .working = working,
        };
    }
};

pub fn serve(sh: *reviews.Shared, req: *Request, arena: std.mem.Allocator, key: reviews.Key) !void {
    const file = try reviews.fileOf(sh, arena, key);
    var buf: [256]u8 = undefined;
    var body = try req.respondStreaming(&buf, .{ .respond_options = .{
        .extra_headers = &.{ .{ .name = "content-type", .value = "text/event-stream" }, .{ .name = "cache-control", .value = "no-store" } },
    } });
    const out = &body.writer;
    const tab = presence.join(sh, &sh.tabs, key);
    presence.markShown(sh, key);
    defer presence.leave(sh, &sh.tabs, tab);
    var last = Watch.now(sh, key, file, null);
    try out.print("data: presence {t}\n\n", .{last.state});
    var tick: u32 = 0;
    while (true) : (tick += 1) {
        // Two buffers sit between here and the socket: the body's, then the connection's.
        try out.flush();
        try body.flush();
        Io.sleep(sh.io, .{ .nanoseconds = 200 * std.time.ns_per_ms }, .awake) catch return;
        const next = Watch.now(sh, key, file, last);
        if (Times.changed(last.times, next.times)) {
            presence.markWorking(sh, key);
            try out.writeAll("data: reload\n\n");
        }
        if (next.log_size != last.log_size) try out.writeAll("data: log\n\n");
        if (next.state != last.state) try out.print("data: presence {t}\n\n", .{next.state});
        // The comment line every 5 s is how one closed tab gets noticed.
        if (tick % 25 == 24) try out.writeAll(": ping\n\n");
        last = next;
    }
}
