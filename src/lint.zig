// Checks the visible words of one page against the writing rules its owner turned on.
// Rules come from the `rules` file in the state folder, one name per line. With no
// file, nothing is checked: these are one person's style rules, not everyone's.
// Not checked: words inside code, pre, kbd, samp, script, style, svg, textarea, q,
// blockquote, and words inside double quotes.
const std = @import("std");

pub const Rules = struct {
    articles: bool = false, // no-indefinite-articles
    em_dash: bool = false, // no-em-dash
    contractions: bool = false, // no-contractions
    external: bool = false, // no-external-assets
    max_words: usize = 0, // max-sentence-words N
    unknown: ?[]const u8 = null,
};

pub fn parseRules(text: []const u8) Rules {
    var r: Rules = .{};
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        const max = "max-sentence-words ";
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.eql(u8, line, "no-indefinite-articles")) {
            r.articles = true;
        } else if (std.mem.eql(u8, line, "no-em-dash")) {
            r.em_dash = true;
        } else if (std.mem.eql(u8, line, "no-contractions")) {
            r.contractions = true;
        } else if (std.mem.eql(u8, line, "no-external-assets")) {
            r.external = true;
        } else if (std.mem.startsWith(u8, line, max)) {
            r.max_words = std.fmt.parseInt(usize, line[max.len..], 10) catch 0;
        } else {
            r.unknown = line;
        }
    }
    return r;
}

const skipped = [_][]const u8{ "script", "style", "code", "pre", "kbd", "samp", "textarea", "svg", "q", "blockquote" };
const inline_tags = [_][]const u8{ "a", "b", "i", "em", "strong", "span", "small", "sub", "sup", "mark", "u", "abbr" };
const max_findings = 30;

fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |item| {
        if (std.ascii.eqlIgnoreCase(name, item)) return true;
    }
    return false;
}

const Scan = struct {
    arena: std.mem.Allocator,
    rules: Rules,
    line: usize = 1,
    start_line: usize = 1,
    sentence: std.ArrayList(u8) = .empty,
    out: std.ArrayList(u8) = .empty,
    found: usize = 0,

    fn report(st: *Scan, what: []const u8, text: []const u8) !void {
        st.found += 1;
        if (st.found > max_findings) return;
        var cut = @min(text.len, 70);
        while (cut < text.len and cut > 0 and (text[cut] & 0xC0) == 0x80) cut -= 1;
        try st.out.print(st.arena, "line {d}: {s}: {s}\n", .{ st.start_line, what, text[0..cut] });
    }

    // Consumes one tag that starts at html[i]. Returns the index after it, or after the
    // whole element when its words are not checked.
    fn tag(st: *Scan, html: []const u8, i: usize) !usize {
        const close = std.mem.findScalarPos(u8, html, i, '>') orelse return html.len;
        var end = close + 1;
        const inner = html[i + 1 .. close];
        const is_closing = inner.len > 0 and inner[0] == '/';
        var name_len: usize = 0;
        const body = inner[@intFromBool(is_closing)..];
        while (name_len < body.len and std.ascii.isAlphanumeric(body[name_len])) name_len += 1;
        const name = body[0..name_len];
        if (std.mem.startsWith(u8, inner, "!--")) {
            end = if (std.mem.findPos(u8, html, i, "-->")) |c| c + 3 else html.len;
        } else if (!is_closing and oneOf(name, &skipped)) {
            const closer = try std.fmt.allocPrint(st.arena, "</{s}", .{name});
            const at = std.ascii.findIgnoreCasePos(html, end, closer) orelse html.len;
            end = if (std.mem.findScalarPos(u8, html, at, '>')) |c| c + 1 else html.len;
        }
        if (st.rules.external and (oneOf(name, &.{ "script", "link" }))) {
            if (std.mem.find(u8, inner, "=\"http") != null or std.mem.find(u8, inner, "=\"//") != null) {
                try st.flush();
                st.start_line = st.line;
                try st.report("file from another site", inner);
            }
        }
        if (!oneOf(name, &inline_tags)) try st.flush();
        st.line += std.mem.count(u8, html[i..end], "\n");
        return end;
    }

    fn flush(st: *Scan) !void {
        const text = std.mem.trim(u8, st.sentence.items, " \t\r\n");
        if (text.len > 0) try check(st, text);
        st.sentence.clearRetainingCapacity();
    }
};

fn check(st: *Scan, text: []const u8) !void {
    const words = @import("lint_words.zig");
    const plain = try words.unquote(st.arena, text);
    var it = std.mem.tokenizeAny(u8, plain, " \t\r\n");
    var count: usize = 0;
    var article = false;
    var contraction = false;
    while (it.next()) |raw| {
        const w = std.mem.trim(u8, raw, ".,;:!?()[]");
        if (w.len == 0) continue;
        count += 1;
        article = article or words.isArticle(w, count == 1);
        contraction = contraction or words.isContraction(w);
    }
    // One line per rule and sentence, however many times the sentence breaks the rule.
    if (st.rules.articles and article) try st.report("indefinite article", text);
    if (st.rules.contractions and contraction) try st.report("contraction", text);
    if (st.rules.em_dash and words.hasEmDash(plain)) try st.report("em dash", text);
    if (st.rules.max_words != 0 and count > st.rules.max_words) {
        try st.report(try std.fmt.allocPrint(st.arena, "{d} words, limit {d}", .{ count, st.rules.max_words }), text);
    }
}

// Returns one line per problem, or "" when the page passes.
pub fn run(arena: std.mem.Allocator, html: []const u8, rules: Rules) ![]const u8 {
    var st: Scan = .{ .arena = arena, .rules = rules };
    var i: usize = 0;
    while (i < html.len) {
        const c = html[i];
        if (c == '<') {
            i = try st.tag(html, i);
            continue;
        }
        if (st.sentence.items.len == 0) st.start_line = st.line;
        if (c == '\n') st.line += 1;
        try st.sentence.append(arena, c);
        const at_end = i + 1 == html.len or std.ascii.isWhitespace(html[i + 1]) or html[i + 1] == '<';
        if ((c == '.' or c == '!' or c == '?') and at_end) try st.flush();
        i += 1;
    }
    try st.flush();
    if (st.found > max_findings) try st.out.print(arena, "and {d} more\n", .{st.found - max_findings});
    return st.out.items;
}

test "finds each rule break and skips code and quotes" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const all = parseRules("no-indefinite-articles\nno-em-dash\nno-contractions\nno-external-assets\nmax-sentence-words 6\n");
    const bad = "<link href=\"https://cdn.example/x.css\">\n<p>Click a button.</p>\n<p>It doesn't work \xe2\x80\x94 yet.</p>\n" ++
        "<p>One two three four five six seven.</p>";
    const out = try run(arena, bad, all);
    try std.testing.expectEqual(@as(usize, 5), std.mem.count(u8, out, "\n"));
    try std.testing.expect(std.mem.find(u8, out, "line 2: indefinite article") != null);
    const good = "<p>Press <code>a</code> or \"a\" key. Plan A is ready.</p><pre>a an don't</pre>";
    try std.testing.expectEqualStrings("", try run(arena, good, all));
    try std.testing.expectEqualStrings("", try run(arena, bad, .{}));
    try std.testing.expect(parseRules("no-such-rule\n").unknown != null);
}
