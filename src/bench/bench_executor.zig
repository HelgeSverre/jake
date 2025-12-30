//! Executor benchmarks - measures recipe resolution performance (dry-run)

const std = @import("std");
const jake = @import("jake");
const main = @import("main.zig");

fn setupExecutor(allocator: std.mem.Allocator, source: []const u8) ?struct { jake.Executor, jake.Jakefile } {
    var lex = jake.Lexer.init(source);
    var p = jake.Parser.init(allocator, &lex);
    var jakefile = p.parseJakefile() catch return null;

    var exec = jake.Executor.init(allocator, &jakefile);
    exec.dry_run = true;

    return .{ exec, jakefile };
}

const simple_jakefile =
    \\task build:
    \\    echo "building"
    \\
    \\task test: [build]
    \\    echo "testing"
    \\
    \\task deploy: [test]
    \\    echo "deploying"
;

const variable_jakefile =
    \\name = "myapp"
    \\version = "1.0.0"
    \\
    \\task build:
    \\    echo "Building {{name}} v{{version}}"
;

fn benchExecuteSimple(allocator: std.mem.Allocator) void {
    const setup = setupExecutor(allocator, simple_jakefile) orelse return;
    var exec = setup[0];
    var jakefile = setup[1];
    defer jakefile.deinit(allocator);
    defer exec.deinit();

    exec.execute("deploy") catch {};
}

fn benchExecuteVariables(allocator: std.mem.Allocator) void {
    const setup = setupExecutor(allocator, variable_jakefile) orelse return;
    var exec = setup[0];
    var jakefile = setup[1];
    defer jakefile.deinit(allocator);
    defer exec.deinit();

    exec.execute("build") catch {};
}

pub fn run(allocator: std.mem.Allocator, stdout: std.fs.File) !void {
    try stdout.writeAll("Executor Benchmarks:\n");
    try main.runBenchmark("  executor/simple-deps", allocator, benchExecuteSimple, stdout);
    try main.runBenchmark("  executor/variable-expansion", allocator, benchExecuteVariables, stdout);
    try stdout.writeAll("\n");
}
