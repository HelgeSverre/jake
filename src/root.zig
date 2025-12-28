// Jake - A modern command runner with dependency tracking
// The best of Make and Just combined

const std = @import("std");

pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const executor = @import("executor.zig");
pub const cache = @import("cache.zig");

pub const Lexer = lexer.Lexer;
pub const Parser = parser.Parser;
pub const Executor = executor.Executor;
pub const Jakefile = parser.Jakefile;

/// Parse a Jakefile from source
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Jakefile {
    var lex = Lexer.init(source);
    var p = Parser.init(allocator, &lex);
    return p.parseJakefile();
}

/// Load and parse a Jakefile from disk
pub fn load(allocator: std.mem.Allocator, path: []const u8) !Jakefile {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(source);

    return parse(allocator, source);
}

test "basic lexer test" {
    const source =
        \\# Comment
        \\name = "value"
        \\
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);

    // Should get tokens for the above
    var count: usize = 0;
    while (lex.next().tag != .eof) {
        count += 1;
    }
    try std.testing.expect(count > 0);
}
