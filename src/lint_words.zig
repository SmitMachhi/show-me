// Word-level tests for the writing rules. English only.
const std = @import("std");

const curly_open = "\xe2\x80\x9c";
const curly_close = "\xe2\x80\x9d";
const curly_apostrophe = "\xe2\x80\x99";
const em_dash = "\xe2\x80\x94";

// Words that end in 's and are always one contraction, never one possessive.
const s_contractions = [_][]const u8{ "it's", "that's", "there's", "here's", "what's", "let's", "he's", "she's", "who's" };
const endings = [_][]const u8{ "n't", "'re", "'ll", "'ve", "'d", "'m" };

// "A" in capitals is an article only when it starts the sentence. Elsewhere it is one
// label, as in "Plan A".
pub fn isArticle(word: []const u8, first_in_sentence: bool) bool {
    if (std.ascii.eqlIgnoreCase(word, "an")) return true;
    return std.mem.eql(u8, word, "a") or (first_in_sentence and std.mem.eql(u8, word, "A"));
}

pub fn isContraction(word: []const u8) bool {
    var buf: [32]u8 = undefined;
    if (word.len > buf.len) return false;
    const n = std.mem.replacementSize(u8, word, curly_apostrophe, "'");
    _ = std.mem.replace(u8, word, curly_apostrophe, "'", &buf);
    const w = std.ascii.lowerString(buf[0..n], buf[0..n]);
    for (endings) |ending| {
        if (std.mem.endsWith(u8, w, ending)) return true;
    }
    for (s_contractions) |c| {
        if (std.mem.eql(u8, w, c)) return true;
    }
    return false;
}

pub fn hasEmDash(text: []const u8) bool {
    return std.mem.find(u8, text, em_dash) != null or std.mem.find(u8, text, "&mdash;") != null or
        std.mem.find(u8, text, "&#8212;") != null;
}

// Removes text inside straight or curly double quotes. Quoted words are not the author's.
pub fn unquote(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var quoted = false;
    var i: usize = 0;
    while (i < text.len) {
        const rest = text[i..];
        if (rest[0] == '"') {
            quoted = !quoted;
            i += 1;
        } else if (std.mem.startsWith(u8, rest, curly_open) or std.mem.startsWith(u8, rest, curly_close)) {
            quoted = std.mem.startsWith(u8, rest, curly_open);
            i += 3;
        } else {
            if (!quoted) try out.append(arena, rest[0]);
            i += 1;
        }
    }
    return out.items;
}

test "word rules" {
    try std.testing.expect(isArticle("a", false) and isArticle("An", false) and isArticle("A", true));
    try std.testing.expect(!isArticle("A", false) and !isArticle("and", false));
    try std.testing.expect(isContraction("don't") and isContraction("It\xe2\x80\x99s") and isContraction("we'll"));
    try std.testing.expect(!isContraction("Zig's") and !isContraction("users'"));
    try std.testing.expect(hasEmDash("x \xe2\x80\x94 y") and !hasEmDash("x - y"));
}
