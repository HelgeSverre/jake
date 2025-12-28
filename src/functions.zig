// Jake Built-in Functions
// Provides string manipulation and path utilities

const std = @import("std");

pub const FunctionError = error{
    UnknownFunction,
    InvalidArguments,
    OutOfMemory,
};

/// Evaluate a function call like "uppercase(value)" or "dirname(/path/to/file)"
pub fn evaluate(allocator: std.mem.Allocator, call: []const u8, variables: *const std.StringHashMap([]const u8)) FunctionError![]const u8 {
    // Parse function name and arguments
    const paren_start = std.mem.indexOfScalar(u8, call, '(') orelse return FunctionError.InvalidArguments;
    const paren_end = std.mem.lastIndexOfScalar(u8, call, ')') orelse return FunctionError.InvalidArguments;

    const func_name = std.mem.trim(u8, call[0..paren_start], " \t");
    const args_str = call[paren_start + 1 .. paren_end];

    // Resolve variable references in args
    const arg = resolveArg(args_str, variables);

    // Dispatch to function implementation
    if (std.mem.eql(u8, func_name, "uppercase")) {
        return uppercase(allocator, arg);
    } else if (std.mem.eql(u8, func_name, "lowercase")) {
        return lowercase(allocator, arg);
    } else if (std.mem.eql(u8, func_name, "trim")) {
        return trim(allocator, arg);
    } else if (std.mem.eql(u8, func_name, "dirname")) {
        return dirname(allocator, arg);
    } else if (std.mem.eql(u8, func_name, "basename")) {
        return basename(allocator, arg);
    } else if (std.mem.eql(u8, func_name, "extension")) {
        return extension(allocator, arg);
    } else if (std.mem.eql(u8, func_name, "without_extension")) {
        return withoutExtension(allocator, arg);
    } else if (std.mem.eql(u8, func_name, "absolute_path")) {
        return absolutePath(allocator, arg);
    }

    return FunctionError.UnknownFunction;
}

fn resolveArg(arg: []const u8, variables: *const std.StringHashMap([]const u8)) []const u8 {
    const trimmed = std.mem.trim(u8, arg, " \t\"'");
    if (variables.get(trimmed)) |value| {
        return value;
    }
    return trimmed;
}

fn uppercase(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const result = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

fn lowercase(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const result = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

fn trim(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, s, " \t\n\r");
    return try allocator.dupe(u8, trimmed);
}

fn dirname(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.fs.path.dirname(path)) |dir| {
        return try allocator.dupe(u8, dir);
    }
    return try allocator.dupe(u8, ".");
}

fn basename(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const base = std.fs.path.basename(path);
    return try allocator.dupe(u8, base);
}

fn extension(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const ext = std.fs.path.extension(path);
    return try allocator.dupe(u8, ext);
}

fn withoutExtension(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const stem = std.fs.path.stem(path);
    if (std.fs.path.dirname(path)) |dir| {
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, stem });
    }
    return try allocator.dupe(u8, stem);
}

fn absolutePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const cwd = std.fs.cwd();
    const abs = cwd.realpathAlloc(allocator, path) catch {
        // If path doesn't exist, join with cwd
        const cwd_path = cwd.realpathAlloc(allocator, ".") catch return FunctionError.OutOfMemory;
        defer allocator.free(cwd_path);
        return try std.fs.path.join(allocator, &[_][]const u8{ cwd_path, path });
    };
    return abs;
}

// Tests
test "uppercase function" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "uppercase(hello)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("HELLO", result);
}

test "lowercase function" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "lowercase(HELLO)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "dirname function" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "dirname(/path/to/file.txt)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/path/to", result);
}

test "basename function" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "basename(/path/to/file.txt)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("file.txt", result);
}

test "extension function" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "extension(file.txt)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings(".txt", result);
}

test "function with variable" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();
    try vars.put("name", "world");

    const result = try evaluate(allocator, "uppercase(name)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("WORLD", result);
}
