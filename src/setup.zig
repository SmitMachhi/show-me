// `show-me setup`: writes the skill that teaches an agent to use show-me.
// The skill files are built into the program, so one downloaded file is the whole install.
// With no folder it writes <agent folder>/skills/show-me for each agent folder that
// exists in the home folder, the layout these agents read skills from. Without any of
// them it writes ~/.claude/skills/show-me. It changes no settings file of any agent.
// `show-me setup <folder>` writes to that one folder.
const std = @import("std");
const state = @import("state.zig");
const Io = std.Io;

const files = [_][2][]const u8{
    .{ "SKILL.md", @embedFile("skill/SKILL.md") },
    .{ "base.html", @embedFile("skill/base.html") },
};

// The agents and their folders inside the home folder.
const agents = [_][2][]const u8{
    .{ "Claude Code", ".claude" },
    .{ "Codex", ".codex" },
    .{ "OpenCode", ".config/opencode" },
    .{ "GitHub Copilot", ".copilot" },
    .{ "Cursor", ".cursor" },
    .{ "Gemini", ".gemini" },
    .{ "Agent Skills (shared)", ".agents" },
};

fn write(io: Io, dest: []const u8) void {
    var dir = Io.Dir.cwd().createDirPathOpen(io, dest, .{}) catch |e|
        state.fail("cannot create '{s}': {t}", .{ dest, e });
    defer dir.close(io);
    for (files) |f| {
        dir.writeFile(io, .{ .sub_path = f[0], .data = f[1] }) catch |e|
            state.fail("cannot write {s} in '{s}': {t}", .{ f[0], dest, e });
    }
}

pub fn run(init: std.process.Init, args: []const []const u8) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const out = Io.File.stdout();
    if (args.len > 2) {
        write(io, args[2]);
        out.writeStreamingAll(io, std.fmt.allocPrint(arena, "skill written to {s}\n", .{args[2]}) catch return) catch {};
        return;
    }
    const home = state.home(init.environ_map);
    var found: usize = 0;
    for (agents) |a| {
        const folder = std.fs.path.join(arena, &.{ home, a[1] }) catch return;
        Io.Dir.cwd().access(io, folder, .{}) catch continue;
        const dest = std.fs.path.join(arena, &.{ folder, "skills", "show-me" }) catch return;
        write(io, dest);
        found += 1;
        out.writeStreamingAll(io, std.fmt.allocPrint(arena, "{s}: skill written to {s}\n", .{ a[0], dest }) catch return) catch {};
    }
    if (found > 0) return;
    const dest = std.fs.path.join(arena, &.{ home, ".claude", "skills", "show-me" }) catch return;
    write(io, dest);
    out.writeStreamingAll(io, std.fmt.allocPrint(arena, "no agent folder found; skill written to {s}\n", .{dest}) catch return) catch {};
}
