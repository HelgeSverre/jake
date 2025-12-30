//! Lexer benchmarks - measures tokenization performance

const std = @import("std");
const jake = @import("jake");
const main = @import("main.zig");

fn generateTokenDenseSource(allocator: std.mem.Allocator, line_count: usize) ![]const u8 {
    var list = std.ArrayListUnmanaged(u8){};
    errdefer list.deinit(allocator);

    try list.ensureTotalCapacity(allocator, line_count * 100);
    const writer = list.writer(allocator);

    for (0..line_count) |i| {
        try writer.print("var_{d} = \"value_{d}\"\n", .{ i, i });
        try writer.print("task t{d}: [dep1, dep2]\n", .{i});
        try writer.writeAll("    @if env(VAR)\n");
        try writer.print("        echo \"line {d}\" # comment\n", .{i});
        try writer.writeAll("    @end\n");
    }

    return list.toOwnedSlice(allocator);
}

fn benchLexSmall(allocator: std.mem.Allocator) void {
    const source = generateTokenDenseSource(allocator, 10) catch return;
    defer allocator.free(source);

    var lex = jake.Lexer.init(source);
    while (lex.next().tag != .eof) {}
}

fn benchLexMedium(allocator: std.mem.Allocator) void {
    const source = generateTokenDenseSource(allocator, 100) catch return;
    defer allocator.free(source);

    var lex = jake.Lexer.init(source);
    while (lex.next().tag != .eof) {}
}

fn benchLexLarge(allocator: std.mem.Allocator) void {
    const source = generateTokenDenseSource(allocator, 500) catch return;
    defer allocator.free(source);

    var lex = jake.Lexer.init(source);
    while (lex.next().tag != .eof) {}
}

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    try stdout.writeAll("Lexer Benchmarks:\n");
    try main.runBenchmark("  lexer/tokenize-small", allocator, benchLexSmall, stdout);
    try main.runBenchmark("  lexer/tokenize-medium", allocator, benchLexMedium, stdout);
    try main.runBenchmark("  lexer/tokenize-large", allocator, benchLexLarge, stdout);
    try stdout.writeAll("\n");
}
