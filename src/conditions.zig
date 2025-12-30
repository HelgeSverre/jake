// Jake Conditions - Evaluates conditional expressions for @if/@elif directives

const std = @import("std");
const builtin = @import("builtin");

pub const ConditionError = error{
    InvalidSyntax,
    UnknownFunction,
    MissingArgument,
    OutOfMemory,
};

/// Runtime context passed from the Executor for runtime state conditions
pub const RuntimeContext = struct {
    watch_mode: bool = false,
    dry_run: bool = false,
    verbose: bool = false,
};

/// Evaluates a condition expression like "env(VAR)", "exists(path)", "eq(a, b)"
pub fn evaluate(
    condition: []const u8,
    variables: *const std.StringHashMap([]const u8),
    context: RuntimeContext,
) ConditionError!bool {
    const trimmed = std.mem.trim(u8, condition, " \t");

    // Handle bare boolean literals
    if (std.mem.eql(u8, trimmed, "true")) {
        return true;
    } else if (std.mem.eql(u8, trimmed, "false")) {
        return false;
    }

    // Parse function call: func(args)
    if (std.mem.indexOf(u8, trimmed, "(")) |paren_start| {
        const func_name = trimmed[0..paren_start];
        const paren_end = std.mem.lastIndexOf(u8, trimmed, ")") orelse return ConditionError.InvalidSyntax;

        const args_str = trimmed[paren_start + 1 .. paren_end];
        const has_args = paren_start + 1 < paren_end;

        // Runtime state conditions (no arguments)
        if (std.mem.eql(u8, func_name, "is_watching")) {
            return context.watch_mode;
        } else if (std.mem.eql(u8, func_name, "is_dry_run")) {
            return context.dry_run;
        } else if (std.mem.eql(u8, func_name, "is_verbose")) {
            return context.verbose;
        }
        // OS/platform conditions (no arguments)
        else if (std.mem.eql(u8, func_name, "is_macos")) {
            return builtin.os.tag == .macos;
        } else if (std.mem.eql(u8, func_name, "is_linux")) {
            return builtin.os.tag == .linux;
        } else if (std.mem.eql(u8, func_name, "is_windows")) {
            return builtin.os.tag == .windows;
        } else if (std.mem.eql(u8, func_name, "is_unix")) {
            return switch (builtin.os.tag) {
                .linux, .macos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
                else => false,
            };
        }

        // Conditions that require arguments
        if (!has_args) {
            return ConditionError.MissingArgument;
        }

        if (std.mem.eql(u8, func_name, "env")) {
            return evaluateEnv(args_str);
        } else if (std.mem.eql(u8, func_name, "exists")) {
            return evaluateExists(args_str, variables);
        } else if (std.mem.eql(u8, func_name, "eq")) {
            return evaluateEq(args_str, variables, true);
        } else if (std.mem.eql(u8, func_name, "neq")) {
            return evaluateEq(args_str, variables, false);
        } else if (std.mem.eql(u8, func_name, "is_platform")) {
            return evaluatePlatform(args_str);
        } else if (std.mem.eql(u8, func_name, "command")) {
            return evaluateCommand(args_str);
        } else {
            return ConditionError.UnknownFunction;
        }
    }

    // Unknown format
    return ConditionError.InvalidSyntax;
}

/// env(VAR) - returns true if environment variable is set and non-empty
fn evaluateEnv(args: []const u8) bool {
    const var_name = stripQuotes(std.mem.trim(u8, args, " \t"));

    if (getSystemEnv(var_name)) |value| {
        return value.len > 0;
    }
    return false;
}

/// Cross-platform system environment variable lookup
fn getSystemEnv(key: []const u8) ?[]const u8 {
    if (comptime builtin.os.tag == .windows) {
        // Windows: environment strings are in WTF-16, can't use posix.getenv
        // Return null on Windows (we rely on locally set vars via .env files)
        return @as(?[]const u8, null);
    }
    return std.posix.getenv(key);
}

/// exists(path) - returns true if file or directory exists
fn evaluateExists(args: []const u8, variables: *const std.StringHashMap([]const u8)) bool {
    const path = expandVariablesSimple(stripQuotes(std.mem.trim(u8, args, " \t")), variables);

    std.fs.cwd().access(path, .{}) catch {
        return false;
    };
    return true;
}

/// is_platform(name) - returns true if current OS matches the given platform name
fn evaluatePlatform(args: []const u8) bool {
    const platform_name = stripQuotes(std.mem.trim(u8, args, " \t"));
    const current_os = @tagName(builtin.os.tag);
    return std.mem.eql(u8, current_os, platform_name);
}

/// command(name) - returns true if command exists in PATH or as absolute path
fn evaluateCommand(args: []const u8) bool {
    const cmd_name = stripQuotes(std.mem.trim(u8, args, " \t"));
    if (cmd_name.len == 0) return false;

    // Handle absolute paths
    if (cmd_name[0] == '/') {
        return if (std.fs.accessAbsolute(cmd_name, .{})) true else |_| false;
    }

    // Search in PATH
    const path_env = std.process.getEnvVarOwned(std.heap.page_allocator, "PATH") catch return false;
    defer std.heap.page_allocator.free(path_env);

    var path_iter = std.mem.splitScalar(u8, path_env, ':');
    while (path_iter.next()) |dir| {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir, cmd_name }) catch continue;
        if (std.fs.accessAbsolute(full_path, .{})) |_| {
            return true;
        } else |_| {
            continue;
        }
    }
    return false;
}

/// eq(a, b) / neq(a, b) - string equality/inequality comparison
fn evaluateEq(args: []const u8, variables: *const std.StringHashMap([]const u8), equal: bool) ConditionError!bool {
    // Parse two comma-separated arguments
    var it = std.mem.splitSequence(u8, args, ",");
    const arg1_raw = it.next() orelse return ConditionError.MissingArgument;
    const arg2_raw = it.next() orelse return ConditionError.MissingArgument;

    const arg1 = resolveValue(std.mem.trim(u8, arg1_raw, " \t"), variables);
    const arg2 = resolveValue(std.mem.trim(u8, arg2_raw, " \t"), variables);

    const are_equal = std.mem.eql(u8, arg1, arg2);
    return if (equal) are_equal else !are_equal;
}

/// Resolve a value - handles environment variables, jake variables, and literals
fn resolveValue(value: []const u8, variables: *const std.StringHashMap([]const u8)) []const u8 {
    const stripped = stripQuotes(value);

    // Check if it's an environment variable reference: $VAR or ${VAR}
    if (stripped.len > 0 and stripped[0] == '$') {
        var var_name: []const u8 = undefined;
        if (stripped.len > 2 and stripped[1] == '{') {
            // ${VAR} format
            if (std.mem.indexOf(u8, stripped, "}")) |end| {
                var_name = stripped[2..end];
            } else {
                return stripped;
            }
        } else {
            // $VAR format
            var_name = stripped[1..];
        }

        if (getSystemEnv(var_name)) |env_val| {
            return env_val;
        }
        return "";
    }

    // Check if it's a jake variable: {{var}}
    if (stripped.len > 4 and std.mem.startsWith(u8, stripped, "{{") and std.mem.endsWith(u8, stripped, "}}")) {
        const var_name = stripped[2 .. stripped.len - 2];
        if (variables.get(var_name)) |val| {
            return val;
        }
        return "";
    }

    // Check jake variable as plain identifier
    if (variables.get(stripped)) |val| {
        return val;
    }

    return stripped;
}

/// Simple variable expansion for paths - handles {{var}} pattern
fn expandVariablesSimple(path: []const u8, variables: *const std.StringHashMap([]const u8)) []const u8 {
    // For now, just handle the basic case of a plain variable reference
    if (path.len > 4 and std.mem.startsWith(u8, path, "{{") and std.mem.endsWith(u8, path, "}}")) {
        const var_name = path[2 .. path.len - 2];
        if (variables.get(var_name)) |val| {
            return val;
        }
    }
    return path;
}

/// Strip quotes from a string
fn stripQuotes(s: []const u8) []const u8 {
    if (s.len >= 2) {
        if ((s[0] == '"' and s[s.len - 1] == '"') or (s[0] == '\'' and s[s.len - 1] == '\'')) {
            return s[1 .. s.len - 1];
        }
    }
    return s;
}

// Tests

// Default context for tests (no runtime flags set)
const test_context = RuntimeContext{};

// Regression tests for bare boolean literals (fixed in issue with @if true/@if false)
test "bare true literal returns true" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("true", &variables, test_context);
    try std.testing.expect(result == true);
}

test "bare false literal returns false" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("false", &variables, test_context);
    try std.testing.expect(result == false);
}

test "bare true with whitespace" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("  true  ", &variables, test_context);
    try std.testing.expect(result == true);
}

test "bare false with whitespace" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("  false  ", &variables, test_context);
    try std.testing.expect(result == false);
}

test "env condition - set variable" {
    // Set a test environment variable
    const result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", "echo test" },
    });
    std.testing.allocator.free(result.stdout);
    std.testing.allocator.free(result.stderr);

    // PATH should always be set
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const has_path = try evaluate("env(PATH)", &variables, test_context);
    try std.testing.expect(has_path);
}

test "env condition - unset variable" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const has_nonexistent = try evaluate("env(JAKE_TEST_NONEXISTENT_VAR_12345)", &variables, test_context);
    try std.testing.expect(!has_nonexistent);
}

test "exists condition - existing path" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // Current directory should exist
    const exists_cwd = try evaluate("exists(.)", &variables, test_context);
    try std.testing.expect(exists_cwd);
}

test "exists condition - non-existing path" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const exists_none = try evaluate("exists(/nonexistent/path/12345)", &variables, test_context);
    try std.testing.expect(!exists_none);
}

test "eq condition - equal strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const are_equal = try evaluate("eq(hello, hello)", &variables, test_context);
    try std.testing.expect(are_equal);
}

test "eq condition - unequal strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const are_equal = try evaluate("eq(hello, world)", &variables, test_context);
    try std.testing.expect(!are_equal);
}

test "neq condition - unequal strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const are_not_equal = try evaluate("neq(hello, world)", &variables, test_context);
    try std.testing.expect(are_not_equal);
}

test "neq condition - equal strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const are_not_equal = try evaluate("neq(hello, hello)", &variables, test_context);
    try std.testing.expect(!are_not_equal);
}

test "eq with jake variable" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();
    try variables.put("mode", "debug");

    const is_debug = try evaluate("eq(mode, debug)", &variables, test_context);
    try std.testing.expect(is_debug);
}

test "eq with quoted strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const are_equal = try evaluate("eq(\"hello world\", \"hello world\")", &variables, test_context);
    try std.testing.expect(are_equal);
}

test "invalid syntax" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = evaluate("invalid", &variables, test_context);
    try std.testing.expectError(ConditionError.InvalidSyntax, result);
}

test "unknown function" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = evaluate("unknown(arg)", &variables, test_context);
    try std.testing.expectError(ConditionError.UnknownFunction, result);
}

test "exists with variable" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();
    try variables.put("cwd", ".");

    const exists_var = try evaluate("exists({{cwd}})", &variables, test_context);
    try std.testing.expect(exists_var);
}

test "eq with env variable" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // HOME should be set on most systems
    if (getSystemEnv("HOME")) |home_val| {
        // Create a variable with the same value
        try variables.put("home", home_val);

        const matches = try evaluate("eq($HOME, home)", &variables, test_context);
        try std.testing.expect(matches);
    }
}

test "neq with different env variables" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // PATH and HOME should be different
    const result = try evaluate("neq($PATH, $HOME)", &variables, test_context);
    try std.testing.expect(result);
}

test "eq with empty vs non-empty" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();
    try variables.put("empty", "");
    try variables.put("non_empty", "value");

    const not_equal = try evaluate("neq(empty, non_empty)", &variables, test_context);
    try std.testing.expect(not_equal);
}

test "eq with braced env variable" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // HOME should be set on most systems
    if (getSystemEnv("HOME")) |_| {
        const matches = try evaluate("eq(${HOME}, $HOME)", &variables, test_context);
        try std.testing.expect(matches);
    }
}

test "is_watching condition" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const ctx_watching = RuntimeContext{ .watch_mode = true };
    const ctx_not = RuntimeContext{ .watch_mode = false };

    try std.testing.expect(try evaluate("is_watching()", &variables, ctx_watching));
    try std.testing.expect(!try evaluate("is_watching()", &variables, ctx_not));
}

test "is_dry_run condition" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const ctx_dry = RuntimeContext{ .dry_run = true };
    const ctx_not = RuntimeContext{ .dry_run = false };

    try std.testing.expect(try evaluate("is_dry_run()", &variables, ctx_dry));
    try std.testing.expect(!try evaluate("is_dry_run()", &variables, ctx_not));
}

test "is_verbose condition" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const ctx_verbose = RuntimeContext{ .verbose = true };
    const ctx_not = RuntimeContext{ .verbose = false };

    try std.testing.expect(try evaluate("is_verbose()", &variables, ctx_verbose));
    try std.testing.expect(!try evaluate("is_verbose()", &variables, ctx_not));
}

// ============================================================================
// Edge case tests
// ============================================================================

test "eq with both empty strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    try std.testing.expect(try evaluate("eq(\"\", \"\")", &variables, .{}));
}

test "neq with both empty strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    try std.testing.expect(!try evaluate("neq(\"\", \"\")", &variables, .{}));
}

test "eq with whitespace in arguments" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // Whitespace around arguments should be trimmed
    try std.testing.expect(try evaluate("eq(  hello  ,  hello  )", &variables, .{}));
}

test "exists with current directory" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    try std.testing.expect(try evaluate("exists(.)", &variables, .{}));
}

test "exists with parent directory" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    try std.testing.expect(try evaluate("exists(..)", &variables, .{}));
}

test "env with undefined variable returns false" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // env() should return false for undefined variables
    try std.testing.expect(!try evaluate("env(JAKE_TEST_UNDEFINED_VAR_12345)", &variables, .{}));
}

test "eq comparing variable to literal" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();
    try variables.put("mode", "debug");

    try std.testing.expect(try evaluate("eq(mode, debug)", &variables, .{}));
    try std.testing.expect(!try evaluate("eq(mode, release)", &variables, .{}));
}

test "neq comparing variable to literal" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();
    try variables.put("mode", "debug");

    try std.testing.expect(try evaluate("neq(mode, release)", &variables, .{}));
    try std.testing.expect(!try evaluate("neq(mode, debug)", &variables, .{}));
}

// --- Platform Detection Tests ---

test "is_macos condition" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("is_macos()", &variables, .{});
    // Result depends on compile-time OS
    if (builtin.os.tag == .macos) {
        try std.testing.expect(result);
    } else {
        try std.testing.expect(!result);
    }
}

test "is_linux condition" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("is_linux()", &variables, .{});
    if (builtin.os.tag == .linux) {
        try std.testing.expect(result);
    } else {
        try std.testing.expect(!result);
    }
}

test "is_windows condition" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("is_windows()", &variables, .{});
    if (builtin.os.tag == .windows) {
        try std.testing.expect(result);
    } else {
        try std.testing.expect(!result);
    }
}

test "is_unix condition" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("is_unix()", &variables, .{});
    const is_unix_os = switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
        else => false,
    };
    try std.testing.expectEqual(is_unix_os, result);
}

test "is_platform with current OS" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const current_os = @tagName(builtin.os.tag);
    var buf: [64]u8 = undefined;
    const condition = std.fmt.bufPrint(&buf, "is_platform({s})", .{current_os}) catch return;

    const result = try evaluate(condition, &variables, .{});
    try std.testing.expect(result);
}

test "is_platform with non-matching OS" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // Use an OS that's definitely not the current one
    const fake_os = if (builtin.os.tag == .linux) "windows" else "linux";
    var buf: [64]u8 = undefined;
    const condition = std.fmt.bufPrint(&buf, "is_platform({s})", .{fake_os}) catch return;

    const result = try evaluate(condition, &variables, .{});
    try std.testing.expect(!result);
}

test "is_platform with quoted argument" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const current_os = @tagName(builtin.os.tag);
    var buf: [64]u8 = undefined;
    const condition = std.fmt.bufPrint(&buf, "is_platform(\"{s}\")", .{current_os}) catch return;

    const result = try evaluate(condition, &variables, .{});
    try std.testing.expect(result);
}

test "is_platform with whitespace around argument" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const current_os = @tagName(builtin.os.tag);
    var buf: [64]u8 = undefined;
    const condition = std.fmt.bufPrint(&buf, "is_platform(  {s}  )", .{current_os}) catch return;

    const result = try evaluate(condition, &variables, .{});
    try std.testing.expect(result);
}

test "is_platform with invalid platform returns false" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("is_platform(nonexistent_os_xyz)", &variables, .{});
    try std.testing.expect(!result);
}

test "is_unix returns true on macOS" {
    if (builtin.os.tag != .macos) return;
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("is_unix()", &variables, .{});
    try std.testing.expect(result);
}

test "is_unix returns true on Linux" {
    if (builtin.os.tag != .linux) return;
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("is_unix()", &variables, .{});
    try std.testing.expect(result);
}

test "platform conditions work with parentheses variations" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // Test with empty parens (should work)
    _ = try evaluate("is_macos()", &variables, .{});
    _ = try evaluate("is_linux()", &variables, .{});
    _ = try evaluate("is_windows()", &variables, .{});
    _ = try evaluate("is_unix()", &variables, .{});
}

// --- Fuzz Testing ---

test "fuzz condition evaluation" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, input: []const u8) !void {
            var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
            defer variables.deinit();

            // Add some test variables for the fuzzer to potentially reference
            variables.put("mode", "debug") catch return;
            variables.put("version", "1.0.0") catch return;

            const context = RuntimeContext{
                .watch_mode = false,
                .dry_run = false,
                .verbose = false,
            };

            // Evaluate condition - errors are expected for invalid syntax
            _ = evaluate(input, &variables, context) catch {};
        }
    }.testOne, .{});
}

// --- command() condition tests ---

test "command condition - existing command (sh)" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // /bin/sh should always exist on Unix systems
    const result = try evaluate("command(sh)", &variables, test_context);
    try std.testing.expect(result);
}

test "command condition - existing command (ls)" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // ls should be in PATH on Unix systems
    const result = try evaluate("command(ls)", &variables, test_context);
    try std.testing.expect(result);
}

test "command condition - nonexistent command" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("command(jake_nonexistent_cmd_xyz123)", &variables, test_context);
    try std.testing.expect(!result);
}

test "command condition - absolute path exists" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // /bin/sh should exist as an absolute path
    const result = try evaluate("command(/bin/sh)", &variables, test_context);
    try std.testing.expect(result);
}

test "command condition - absolute path nonexistent" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = try evaluate("command(/nonexistent/path/cmd)", &variables, test_context);
    try std.testing.expect(!result);
}

test "command condition - empty argument returns false" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // Empty string should return false, not error
    const result = try evaluate("command(\"\")", &variables, test_context);
    try std.testing.expect(!result);
}

test "command condition - with quotes" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // command("sh") should work with quotes
    const result = try evaluate("command(\"sh\")", &variables, test_context);
    try std.testing.expect(result);
}

test "command condition - with whitespace" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // Whitespace should be trimmed
    const result = try evaluate("command(  sh  )", &variables, test_context);
    try std.testing.expect(result);
}
