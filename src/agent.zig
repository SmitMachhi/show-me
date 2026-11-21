// The commands one agent runs against one review that is already open:
// wait for notes, reply, and end.
const std = @import("std");
const state = @import("state.zig");
const client = @import("client.zig");
const reviews = @import("reviews.zig");
const Io = std.Io;

const Review = struct { port: u16, key: reviews.Key, file: []const u8 };

pub fn say(io: Io, text: []const u8) void {
    Io.File.stdout().writeStreamingAll(io, text) catch {};
}

// Checks the file argument and returns its real path. Two spellings of one file are one review.
pub fn realFile(init: std.process.Init, args: []const []const u8, cmd: []const u8) []const u8 {
    if (args.len < 3) state.fail("{s} needs one file. Example: show-me {s} plan.html", .{ cmd, cmd });
    const file = args[2];
    const is_html = std.ascii.endsWithIgnoreCase(file, ".html") or std.ascii.endsWithIgnoreCase(file, ".htm");
    if (!is_html) state.fail("'{s}' is not an .html file. show-me reviews HTML pages only.", .{file});
    return Io.Dir.cwd().realPathFileAlloc(init.io, file, init.arena.allocator()) catch
        state.fail("cannot read '{s}'. Check the path.", .{file});
}

fn find(init: std.process.Init, args: []const []const u8, cmd: []const u8) Review {
    const arena = init.arena.allocator();
    const path = realFile(init, args, cmd);
    const d = state.dir(init.io, arena, init.environ_map);
    const info = if (client.running(init.io, d)) state.readInfo(init.io, arena, d) else null;
    const port = (info orelse state.fail("no review is open. Run: show-me open {s}", .{args[2]})).port;
    return .{ .port = port, .key = reviews.keyOf(path), .file = args[2] };
}

// One POST to /<action>/<key>. Fails with what to do when the review is not open.
fn post(init: std.process.Init, r: Review, comptime action: []const u8, body: []const u8) void {
    const res = client.call(init.io, init.arena.allocator(), r.port, "POST", "/" ++ action ++ "/" ++ r.key, body) catch |e|
        state.fail("the daemon did not answer: {t}. Run: show-me open {s}", .{ e, r.file });
    if (res.status != 200) state.fail("no review is open for this file. Run: show-me open {s}", .{r.file});
}

fn sendReply(init: std.process.Init, r: Review, text: []const u8) void {
    if (std.mem.trim(u8, text, " \r\n\t").len == 0) state.fail("the reply is empty. Give the reply text.", .{});
    post(init, r, "reply", text);
}

// The reply text: args[at] itself, or the content of the file named after `file_flag`.
// A file keeps line breaks and any characters that the shell would change.
fn replyText(init: std.process.Init, args: []const []const u8, at: usize, comptime file_flag: []const u8) []const u8 {
    if (!std.mem.eql(u8, args[at], file_flag)) return args[at];
    if (at + 1 >= args.len) state.fail(file_flag ++ " needs one file name.", .{});
    const text = Io.Dir.cwd().readFileAlloc(init.io, args[at + 1], init.arena.allocator(), .limited(1024 * 1024)) catch |e|
        state.fail("cannot read '{s}': {t}", .{ args[at + 1], e });
    // Windows PowerShell 5 starts UTF-8 files with one byte order mark. It is not text.
    return if (std.mem.startsWith(u8, text, "\xEF\xBB\xBF")) text[3..] else text;
}

pub fn reply(init: std.process.Init, args: []const []const u8) void {
    if (args.len < 4) state.fail("reply needs the text. Example: show-me reply plan.html \"Title is shorter now.\"", .{});
    sendReply(init, find(init, args, "reply"), replyText(init, args, 3, "--file"));
    say(init.io, "sent\n");
}

pub fn end(init: std.process.Init, args: []const []const u8) void {
    post(init, find(init, args, "end"), "end", "");
    say(init.io, "ended\n");
}

pub fn wait(init: std.process.Init, args: []const []const u8) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const r = find(init, args, "wait");
    if (args.len > 3) {
        const known = std.mem.eql(u8, args[3], "--reply") or std.mem.eql(u8, args[3], "--reply-file");
        if (args.len < 5 or !known) {
            state.fail("unknown option '{s}'. Use: show-me wait <file.html> --reply \"text\" (or --reply-file <file>)", .{args[3]});
        }
        sendReply(init, r, if (std.mem.eql(u8, args[3], "--reply")) args[4] else replyText(init, args, 3, "--reply-file"));
    }
    const res = client.call(io, arena, r.port, "GET", "/wait/" ++ r.key, "") catch |e|
        state.fail("lost the daemon while waiting: {t}. Run the same wait again. No notes are lost.", .{e});
    if (res.status != 200) state.fail("no review is open for this file. Run: show-me open {s}", .{r.file});
    // The daemon sends one space every two seconds while it waits. Then one first line
    // says what follows: one note count, "replaced" or "closed".
    const body = std.mem.trimStart(u8, res.body, " ");
    const split = std.mem.findScalar(u8, body, '\n') orelse
        state.fail("the daemon stopped while waiting. Run the same wait again. No notes are lost.", .{});
    const head = body[0..split];
    if (std.mem.eql(u8, head, "replaced")) {
        state.fail("another wait took over this review. Stop waiting here: one agent listens at a time.", .{});
    }
    say(io, body[split + 1 ..]);
    if (std.mem.eql(u8, head, "closed")) return;
    // Ack only after the notes are printed. A crash before this line redelivers them.
    _ = client.call(io, arena, r.port, "POST", "/ack/" ++ r.key, head) catch {};
}
