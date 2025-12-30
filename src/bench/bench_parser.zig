//! Parser benchmarks - measures Jakefile parsing performance

const std = @import("std");
const jake = @import("jake");
const main = @import("main.zig");

/// Generate a Jakefile with N simple recipes
fn generateSimpleJakefile(allocator: std.mem.Allocator, recipe_count: usize) ![]const u8 {
    var list = std.ArrayListUnmanaged(u8){};
    errdefer list.deinit(allocator);

    try list.ensureTotalCapacity(allocator, recipe_count * 50);

    try list.appendSlice(allocator, "# Generated Jakefile for benchmarking\n\n");
    try list.appendSlice(allocator, "version = \"1.0.0\"\n\n");

    for (0..recipe_count) |i| {
        try list.writer(allocator).print("task task_{d}:\n", .{i});
        try list.writer(allocator).print("    echo \"Running task {d}\"\n\n", .{i});
    }

    return list.toOwnedSlice(allocator);
}

fn benchParseSmall(allocator: std.mem.Allocator) void {
    const source = generateSimpleJakefile(allocator, 10) catch return;
    defer allocator.free(source);

    var lex = jake.Lexer.init(source);
    var p = jake.Parser.init(allocator, &lex);
    var jakefile = p.parseJakefile() catch return;
    jakefile.deinit(allocator);
}

fn benchParseMedium(allocator: std.mem.Allocator) void {
    const source = generateSimpleJakefile(allocator, 100) catch return;
    defer allocator.free(source);

    var lex = jake.Lexer.init(source);
    var p = jake.Parser.init(allocator, &lex);
    var jakefile = p.parseJakefile() catch return;
    jakefile.deinit(allocator);
}

fn benchParseLarge(allocator: std.mem.Allocator) void {
    const source = generateSimpleJakefile(allocator, 500) catch return;
    defer allocator.free(source);

    var lex = jake.Lexer.init(source);
    var p = jake.Parser.init(allocator, &lex);
    var jakefile = p.parseJakefile() catch return;
    jakefile.deinit(allocator);
}

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    try stdout.writeAll("Parser Benchmarks:\n");
    try main.runBenchmark("  parser/simple-10-recipes", allocator, benchParseSmall, stdout);
    try main.runBenchmark("  parser/simple-100-recipes", allocator, benchParseMedium, stdout);
    try main.runBenchmark("  parser/simple-500-recipes", allocator, benchParseLarge, stdout);
    try stdout.writeAll("\n");
}
