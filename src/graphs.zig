// Turns DOT blocks in one page into inline SVG with Graphviz. The page author writes
//   <script type="text/vnd.graphviz">digraph { a -> b }</script>
// and never handles the SVG, which is 5 to 10 times larger than the DOT.
// Results are cached by the hash of the DOT text, so one diagram is drawn once.
// Needs the `dot` program on PATH. Without it the page shows how to install it.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Env = std.process.Environ.Map;

pub const Ctx = struct { io: Io, dir: Io.Dir, env: *const Env };
pub const Result = struct { html: []const u8, errors: []const u8 };
const Drawn = union(enum) { svg: []const u8, err: []const u8 };

const open_tag = "<script type=\"text/vnd.graphviz\">";
const close_tag = "</script>";
const max_svg_bytes = 16 * 1024 * 1024;
const install_hint = "Graphviz is not installed. Install it, then retry. " ++
    "Windows: winget install Graphviz.Graphviz. macOS: brew install graphviz. Linux: sudo apt install graphviz.";
// Fonts with metrics built into Graphviz, so labels fit without any font lookup.
const fonts = [_][]const u8{ "-Gfontname=Helvetica", "-Nfontname=Helvetica", "-Efontname=Helvetica" };

// Returns the page with one <figure> after each DOT block, and one line per failed block.
pub fn expand(ctx: Ctx, arena: std.mem.Allocator, html: []const u8) !Result {
    var out: std.ArrayList(u8) = .empty;
    var errors: std.ArrayList(u8) = .empty;
    var rest = html;
    var n: usize = 1;
    while (std.mem.find(u8, rest, open_tag)) |start| : (n += 1) {
        const from = start + open_tag.len;
        const len = std.mem.find(u8, rest[from..], close_tag) orelse break;
        const end = from + len + close_tag.len;
        try out.appendSlice(arena, rest[0..end]);
        switch (try draw(ctx, arena, rest[from .. from + len])) {
            .svg => |svg| try out.print(arena, "<figure class=\"showme-graph\">{s}</figure>", .{svg}),
            .err => |text| {
                // Graphviz prefixes its message with the cache file's path. The author never saw that file.
                const skip = if (std.mem.find(u8, text, ".dot: ")) |i| i + 6 else 0;
                const clean = std.mem.trim(u8, text[skip..], " \r\n");
                try errors.print(arena, "graph {d}: {s}\n", .{ n, clean });
                try out.print(arena, "<pre class=\"showme-graph-error\">graph {d}: {f}</pre>", .{ n, escaped(clean) });
            },
        }
        rest = rest[end..];
    }
    try out.appendSlice(arena, rest);
    return .{ .html = out.items, .errors = errors.items };
}

const Escaped = struct {
    text: []const u8,
    pub fn format(e: Escaped, w: *Io.Writer) Io.Writer.Error!void {
        for (e.text) |c| switch (c) {
            '<' => try w.writeAll("&lt;"),
            '&' => try w.writeAll("&amp;"),
            else => try w.writeByte(c),
        };
    }
};

fn escaped(text: []const u8) Escaped {
    return .{ .text = text };
}

fn draw(ctx: Ctx, arena: std.mem.Allocator, dot_text: []const u8) !Drawn {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(dot_text, &digest, .{});
    const hex = std.fmt.bytesToHex(digest[0..12].*, .lower);
    const cache = try ctx.dir.createDirPathOpen(ctx.io, "graphs", .{});
    defer cache.close(ctx.io);
    if (cache.readFileAlloc(ctx.io, &(hex ++ ".svg").*, arena, .limited(max_svg_bytes))) |svg| {
        return .{ .svg = svg };
    } else |_| {}

    const exe = findDot(ctx, arena) orelse return .{ .err = install_hint };
    try cache.writeFile(ctx.io, .{ .sub_path = &(hex ++ ".dot").*, .data = dot_text });
    const dot_path = try cache.realPathFileAlloc(ctx.io, &(hex ++ ".dot").*, arena);
    var env = try ctx.env.clone(arena);
    if (builtin.os.tag == .windows) {
        if (lite.folder(ctx, arena, std.fs.path.dirname(exe).?)) |path| try env.put("GVBINDIR", path);
    }
    const res = try std.process.run(arena, ctx.io, .{
        .argv = &.{ exe, "-Tsvg", fonts[0], fonts[1], fonts[2], dot_path },
        .environ_map = &env,
    });
    const at = std.mem.find(u8, res.stdout, "<svg");
    if (!res.term.success() or at == null) {
        return .{ .err = if (res.stderr.len > 0) res.stderr else "Graphviz printed no SVG." };
    }
    try cache.writeFile(ctx.io, .{ .sub_path = &(hex ++ ".svg").*, .data = res.stdout[at.?..] });
    return .{ .svg = res.stdout[at.?..] };
}

fn findDot(ctx: Ctx, arena: std.mem.Allocator) ?[]const u8 {
    const windows = builtin.os.tag == .windows;
    var dirs = std.mem.splitScalar(u8, ctx.env.get("PATH") orelse return null, if (windows) ';' else ':');
    while (dirs.next()) |dir| {
        if (dir.len == 0) continue;
        const path = std.fs.path.join(arena, &.{ dir, if (windows) "dot.exe" else "dot" }) catch return null;
        Io.Dir.cwd().access(ctx.io, path, .{}) catch continue;
        return path;
    }
    return null;
}

// Windows only. Graphviz loads its font plugin on every run there, and that costs about
// one second. One folder holding only the core and layout plugins brings one run down to
// about 50 ms. The folder is rebuilt when the Graphviz config file changes.
const lite = struct {
    const plugins = [_][]const u8{ "gvplugin_core.dll", "gvplugin_dot_layout.dll" };

    fn folder(ctx: Ctx, arena: std.mem.Allocator, dot_dir: []const u8) ?[]const u8 {
        return build(ctx, arena, dot_dir) catch null;
    }

    fn build(ctx: Ctx, arena: std.mem.Allocator, dot_dir: []const u8) ![]const u8 {
        const io = ctx.io;
        var src = try Io.Dir.cwd().openDir(io, dot_dir, .{ .iterate = true });
        defer src.close(io);
        var it = src.iterate();
        const name = while (try it.next(io)) |entry| {
            if (std.mem.startsWith(u8, entry.name, "config")) break try arena.dupe(u8, entry.name);
        } else return error.NoGraphvizConfig;
        const stat = try src.statFile(io, name, .{});
        const stamp = try std.fmt.allocPrint(arena, "{s} {d} {d}", .{ dot_dir, stat.size, stat.mtime.nanoseconds });

        const dst = try ctx.dir.createDirPathOpen(io, "graphviz", .{});
        defer dst.close(io);
        const path = try ctx.dir.realPathFileAlloc(io, "graphviz", arena);
        var buf: [1024]u8 = undefined;
        const have = dst.readFile(io, "stamp", &buf) catch "";
        if (std.mem.eql(u8, have, stamp)) return path;

        const config = try src.readFileAlloc(io, name, arena, .limited(1024 * 1024));
        try dst.writeFile(io, .{ .sub_path = name, .data = try keepBlocks(arena, config) });
        for (plugins) |plugin| try src.copyFile(plugin, dst, plugin, io, .{});
        try dst.writeFile(io, .{ .sub_path = "stamp", .data = stamp });
        return path;
    }

    // The config lists one block per plugin. A block starts at a line that names its file.
    fn keepBlocks(arena: std.mem.Allocator, config: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        var keep = false;
        var lines = std.mem.splitScalar(u8, config, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "gvplugin_")) {
                keep = std.mem.startsWith(u8, line, plugins[0]) or std.mem.startsWith(u8, line, plugins[1]);
            }
            if (keep) try out.print(arena, "{s}\n", .{line});
        }
        return out.items;
    }
};

test "keepBlocks keeps only the core and layout plugins" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const config = "gvplugin_core.dll core {\n\ta\n}\ngvplugin_pango.dll cairo {\n\tb\n}\ngvplugin_dot_layout.dll dot_layout {\n\tc\n}\n";
    const kept = try lite.keepBlocks(arena_state.allocator(), config);
    try std.testing.expect(std.mem.find(u8, kept, "pango") == null);
    try std.testing.expect(std.mem.find(u8, kept, "\ta\n") != null and std.mem.find(u8, kept, "\tc\n") != null);
}
