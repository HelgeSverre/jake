const std = @import("std");
const jake = @import("jake");
const compat = jake.compat;

// Fuzzing harness for lexer/tokenization.
//
// Designed to be used with external fuzzers (AFL++, honggfuzz, etc.) by compiling
// with Zig's `-ffuzz` instrumentation.
//
// The harness only tokenizes the input without parsing or executing.
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
        break :blk try compat.getStdIn().readToEndAlloc(allocator, max_len);
    };
    defer allocator.free(input);

    // Only tokenize - don't parse
    var lex = jake.Lexer.init(input);
    while (lex.next().tag != .eof) {
        // Consume all tokens
    }
}
