// `show-me setup`: writes the skill that teaches an agent to use show-me.
// The skill files are built into the program, so one downloaded file is the whole install.
// Default folder: ~/.claude/skills/show-me. Pass another folder for another agent.
const std = @import("std");
const state = @import("state.zig");
const Io = std.Io;

const files = [_][2][]const u8{
    .{ "SKILL.md", @embedFile("skill/SKILL.md") },
    .{ "base.html", @embedFile("skill/base.html") },
};

pub fn run(init: std.process.Init, args: []const []const u8) void {
    const io = init.io;
    const arena = init.arena.allocator();
    const dest = if (args.len > 2) args[2] else std.fs.path.join(
        arena,
        &.{ state.home(init.environ_map), ".claude", "skills", "show-me" },
    ) catch return;
    var dir = Io.Dir.cwd().createDirPathOpen(io, dest, .{}) catch |e|
        state.fail("cannot create '{s}': {t}", .{ dest, e });
    defer dir.close(io);
    for (files) |f| {
        dir.writeFile(io, .{ .sub_path = f[0], .data = f[1] }) catch |e|
            state.fail("cannot write {s} in '{s}': {t}", .{ f[0], dest, e });
    }
    const text = std.fmt.allocPrint(arena, "skill written to {s}\n", .{dest}) catch return;
    Io.File.stdout().writeStreamingAll(io, text) catch {};
}
