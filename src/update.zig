// `show-me update`: installs the newest release in the folder of this program. It holds
// no download code: it starts the same installer as the one-command install, with
// SHOW_ME_INSTALL_DIR set to this folder, and returns at once. Windows cannot replace
// one program that still runs, so this program exits before the installer writes.
const std = @import("std");
const builtin = @import("builtin");
const state = @import("state.zig");
const Io = std.Io;

const base = "https://raw.githubusercontent.com/SmitMachhi/show-me/master/";

pub fn run(init: std.process.Init) void {
    const io = init.io;
    const arena = init.arena.allocator();
    var path: [Io.Dir.max_path_bytes]u8 = undefined;
    const n = std.process.executablePath(io, &path) catch |e|
        state.fail("cannot find the show-me program path: {t}", .{e});
    var env = init.environ_map.clone(arena) catch return;
    env.put("SHOW_ME_INSTALL_DIR", std.fs.path.dirname(path[0..n]) orelse ".") catch return;
    // The short wait lets this program exit first, so its file is free to replace.
    const argv: []const []const u8 = if (builtin.os.tag == .windows)
        &.{ "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "Start-Sleep -Milliseconds 700; irm " ++ base ++ "install.ps1 | iex" }
    else
        &.{ "sh", "-c", "sleep 0.7; curl -fsSL " ++ base ++ "install.sh | sh" };
    _ = std.process.spawn(io, .{ .argv = argv, .environ_map = &env }) catch |e|
        state.fail("cannot start the installer: {t}. Run the install command from the README.", .{e});
    Io.File.stdout().writeStreamingAll(io, "The installer runs now and prints its result below.\n") catch {};
}
