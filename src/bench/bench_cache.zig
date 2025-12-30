//! Cache benchmarks - measures file hash caching performance

const std = @import("std");
const jake = @import("jake");
const main = @import("main.zig");

fn benchCacheInit(allocator: std.mem.Allocator) void {
    var cache = jake.cache.Cache.init(allocator);
    defer cache.deinit();
}

fn benchCacheIsStale(allocator: std.mem.Allocator) void {
    var cache = jake.cache.Cache.init(allocator);
    defer cache.deinit();

    const test_files = [_][]const u8{
        "src/main.zig",
        "src/lexer.zig",
        "build.zig",
    };

    for (test_files) |file| {
        _ = cache.isStale(file) catch continue;
    }
}

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    try stdout.writeAll("Cache Benchmarks:\n");
    try main.runBenchmark("  cache/init", allocator, benchCacheInit, stdout);
    try main.runBenchmark("  cache/is-stale", allocator, benchCacheIsStale, stdout);
    try stdout.writeAll("\n");
}
