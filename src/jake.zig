//! Jake library — modern command runner and build system.

const std = @import("std");

pub const lexer = @import("frontend/lexer.zig");
pub const parser = @import("frontend/parser.zig");
pub const executor = @import("runtime/executor.zig");
pub const cache = @import("runtime/cache.zig");
pub const glob = @import("util/glob.zig");
pub const watch = @import("runtime/watch.zig");
pub const parallel = @import("runtime/parallel.zig");
pub const env = @import("runtime/env.zig");
pub const import_mod = @import("frontend/import.zig");
pub const jakefile_index = @import("frontend/jakefile_index.zig");
pub const functions = @import("runtime/functions.zig");
pub const compat = @import("compat.zig");
pub const suggest = @import("cli/suggest.zig");
pub const tracy = @import("util/tracy.zig");
pub const hooks = @import("runtime/hooks.zig");
pub const args = @import("cli/args.zig");
pub const conditions = @import("runtime/conditions.zig");
pub const prompt = @import("output/prompt.zig");
pub const completions = @import("cli/completions.zig");
pub const color = @import("output/color.zig");
pub const context = @import("runtime/context.zig");
pub const jakefile_loader = @import("frontend/jakefile_loader.zig");
pub const formatter = @import("output/formatter.zig");
pub const upgrade = @import("cli/upgrade.zig");
pub const init = @import("cli/init.zig");
pub const progress = @import("output/progress.zig");
pub const external = @import("frontend/external.zig");
pub const event_emitter = @import("output/event_emitter.zig");
pub const webui = @import("webui/server.zig");

pub const Lexer = lexer.Lexer;
pub const Parser = parser.Parser;
pub const Executor = executor.Executor;
pub const ListOptions = executor.ListOptions;
pub const Jakefile = parser.Jakefile;
pub const JakefileIndex = jakefile_index.JakefileIndex;
pub const ImportDirective = parser.ImportDirective;
pub const Watcher = watch.Watcher;
pub const ParallelExecutor = parallel.ParallelExecutor;
pub const Environment = env.Environment;
pub const ImportResolver = import_mod.ImportResolver;
pub const ImportAllocations = import_mod.ImportAllocations;
pub const resolveImports = import_mod.resolveImports;
pub const Color = color.Color;
pub const Context = context.Context;
pub const RuntimeContext = context.RuntimeContext;
pub const LoadedJakefile = jakefile_loader.LoadedJakefile;
pub const loadJakefile = jakefile_loader.loadJakefile;
pub const ExternalRecipes = external.ExternalRecipes;
pub const loadAndMergeExternalRecipes = external.loadAndMergeExternalRecipes;

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

// Reference all sub-modules so their tests are discovered
comptime {
    _ = lexer;
    _ = parser;
    _ = executor;
    _ = cache;
    _ = glob;
    _ = watch;
    _ = parallel;
    _ = env;
    _ = import_mod;
    _ = jakefile_index;
    _ = functions;
    _ = suggest;
    _ = hooks;
    _ = args;
    _ = conditions;
    _ = prompt;
    _ = completions;
    _ = color;
    _ = context;
    _ = jakefile_loader;
    _ = formatter;
    _ = upgrade;
    _ = init;
    _ = progress;
    _ = event_emitter;
    _ = webui;
}

test "basic lexer tokenizes Jakefile syntax" {
    const source =
        \\# Comment
        \\name = "value"
        \\
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);

    // Verify expected token types for this source
    var tokens: [32]lexer.Token = undefined;
    var count: usize = 0;
    while (count < tokens.len) {
        tokens[count] = lex.next();
        if (tokens[count].tag == .eof) break;
        count += 1;
    }

    // Should have: comment, newline, identifier, equals, string, etc.
    try std.testing.expect(count >= 8);
    try std.testing.expectEqual(lexer.Token.Tag.comment, tokens[0].tag);
    try std.testing.expectEqual(lexer.Token.Tag.newline, tokens[1].tag);
    try std.testing.expectEqual(lexer.Token.Tag.ident, tokens[2].tag);
    try std.testing.expectEqual(lexer.Token.Tag.equals, tokens[3].tag);
}
