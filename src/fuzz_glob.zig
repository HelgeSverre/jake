const std = @import("std");
const jake = @import("jake");

// Fuzzing harness for glob pattern matching.
//
// Designed to be used with external fuzzers (AFL++, honggfuzz, etc.) by compiling
// with Zig's `-ffuzz` instrumentation.
//
// The harness tests glob pattern matching against various paths and checks pattern validity.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const max_len = 1024 * 1024;

    const input = blk: {
        if (args.len >= 2) {
            break :blk try std.fs.cwd().readFileAlloc(allocator, args[1], max_len);
        }
        break :blk try std.fs.File.stdin().readToEndAlloc(allocator, max_len);
    };
    defer allocator.free(input);

    // Use input as a glob pattern and test matching
    const test_paths = [_][]const u8{
        "src/main.zig",
        "src/lexer.zig",
        "src/parser.zig",
        "src/bench/main.zig",
        "tests/e2e/Jakefile",
        "build.zig",
        "Jakefile",
        "",
        "a",
        "a/b/c/d/e/f/g/h/i/j",
    };

    // Test pattern matching
    for (test_paths) |path| {
        _ = jake.glob.match(input, path);
    }

    // Test if it's a valid glob pattern
    _ = jake.glob.isGlobPattern(input);

    // Try to expand the pattern (may fail gracefully)
    if (jake.glob.expandGlob(allocator, input)) |results| {
        for (results) |result| {
            allocator.free(result);
        }
        allocator.free(results);
    } else |_| {
        // Pattern expansion failed - that's fine for fuzzing
    }
}
