// Jake - A modern command runner with dependency tracking
// The best of Make and Just combined

const std = @import("std");

pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const executor = @import("executor.zig");
pub const cache = @import("cache.zig");
pub const glob = @import("glob.zig");
pub const watch = @import("watch.zig");
pub const parallel = @import("parallel.zig");
pub const env = @import("env.zig");
pub const import_mod = @import("import.zig");
pub const functions = @import("functions.zig");
pub const compat = @import("compat.zig");

pub const Lexer = lexer.Lexer;
pub const Parser = parser.Parser;
pub const Executor = executor.Executor;
pub const Jakefile = parser.Jakefile;
pub const ImportDirective = parser.ImportDirective;
pub const Watcher = watch.Watcher;
pub const ParallelExecutor = parallel.ParallelExecutor;
pub const Environment = env.Environment;
pub const ImportResolver = import_mod.ImportResolver;
pub const ImportAllocations = import_mod.ImportAllocations;
pub const resolveImports = import_mod.resolveImports;

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
