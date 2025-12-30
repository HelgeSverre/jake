//! Glob benchmarks - measures pattern matching performance

const std = @import("std");
const jake = @import("jake");
const main = @import("main.zig");

const test_paths = [_][]const u8{
    "src/main.zig",
    "src/lexer.zig",
    "src/parser.zig",
    "src/bench/main.zig",
    "tests/e2e_test.sh",
    "build.zig",
    "Jakefile",
};

fn benchMatchSimple(_: std.mem.Allocator) void {
    const pattern = "*.zig";
    for (test_paths) |path| {
        _ = jake.glob.match(pattern, path);
    }
}

fn benchMatchRecursive(_: std.mem.Allocator) void {
    const pattern = "**/*.zig";
    for (test_paths) |path| {
        _ = jake.glob.match(pattern, path);
    }
}

fn benchIsGlobPattern(_: std.mem.Allocator) void {
    const patterns = [_][]const u8{
        "*.zig",
        "src/**/*.zig",
        "plain/path/file.txt",
        "src/[a-z]*.zig",
        "file?.txt",
        "no_glob_here",
    };
    for (patterns) |pattern| {
        _ = jake.glob.isGlobPattern(pattern);
    }
}

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    try stdout.writeAll("Glob Benchmarks:\n");
    try main.runBenchmark("  glob/match-simple", allocator, benchMatchSimple, stdout);
    try main.runBenchmark("  glob/match-recursive", allocator, benchMatchRecursive, stdout);
    try main.runBenchmark("  glob/is-pattern", allocator, benchIsGlobPattern, stdout);
    try stdout.writeAll("\n");
}
