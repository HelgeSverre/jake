// Jake Built-in Functions
// Provides string manipulation and path utilities

const std = @import("std");
const builtin = @import("builtin");

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
    } else if (std.mem.eql(u8, func_name, "without_extensions")) {
        return withoutExtensions(allocator, arg);
    } else if (std.mem.eql(u8, func_name, "absolute_path")) {
        return absolutePath(allocator, arg);
    } else if (std.mem.eql(u8, func_name, "home")) {
        return home(allocator);
    } else if (std.mem.eql(u8, func_name, "local_bin")) {
        return localBin(allocator, arg);
    } else if (std.mem.eql(u8, func_name, "shell_config")) {
        return shellConfig(allocator);
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

/// Remove ALL extensions from a path (e.g., "file.tar.gz" -> "file")
fn withoutExtensions(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const base = std.fs.path.basename(path);

    // Handle dotfiles: if name starts with '.', preserve it
    // e.g., ".bashrc" -> ".bashrc", ".hidden.txt" -> ".hidden"
    var name_start: usize = 0;
    if (base.len > 0 and base[0] == '.') {
        name_start = 1;
    }

    // Find first dot after potential leading dot (the start of extensions)
    var first_ext_pos: ?usize = null;
    for (base[name_start..], name_start..) |c, i| {
        if (c == '.') {
            first_ext_pos = i;
            break;
        }
    }

    const stem = if (first_ext_pos) |pos| base[0..pos] else base;

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

fn home(allocator: std.mem.Allocator) FunctionError![]const u8 {
    // home() is not available on Windows (no $HOME)
    if (comptime builtin.os.tag == .windows) {
        return FunctionError.InvalidArguments;
    }
    if (std.posix.getenv("HOME")) |home_dir| {
        return allocator.dupe(u8, home_dir) catch return FunctionError.OutOfMemory;
    }
    return FunctionError.InvalidArguments;
}

fn localBin(allocator: std.mem.Allocator, name: []const u8) FunctionError![]const u8 {
    // local_bin() is not available on Windows (no $HOME/.local/bin)
    if (comptime builtin.os.tag == .windows) {
        return FunctionError.InvalidArguments;
    }
    if (std.posix.getenv("HOME")) |home_dir| {
        return std.fmt.allocPrint(allocator, "{s}/.local/bin/{s}", .{ home_dir, name }) catch return FunctionError.OutOfMemory;
    }
    return FunctionError.InvalidArguments;
}

fn shellConfig(allocator: std.mem.Allocator) FunctionError![]const u8 {
    // shell_config() is not available on Windows (no $HOME or $SHELL)
    if (comptime builtin.os.tag == .windows) {
        return FunctionError.InvalidArguments;
    }
    const home_dir = std.posix.getenv("HOME") orelse return FunctionError.InvalidArguments;
    const shell = std.posix.getenv("SHELL") orelse return FunctionError.InvalidArguments;

    // Extract shell name from path (e.g., /bin/zsh -> zsh)
    const shell_name = std.fs.path.basename(shell);

    if (std.mem.eql(u8, shell_name, "bash")) {
        return std.fmt.allocPrint(allocator, "{s}/.bashrc", .{home_dir}) catch return FunctionError.OutOfMemory;
    } else if (std.mem.eql(u8, shell_name, "zsh")) {
        return std.fmt.allocPrint(allocator, "{s}/.zshrc", .{home_dir}) catch return FunctionError.OutOfMemory;
    } else if (std.mem.eql(u8, shell_name, "fish")) {
        return std.fmt.allocPrint(allocator, "{s}/.config/fish/config.fish", .{home_dir}) catch return FunctionError.OutOfMemory;
    } else if (std.mem.eql(u8, shell_name, "sh")) {
        return std.fmt.allocPrint(allocator, "{s}/.profile", .{home_dir}) catch return FunctionError.OutOfMemory;
    } else if (std.mem.eql(u8, shell_name, "ksh")) {
        return std.fmt.allocPrint(allocator, "{s}/.kshrc", .{home_dir}) catch return FunctionError.OutOfMemory;
    } else if (std.mem.eql(u8, shell_name, "csh")) {
        return std.fmt.allocPrint(allocator, "{s}/.cshrc", .{home_dir}) catch return FunctionError.OutOfMemory;
    } else if (std.mem.eql(u8, shell_name, "tcsh")) {
        return std.fmt.allocPrint(allocator, "{s}/.tcshrc", .{home_dir}) catch return FunctionError.OutOfMemory;
    }
    // Fallback to .profile for unknown shells
    return std.fmt.allocPrint(allocator, "{s}/.profile", .{home_dir}) catch return FunctionError.OutOfMemory;
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

test "home function returns non-empty path" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "home()", &vars);
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "home function returns absolute path" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "home()", &vars);
    defer allocator.free(result);
    // Should start with / (absolute path)
    try std.testing.expect(result[0] == '/');
}

test "home function matches HOME env" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "home()", &vars);
    defer allocator.free(result);
    // Should match the HOME environment variable
    const expected = std.posix.getenv("HOME") orelse "";
    try std.testing.expectEqualStrings(expected, result);
}

test "local_bin function with simple name" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "local_bin(jake)", &vars);
    defer allocator.free(result);
    try std.testing.expect(std.mem.endsWith(u8, result, "/.local/bin/jake"));
}

test "local_bin function with quoted name" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "local_bin(\"myapp\")", &vars);
    defer allocator.free(result);
    try std.testing.expect(std.mem.endsWith(u8, result, "/.local/bin/myapp"));
}

test "local_bin function starts with home" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "local_bin(test)", &vars);
    defer allocator.free(result);
    const home_dir = std.posix.getenv("HOME") orelse "";
    try std.testing.expect(std.mem.startsWith(u8, result, home_dir));
}

test "local_bin function with variable" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();
    try vars.put("binary", "custom-tool");

    const result = try evaluate(allocator, "local_bin(binary)", &vars);
    defer allocator.free(result);
    try std.testing.expect(std.mem.endsWith(u8, result, "/.local/bin/custom-tool"));
}

test "shell_config function returns non-empty path" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "shell_config()", &vars);
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "shell_config function starts with home" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "shell_config()", &vars);
    defer allocator.free(result);
    const home_dir = std.posix.getenv("HOME") orelse "";
    try std.testing.expect(std.mem.startsWith(u8, result, home_dir));
}

test "shell_config function returns valid config file" {
    // Skip on Windows (no posix.getenv)
    if (comptime builtin.os.tag == .windows) return;

    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "shell_config()", &vars);
    defer allocator.free(result);

    // Should end with one of the known config files
    const valid_endings = [_][]const u8{
        ".bashrc",
        ".zshrc",
        ".profile",
        ".kshrc",
        ".cshrc",
        ".tcshrc",
        "config.fish",
    };

    var found_match = false;
    for (valid_endings) |ending| {
        if (std.mem.endsWith(u8, result, ending)) {
            found_match = true;
            break;
        }
    }
    try std.testing.expect(found_match);
}

// ============================================================================
// trim() tests
// ============================================================================

test "trim removes leading and trailing whitespace" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "trim(  hello  )", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "trim removes tabs and newlines" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();
    try vars.put("text", "\t\nhello\r\n");

    const result = try evaluate(allocator, "trim(text)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "trim with already trimmed string" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "trim(hello)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

// ============================================================================
// without_extension() tests
// ============================================================================

test "without_extension removes extension" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extension(file.txt)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("file", result);
}

test "without_extension with path" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extension(/path/to/file.txt)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/path/to/file", result);
}

test "without_extension with double extension" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extension(archive.tar.gz)", &vars);
    defer allocator.free(result);
    // Should remove only the last extension
    try std.testing.expectEqualStrings("archive.tar", result);
}

test "without_extension no extension" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extension(Makefile)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Makefile", result);
}

// ============================================================================
// without_extensions() - strips ALL extensions
// ============================================================================

test "without_extensions removes all extensions" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extensions(archive.tar.gz)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("archive", result);
}

test "without_extensions with single extension" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extensions(file.txt)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("file", result);
}

test "without_extensions preserves dotfile name" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extensions(.bashrc)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings(".bashrc", result);
}

test "without_extensions dotfile with extension" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extensions(.hidden.txt)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings(".hidden", result);
}

test "without_extensions with path" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extensions(/path/to/file.tar.gz)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/path/to/file", result);
}

test "without_extensions no extension" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extensions(Makefile)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Makefile", result);
}

test "without_extensions with multiple dots in filename" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    // Should strip from first dot (after any leading dot for dotfiles)
    const result = try evaluate(allocator, "without_extensions(jquery.min.js)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("jquery", result);
}

test "without_extensions deeply nested path" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extensions(/a/b/c/d/file.backup.sql.gz)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/a/b/c/d/file", result);
}

test "without_extensions just a dotfile in path" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "without_extensions(/home/user/.gitignore)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/home/user/.gitignore", result);
}

// ============================================================================
// extension() edge cases
// ============================================================================

test "extension with no extension" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "extension(Makefile)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "extension with double extension" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = try evaluate(allocator, "extension(archive.tar.gz)", &vars);
    defer allocator.free(result);
    try std.testing.expectEqualStrings(".gz", result);
}

// ============================================================================
// Error handling tests
// ============================================================================

test "unknown function returns error" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = evaluate(allocator, "nonexistent(arg)", &vars);
    try std.testing.expectError(FunctionError.UnknownFunction, result);
}

test "function with missing parenthesis returns error" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = evaluate(allocator, "uppercase(hello", &vars);
    try std.testing.expectError(FunctionError.InvalidArguments, result);
}

test "function with no opening paren returns error" {
    const allocator = std.testing.allocator;
    var vars = std.StringHashMap([]const u8).init(allocator);
    defer vars.deinit();

    const result = evaluate(allocator, "uppercase hello)", &vars);
    try std.testing.expectError(FunctionError.InvalidArguments, result);
}
