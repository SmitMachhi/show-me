// Makes one HTML file that opens anywhere without show-me: diagrams are drawn into
// it, and local stylesheets, scripts and images are written into it.
// Files from other sites stay as links, so those still need the network.
// Limits: one simple tag scanner, not a full HTML parser. `url()` inside CSS and
// `srcset` are left as they are.
const std = @import("std");
const graphs = @import("graphs.zig");
const pages = @import("pages.zig");

const max_asset_bytes = 10 * 1024 * 1024;
const graph_style = "<style>.showme-graph{margin:0}.showme-graph svg{max-width:100%;height:auto}</style>\n";

// The value of one attribute inside the text of one tag, or null.
fn attr(tag: []const u8, comptime name: []const u8) ?[]const u8 {
    var from: usize = 0;
    while (std.ascii.findIgnoreCasePos(tag, from, name ++ "=")) |at| : (from = at + 1) {
        if (at > 0 and !std.ascii.isWhitespace(tag[at - 1])) continue;
        const start = at + name.len + 1;
        if (start >= tag.len) return null;
        const q = tag[start];
        if (q != '"' and q != '\'') return null;
        const end = std.mem.findScalarPos(u8, tag, start + 1, q) orelse return null;
        return tag[start + 1 .. end];
    }
    return null;
}

fn isLocal(url: []const u8) bool {
    const remote = [_][]const u8{ "http:", "https:", "//", "data:", "#", "/", "blob:" };
    for (remote) |prefix| {
        if (std.ascii.startsWithIgnoreCase(url, prefix)) return false;
    }
    return url.len > 0;
}

const Job = struct {
    ctx: graphs.Ctx,
    arena: std.mem.Allocator,
    file: []const u8,
    out: std.ArrayList(u8) = .empty,

    // The bytes of one local file beside the page, or null when it is missing or outside the folder.
    fn load(job: *Job, url: []const u8) ?[]const u8 {
        if (!isLocal(url)) return null;
        const path = (pages.confine(job.ctx.io, job.arena, job.file, url) catch return null) orelse return null;
        return std.Io.Dir.cwd().readFileAlloc(job.ctx.io, path, job.arena, .limited(max_asset_bytes)) catch null;
    }

    // Handles the tag html[at..end]. Returns where to continue reading.
    fn tag(job: *Job, html: []const u8, at: usize, end: usize) !usize {
        const text = html[at..end];
        const a = job.arena;
        if (std.ascii.startsWithIgnoreCase(text, "<link")) {
            const rel = attr(text, "rel") orelse "";
            if (std.ascii.findIgnoreCase(rel, "stylesheet") != null) {
                if (job.load(attr(text, "href") orelse "")) |css| {
                    try job.out.print(a, "<style>{s}</style>", .{css});
                    return end;
                }
            }
        } else if (std.ascii.startsWithIgnoreCase(text, "<script")) {
            const close = std.ascii.findIgnoreCasePos(html, end, "</script>") orelse html.len;
            const after = @min(html.len, close + "</script>".len);
            if (job.load(attr(text, "src") orelse "")) |js| {
                // A script that holds "</script" would end its own tag early.
                const safe = try std.mem.replaceOwned(u8, a, js, "</script", "<\\/script");
                try job.out.print(a, "<script>{s}</script>", .{safe});
                return after;
            }
            // Any other script is copied whole, so its text is never read as tags.
            try job.out.appendSlice(a, html[at..after]);
            return after;
        } else if (std.ascii.startsWithIgnoreCase(text, "<img")) {
            const src = attr(text, "src") orelse "";
            if (job.load(src)) |bytes| {
                const size = std.base64.standard.Encoder.calcSize(bytes.len);
                const b64 = std.base64.standard.Encoder.encode(try a.alloc(u8, size), bytes);
                const uri = try std.fmt.allocPrint(a, "data:{s};base64,{s}", .{ pages.mime(src), b64 });
                try job.out.appendSlice(a, try std.mem.replaceOwned(u8, a, text, src, uri));
                return end;
            }
        }
        try job.out.appendSlice(a, text);
        return end;
    }
};

// Returns the standalone page for the HTML file at `file`.
pub fn page(ctx: graphs.Ctx, arena: std.mem.Allocator, file: []const u8, source: []const u8) ![]const u8 {
    const html = (try graphs.expand(ctx, arena, source)).html;
    var job: Job = .{ .ctx = ctx, .arena = arena, .file = file };
    var i: usize = 0;
    while (std.mem.findScalarPos(u8, html, i, '<')) |at| {
        try job.out.appendSlice(arena, html[i..at]);
        const end = (std.mem.findScalarPos(u8, html, at, '>') orelse html.len - 1) + 1;
        i = try job.tag(html, at, end);
    }
    try job.out.appendSlice(arena, html[@min(i, html.len)..]);
    // Diagram sizing normally comes from show-me's page script. Without it, this does the job.
    if (std.mem.find(u8, job.out.items, "class=\"showme-graph\"") != null) {
        try job.out.appendSlice(arena, graph_style);
    }
    return job.out.items;
}

test "attr reads quoted values and skips look-alikes" {
    const t = "<link data-href=\"no\" rel='stylesheet' href=\"a b.css\">";
    try std.testing.expectEqualStrings("a b.css", attr(t, "href").?);
    try std.testing.expectEqualStrings("stylesheet", attr(t, "rel").?);
    try std.testing.expect(attr(t, "src") == null);
    try std.testing.expect(isLocal("img/x.png") and !isLocal("https://x/y.css") and !isLocal("//cdn/x.js"));
    try std.testing.expect(!isLocal("/root.css") and !isLocal("data:image/png;base64,AA") and !isLocal(""));
}
