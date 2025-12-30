//! Parallel executor benchmarks - measures graph building performance

const std = @import("std");
const jake = @import("jake");
const main = @import("main.zig");

fn generateWideDeps(allocator: std.mem.Allocator, width: usize) ![]const u8 {
    var list = std.ArrayListUnmanaged(u8){};
    errdefer list.deinit(allocator);

    try list.ensureTotalCapacity(allocator, width * 40);
    const writer = list.writer(allocator);

    for (0..width) |i| {
        try writer.print("task t{d}:\n    echo \"{d}\"\n\n", .{ i, i });
    }

    try writer.writeAll("task all: [");
    for (0..width) |i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.print("t{d}", .{i});
    }
    try writer.writeAll("]\n    echo \"all done\"\n");

    return list.toOwnedSlice(allocator);
}

fn benchBuildGraphWide(allocator: std.mem.Allocator) void {
    const source = generateWideDeps(allocator, 30) catch return;
    defer allocator.free(source);

    var lex = jake.Lexer.init(source);
    var p = jake.Parser.init(allocator, &lex);
    var jakefile = p.parseJakefile() catch return;
    defer jakefile.deinit(allocator);

    var parallel = jake.ParallelExecutor.init(allocator, &jakefile, 4);
    defer parallel.deinit();

    parallel.buildGraph("all") catch {};
}

fn benchGetStats(allocator: std.mem.Allocator) void {
    const source = generateWideDeps(allocator, 10) catch return;
    defer allocator.free(source);

    var lex = jake.Lexer.init(source);
    var p = jake.Parser.init(allocator, &lex);
    var jakefile = p.parseJakefile() catch return;
    defer jakefile.deinit(allocator);

    var parallel = jake.ParallelExecutor.init(allocator, &jakefile, 4);
    defer parallel.deinit();

    parallel.buildGraph("all") catch {};
    _ = parallel.getParallelismStats();
}

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    try stdout.writeAll("Parallel Benchmarks:\n");
    try main.runBenchmark("  parallel/build-graph-wide", allocator, benchBuildGraphWide, stdout);
    try main.runBenchmark("  parallel/get-stats", allocator, benchGetStats, stdout);
    try stdout.writeAll("\n");
}
