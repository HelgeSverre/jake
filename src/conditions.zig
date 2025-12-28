// Jake Conditions - Evaluates conditional expressions for @if/@elif directives

const std = @import("std");

pub const ConditionError = error{
    InvalidSyntax,
    UnknownFunction,
    MissingArgument,
    OutOfMemory,
};

/// Evaluates a condition expression like "env(VAR)", "exists(path)", "eq(a, b)"
pub fn evaluate(
    condition: []const u8,
    variables: *const std.StringHashMap([]const u8),
) ConditionError!bool {
    const trimmed = std.mem.trim(u8, condition, " \t");

    // Parse function call: func(args)
    if (std.mem.indexOf(u8, trimmed, "(")) |paren_start| {
        const func_name = trimmed[0..paren_start];
        const paren_end = std.mem.lastIndexOf(u8, trimmed, ")") orelse return ConditionError.InvalidSyntax;

        if (paren_start + 1 >= paren_end) {
            return ConditionError.MissingArgument;
        }

        const args_str = trimmed[paren_start + 1 .. paren_end];

        if (std.mem.eql(u8, func_name, "env")) {
            return evaluateEnv(args_str);
        } else if (std.mem.eql(u8, func_name, "exists")) {
            return evaluateExists(args_str, variables);
        } else if (std.mem.eql(u8, func_name, "eq")) {
            return evaluateEq(args_str, variables, true);
        } else if (std.mem.eql(u8, func_name, "neq")) {
            return evaluateEq(args_str, variables, false);
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

    if (std.posix.getenv(var_name)) |value| {
        return value.len > 0;
    }
    return false;
}

/// exists(path) - returns true if file or directory exists
fn evaluateExists(args: []const u8, variables: *const std.StringHashMap([]const u8)) bool {
    const path = expandVariablesSimple(stripQuotes(std.mem.trim(u8, args, " \t")), variables);

    std.fs.cwd().access(path, .{}) catch {
        return false;
    };
    return true;
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

        if (std.posix.getenv(var_name)) |env_val| {
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

    const has_path = try evaluate("env(PATH)", &variables);
    try std.testing.expect(has_path);
}

test "env condition - unset variable" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const has_nonexistent = try evaluate("env(JAKE_TEST_NONEXISTENT_VAR_12345)", &variables);
    try std.testing.expect(!has_nonexistent);
}

test "exists condition - existing path" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // Current directory should exist
    const exists_cwd = try evaluate("exists(.)", &variables);
    try std.testing.expect(exists_cwd);
}

test "exists condition - non-existing path" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const exists_none = try evaluate("exists(/nonexistent/path/12345)", &variables);
    try std.testing.expect(!exists_none);
}

test "eq condition - equal strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const are_equal = try evaluate("eq(hello, hello)", &variables);
    try std.testing.expect(are_equal);
}

test "eq condition - unequal strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const are_equal = try evaluate("eq(hello, world)", &variables);
    try std.testing.expect(!are_equal);
}

test "neq condition - unequal strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const are_not_equal = try evaluate("neq(hello, world)", &variables);
    try std.testing.expect(are_not_equal);
}

test "neq condition - equal strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const are_not_equal = try evaluate("neq(hello, hello)", &variables);
    try std.testing.expect(!are_not_equal);
}

test "eq with jake variable" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();
    try variables.put("mode", "debug");

    const is_debug = try evaluate("eq(mode, debug)", &variables);
    try std.testing.expect(is_debug);
}

test "eq with quoted strings" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const are_equal = try evaluate("eq(\"hello world\", \"hello world\")", &variables);
    try std.testing.expect(are_equal);
}

test "invalid syntax" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = evaluate("invalid", &variables);
    try std.testing.expectError(ConditionError.InvalidSyntax, result);
}

test "unknown function" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const result = evaluate("unknown(arg)", &variables);
    try std.testing.expectError(ConditionError.UnknownFunction, result);
}

test "exists with variable" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();
    try variables.put("cwd", ".");

    const exists_var = try evaluate("exists({{cwd}})", &variables);
    try std.testing.expect(exists_var);
}

test "eq with env variable" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // HOME should be set on most systems
    if (std.posix.getenv("HOME")) |home_val| {
        // Create a variable with the same value
        try variables.put("home", home_val);

        const matches = try evaluate("eq($HOME, home)", &variables);
        try std.testing.expect(matches);
    }
}

test "neq with different env variables" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // PATH and HOME should be different
    const result = try evaluate("neq($PATH, $HOME)", &variables);
    try std.testing.expect(result);
}

test "eq with empty vs non-empty" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();
    try variables.put("empty", "");
    try variables.put("non_empty", "value");

    const not_equal = try evaluate("neq(empty, non_empty)", &variables);
    try std.testing.expect(not_equal);
}

test "eq with braced env variable" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // HOME should be set on most systems
    if (std.posix.getenv("HOME")) |_| {
        const matches = try evaluate("eq(${HOME}, $HOME)", &variables);
        try std.testing.expect(matches);
    }
}
