const std = @import("std");
const jake = @import("jake");
const compat = jake.compat;

// Fuzzing harness for Jakefile parsing.
//
// Designed to be used with external fuzzers (AFL++, honggfuzz, etc.) by compiling
// with Zig's `-ffuzz` instrumentation.
//
// The harness intentionally avoids executing any commands; it only tokenizes and
// parses the input into an AST and then frees it again.
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

    var lex = jake.Lexer.init(input);
    var p = jake.Parser.init(allocator, &lex);

    var jakefile = p.parseJakefile() catch return;
    defer jakefile.deinit(allocator);
}
