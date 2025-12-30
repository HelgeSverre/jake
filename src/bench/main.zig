//! Jake internal benchmark suite
//!
//! Run with: zig build bench
//! Build only: zig build bench-build
//!
//! Uses std.time.Timer for benchmarking (compatible with all Zig versions)

const std = @import("std");
const jake = @import("jake");
const compat = jake.compat;

const bench_parser = @import("bench_parser.zig");
const bench_lexer = @import("bench_lexer.zig");
const bench_executor = @import("bench_executor.zig");
const bench_glob = @import("bench_glob.zig");
const bench_cache = @import("bench_cache.zig");
const bench_parallel = @import("bench_parallel.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = compat.getStdOut();

    try stdout.writeAll("\n=== Jake Internal Benchmarks ===\n\n");

    // Run all benchmarks
    try bench_parser.run(allocator, stdout);
    try bench_lexer.run(allocator, stdout);
    try bench_executor.run(allocator, stdout);
    try bench_glob.run(allocator, stdout);
    try bench_cache.run(allocator, stdout);
    try bench_parallel.run(allocator, stdout);

    try stdout.writeAll("\n=== Benchmarks Complete ===\n");
}

/// Simple benchmark runner using std.time.Timer
pub fn runBenchmark(
    name: []const u8,
    allocator: std.mem.Allocator,
    comptime benchFn: fn (std.mem.Allocator) void,
    stdout: std.fs.File,
) !void {
    const warmup_iterations: usize = 3;
    const iterations: usize = 100;

    // Warmup
    for (0..warmup_iterations) |_| {
        benchFn(allocator);
    }

    // Timed run
    var timer = try std.time.Timer.start();
    for (0..iterations) |_| {
        benchFn(allocator);
    }
    const elapsed_ns = timer.read();

    const avg_ns = elapsed_ns / iterations;
    const avg_us = @as(f64, @floatFromInt(avg_ns)) / 1000.0;
    const avg_ms = avg_us / 1000.0;

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{s:<40} {d:>10.2} us ({d:.3} ms)\n", .{ name, avg_us, avg_ms }) catch return;
    try stdout.writeAll(msg);
}
