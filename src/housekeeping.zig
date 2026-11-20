// What the daemon does on its own clock: it removes old pictures, and it stops itself
// when nobody has used it for a while. The next `show-me open` starts it again, and
// every review is still on disk.
// SHOW_ME_IDLE_MINUTES sets the wait before it stops (default 30, 0 means never).
const std = @import("std");
const reviews = @import("reviews.zig");
const Io = std.Io;
const Shared = reviews.Shared;

const picture_days = 7;
const minute = 60 * std.time.ns_per_s;

pub fn start(sh: *Shared) void {
    const t = std.Thread.spawn(.{ .stack_size = 256 * 1024 }, run, .{sh}) catch return;
    t.detach();
}

fn run(sh: *Shared) void {
    const text = sh.env.get("SHOW_ME_IDLE_MINUTES") orelse "30";
    const limit = std.fmt.parseInt(u32, text, 10) catch 30;
    var idle: u32 = 0;
    var minutes: u32 = 0;
    while (true) : (minutes += 1) {
        // Once at start, then once a day.
        if (minutes % (24 * 60) == 0) sweepPictures(sh);
        Io.sleep(sh.io, .{ .nanoseconds = minute }, .awake) catch return;
        idle = if (inUse(sh)) 0 else idle + 1;
        if (limit != 0 and idle >= limit) std.process.exit(0);
    }
}

// In use means one browser tab shows a review, or one agent command waits for notes.
fn inUse(sh: *Shared) bool {
    sh.mutex.lockUncancelable(sh.io);
    defer sh.mutex.unlock(sh.io);
    for (sh.tabs ++ sh.waiters) |slot| {
        if (slot != null) return true;
    }
    return false;
}

// A picture older than seven days is removed. The agent reads pictures within
// minutes of delivery, so by then only the chat preview loses it.
fn sweepPictures(sh: *Shared) void {
    var dir = sh.dir.openDir(sh.io, "images", .{ .iterate = true }) catch return;
    defer dir.close(sh.io);
    const now = Io.Clock.now(.real, sh.io).nanoseconds;
    var it = dir.iterate();
    while (it.next(sh.io) catch null) |entry| {
        const stat = dir.statFile(sh.io, entry.name, .{}) catch continue;
        const age_days = @divFloor(now - stat.mtime.nanoseconds, 24 * 60 * minute);
        if (age_days >= picture_days) dir.deleteFile(sh.io, entry.name) catch {};
    }
}
