// Std-only HTTPS GET probe: prints status, body byte count and root-cert count. Exit 0 on 200.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const url = if (args.len > 1) args[1] else "https://example.com/";

    // The client loads the OS root store itself on the first https request (Bundle.rescan).
    var client: std.http.Client = .{ .allocator = init.gpa, .io = io };
    defer client.deinit();

    var discard_buf: [4096]u8 = undefined;
    var body: std.Io.Writer.Discarding = .init(&discard_buf);

    var out_buf: [256]u8 = undefined;
    var out = std.Io.File.stdout().writer(io, &out_buf);

    const res = client.fetch(.{ .location = .{ .url = url }, .response_writer = &body.writer }) catch |err| {
        try out.interface.print("{s} error={t} roots={d}\n", .{ url, err, client.ca_bundle.map.count() });
        try out.interface.flush();
        std.process.exit(1);
    };

    const status: u16 = @intFromEnum(res.status);
    try out.interface.print("{s} status={d} bytes={d} roots={d}\n", .{ url, status, body.fullCount(), client.ca_bundle.map.count() });
    try out.interface.flush();
    if (status != 200) std.process.exit(1);
}
