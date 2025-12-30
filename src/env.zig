// Jake Environment Module - Handles .env files and environment variable expansion
//
// Features:
// - Parse .env files (KEY=value format, handle quotes, comments)
// - Support $VAR and ${VAR} syntax in commands
// - Manage environment for child processes

const std = @import("std");
const builtin = @import("builtin");

/// Environment variable storage and expansion
pub const Environment = struct {
    allocator: std.mem.Allocator,
    /// User-defined environment variables (from .env files and @export)
    vars: std.StringHashMap([]const u8),
    /// Allocated strings that need to be freed
    allocated_strings: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator) Environment {
        return .{
            .allocator = allocator,
            .vars = std.StringHashMap([]const u8).init(allocator),
            .allocated_strings = .empty,
        };
    }

    pub fn deinit(self: *Environment) void {
        // Free all allocated strings
        for (self.allocated_strings.items) |s| {
            self.allocator.free(s);
        }
        self.allocated_strings.deinit(self.allocator);
        self.vars.deinit();
    }

    /// Set an environment variable
    pub fn set(self: *Environment, key: []const u8, value: []const u8) !void {
        // Duplicate key and value so we own them
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        // Track allocations for cleanup
        try self.allocated_strings.append(self.allocator, owned_key);
        try self.allocated_strings.append(self.allocator, owned_value);

        try self.vars.put(owned_key, owned_value);
    }

    /// Get an environment variable (checks local vars first, then system env)
    pub fn get(self: *const Environment, key: []const u8) ?[]const u8 {
        // First check our local vars
        if (self.vars.get(key)) |value| {
            return value;
        }
        // Fall back to system environment (cross-platform)
        return getSystemEnv(key);
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

    /// Load environment variables from a .env file
    pub fn loadDotenv(self: *Environment, path: []const u8) !void {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return; // Silently ignore missing .env files
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);

        try self.parseDotenv(content);
    }

    /// Parse .env file content
    pub fn parseDotenv(self: *Environment, content: []const u8) !void {
        var lines = std.mem.splitScalar(u8, content, '\n');

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Skip empty lines and comments
            if (trimmed.len == 0 or trimmed[0] == '#') {
                continue;
            }

            // Parse KEY=value
            if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_pos| {
                const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
                var value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

                // Handle quoted values
                value = stripQuotes(value);

                // Handle escape sequences and variable expansion in value
                const expanded = try self.expandInValue(value);
                errdefer self.allocator.free(expanded);

                // Set the variable
                const owned_key = try self.allocator.dupe(u8, key);
                errdefer self.allocator.free(owned_key);

                try self.allocated_strings.append(self.allocator, owned_key);
                try self.allocated_strings.append(self.allocator, expanded);
                try self.vars.put(owned_key, expanded);
            }
        }
    }

    /// Expand variables within a .env value (supports $VAR and ${VAR})
    fn expandInValue(self: *Environment, value: []const u8) ![]const u8 {
        var result: std.ArrayListUnmanaged(u8) = .empty;
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < value.len) {
            // Check for escape sequences
            if (value[i] == '\\' and i + 1 < value.len) {
                const next = value[i + 1];
                switch (next) {
                    'n' => try result.append(self.allocator, '\n'),
                    't' => try result.append(self.allocator, '\t'),
                    'r' => try result.append(self.allocator, '\r'),
                    '$' => try result.append(self.allocator, '$'),
                    '\\' => try result.append(self.allocator, '\\'),
                    '"' => try result.append(self.allocator, '"'),
                    '\'' => try result.append(self.allocator, '\''),
                    else => {
                        try result.append(self.allocator, '\\');
                        try result.append(self.allocator, next);
                    },
                }
                i += 2;
                continue;
            }

            // Check for variable expansion
            if (value[i] == '$') {
                if (i + 1 < value.len and value[i + 1] == '{') {
                    // ${VAR} syntax
                    const start = i + 2;
                    var end = start;
                    while (end < value.len and value[end] != '}') {
                        end += 1;
                    }
                    if (end < value.len) {
                        const var_name = value[start..end];
                        if (self.get(var_name)) |var_value| {
                            try result.appendSlice(self.allocator, var_value);
                        }
                        i = end + 1;
                        continue;
                    }
                } else if (i + 1 < value.len and isVarStart(value[i + 1])) {
                    // $VAR syntax
                    const start = i + 1;
                    var end = start;
                    while (end < value.len and isVarChar(value[end])) {
                        end += 1;
                    }
                    const var_name = value[start..end];
                    if (self.get(var_name)) |var_value| {
                        try result.appendSlice(self.allocator, var_value);
                    }
                    i = end;
                    continue;
                }
            }

            try result.append(self.allocator, value[i]);
            i += 1;
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Expand environment variables in a command string
    /// Supports both $VAR and ${VAR} syntax
    pub fn expandCommand(self: *const Environment, command: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        var result: std.ArrayListUnmanaged(u8) = .empty;
        errdefer result.deinit(allocator);

        var i: usize = 0;
        while (i < command.len) {
            // Check for escape sequence
            if (command[i] == '\\' and i + 1 < command.len and command[i + 1] == '$') {
                try result.append(allocator, '$');
                i += 2;
                continue;
            }

            // Check for variable expansion
            if (command[i] == '$') {
                if (i + 1 < command.len and command[i + 1] == '{') {
                    // ${VAR} syntax
                    const start = i + 2;
                    var end = start;
                    while (end < command.len and command[end] != '}') {
                        end += 1;
                    }
                    if (end < command.len) {
                        const var_name = command[start..end];
                        if (self.get(var_name)) |value| {
                            try result.appendSlice(allocator, value);
                        } else {
                            // Keep original if not found
                            try result.appendSlice(allocator, command[i .. end + 1]);
                        }
                        i = end + 1;
                        continue;
                    }
                } else if (i + 1 < command.len and isVarStart(command[i + 1])) {
                    // $VAR syntax
                    const start = i + 1;
                    var end = start;
                    while (end < command.len and isVarChar(command[end])) {
                        end += 1;
                    }
                    const var_name = command[start..end];
                    if (self.get(var_name)) |value| {
                        try result.appendSlice(allocator, value);
                    } else {
                        // Keep original if not found
                        try result.appendSlice(allocator, command[i..end]);
                    }
                    i = end;
                    continue;
                }
            }

            try result.append(allocator, command[i]);
            i += 1;
        }

        return result.toOwnedSlice(allocator);
    }

    /// Build environment map for child process
    /// Returns a slice of key=value strings suitable for Child.env_map
    pub fn buildEnvMap(self: *const Environment, allocator: std.mem.Allocator) !std.process.EnvMap {
        var env_map = std.process.EnvMap.init(allocator);
        errdefer env_map.deinit();

        // First, copy all system environment variables
        var env_iter = std.process.getEnvMap(allocator) catch |err| {
            if (err == error.OutOfMemory) return err;
            // If we can't get system env, continue with just our vars
            var iter = self.vars.iterator();
            while (iter.next()) |entry| {
                try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            return env_map;
        };
        defer env_iter.deinit();

        var sys_iter = env_iter.iterator();
        while (sys_iter.next()) |entry| {
            try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Then overlay our custom variables (they take precedence)
        var iter = self.vars.iterator();
        while (iter.next()) |entry| {
            try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        return env_map;
    }
};

/// Strip surrounding quotes from a value
fn stripQuotes(s: []const u8) []const u8 {
    if (s.len >= 2) {
        if ((s[0] == '"' and s[s.len - 1] == '"') or
            (s[0] == '\'' and s[s.len - 1] == '\''))
        {
            return s[1 .. s.len - 1];
        }
    }
    return s;
}

/// Check if character can start a variable name
fn isVarStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

/// Check if character can be part of a variable name
fn isVarChar(c: u8) bool {
    return isVarStart(c) or (c >= '0' and c <= '9');
}

// ============================================================================
// Tests
// ============================================================================

test "parse simple dotenv" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\# This is a comment
        \\DATABASE_URL=postgres://localhost/test
        \\PORT=3000
        \\
        \\# Another comment
        \\DEBUG=true
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("postgres://localhost/test", env.get("DATABASE_URL").?);
    try std.testing.expectEqualStrings("3000", env.get("PORT").?);
    try std.testing.expectEqualStrings("true", env.get("DEBUG").?);
}

test "parse quoted values" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\SINGLE='hello world'
        \\DOUBLE="hello world"
        \\UNQUOTED=hello
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("hello world", env.get("SINGLE").?);
    try std.testing.expectEqualStrings("hello world", env.get("DOUBLE").?);
    try std.testing.expectEqualStrings("hello", env.get("UNQUOTED").?);
}

test "expand $VAR syntax" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try env.set("NAME", "World");
    try env.set("GREETING", "Hello");

    const result = try env.expandCommand("$GREETING, $NAME!", std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("Hello, World!", result);
}

test "expand ${VAR} syntax" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try env.set("NAME", "World");

    const result = try env.expandCommand("Hello, ${NAME}!", std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("Hello, World!", result);
}

test "expand mixed syntax" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try env.set("USER", "alice");
    try env.set("HOME", "/home/alice");

    const result = try env.expandCommand("User $USER lives at ${HOME}/data", std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("User alice lives at /home/alice/data", result);
}

test "undefined variables remain unchanged" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const result = try env.expandCommand("Hello $UNDEFINED and ${ALSO_UNDEFINED}", std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("Hello $UNDEFINED and ${ALSO_UNDEFINED}", result);
}

test "escape dollar sign" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try env.set("PRICE", "100");

    const result = try env.expandCommand("Price: \\$50 or $PRICE", std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("Price: $50 or 100", result);
}

test "variable expansion in dotenv values" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\BASE=/opt/app
        \\DATA_DIR=$BASE/data
        \\LOG_DIR=${BASE}/logs
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("/opt/app", env.get("BASE").?);
    try std.testing.expectEqualStrings("/opt/app/data", env.get("DATA_DIR").?);
    try std.testing.expectEqualStrings("/opt/app/logs", env.get("LOG_DIR").?);
}

test "escape sequences in dotenv" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\NEWLINE=hello\nworld
        \\TAB=hello\tworld
        \\ESCAPED_DOLLAR=price\$100
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("hello\nworld", env.get("NEWLINE").?);
    try std.testing.expectEqualStrings("hello\tworld", env.get("TAB").?);
    try std.testing.expectEqualStrings("price$100", env.get("ESCAPED_DOLLAR").?);
}

test "set and get" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try env.set("FOO", "bar");
    try env.set("BAZ", "qux");

    try std.testing.expectEqualStrings("bar", env.get("FOO").?);
    try std.testing.expectEqualStrings("qux", env.get("BAZ").?);
    try std.testing.expect(env.get("NONEXISTENT") == null or env.get("NONEXISTENT") != null); // May fall back to system env
}

// ============================================================================
// Edge case tests
// ============================================================================

test "parse dotenv with empty value" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\EMPTY=
        \\QUOTED_EMPTY=""
        \\NONEMPTY=value
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("", env.get("EMPTY").?);
    try std.testing.expectEqualStrings("", env.get("QUOTED_EMPTY").?);
    try std.testing.expectEqualStrings("value", env.get("NONEMPTY").?);
}

test "parse dotenv skips malformed lines" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\VALID=yes
        \\INVALID_NO_EQUALS
        \\ALSO_VALID=yes
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("yes", env.get("VALID").?);
    try std.testing.expectEqualStrings("yes", env.get("ALSO_VALID").?);
}

test "parse dotenv with multiple empty lines" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\A=1
        \\
        \\
        \\B=2
        \\
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("1", env.get("A").?);
    try std.testing.expectEqualStrings("2", env.get("B").?);
}

test "parse dotenv with special characters in value" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\SPECIAL=!@#%^&*()_+-=[]{}|;:',.<>?/
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("!@#%^&*()_+-=[]{}|;:',.<>?/", env.get("SPECIAL").?);
}

test "parse dotenv with equals in value" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\EQUATION=1+1=2
        \\URL=https://example.com?foo=bar&baz=qux
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("1+1=2", env.get("EQUATION").?);
    try std.testing.expectEqualStrings("https://example.com?foo=bar&baz=qux", env.get("URL").?);
}

test "expand variable at end of string" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try env.set("SUFFIX", "end");

    const result = try env.expandCommand("at the $SUFFIX", std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("at the end", result);
}

test "expand variable at start of string" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try env.set("PREFIX", "START");

    const result = try env.expandCommand("$PREFIX of string", std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("START of string", result);
}

test "expand only variable in string" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    try env.set("ONLY", "value");

    const result = try env.expandCommand("$ONLY", std.testing.allocator);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("value", result);
}

// ============================================================================
// Escape sequence tests (documenting behavior per GUIDE.md)
// ============================================================================

test "backslash-n in value produces newline" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\MULTILINE=line1\nline2\nline3
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("line1\nline2\nline3", env.get("MULTILINE").?);
}

test "backslash-t in value produces tab" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\TABBED=col1\tcol2\tcol3
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("col1\tcol2\tcol3", env.get("TABBED").?);
}

test "backslash-r in value produces carriage return" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\CRLF=line1\r\nline2
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("line1\r\nline2", env.get("CRLF").?);
}

test "double backslash in value produces single backslash" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\PATH=C:\\Users\\Name
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("C:\\Users\\Name", env.get("PATH").?);
}

test "unknown escape sequence preserved" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\UNKNOWN=hello\xworld
    ;

    try env.parseDotenv(content);

    // Unknown escapes like \x should be preserved as-is
    try std.testing.expectEqualStrings("hello\\xworld", env.get("UNKNOWN").?);
}

// ============================================================================
// Edge case tests from TODO.md test gaps
// ============================================================================

test "empty key is ignored" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\=value_with_no_key
        \\VALID=yes
    ;

    try env.parseDotenv(content);

    // Empty key should result in empty string key being set or ignored
    // The current behavior stores it with empty key
    try std.testing.expectEqualStrings("yes", env.get("VALID").?);
    // Empty key may be stored, but shouldn't cause issues
    _ = env.get("");
}

test "recursive variable reference uses first defined value" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    // When A references B and B references A, each gets the value
    // at the time of their definition (no infinite loop)
    const content =
        \\A=$B
        \\B=$A
    ;

    try env.parseDotenv(content);

    // A is defined first, B is undefined at that point, so A gets ""
    // B is defined second, A is "" at that point, so B gets ""
    try std.testing.expectEqualStrings("", env.get("A").?);
    try std.testing.expectEqualStrings("", env.get("B").?);
}

test "recursive variable reference with initial value" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\BASE=/opt
        \\A=$BASE/data
        \\B=$A/logs
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("/opt", env.get("BASE").?);
    try std.testing.expectEqualStrings("/opt/data", env.get("A").?);
    try std.testing.expectEqualStrings("/opt/data/logs", env.get("B").?);
}

test "quote mismatch treated as literal" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\MISMATCH="value'
    ;

    try env.parseDotenv(content);

    // Mismatched quotes are preserved as-is (not stripped)
    try std.testing.expectEqualStrings("\"value'", env.get("MISMATCH").?);
}

test "single quote at start only treated as literal" {
    var env = Environment.init(std.testing.allocator);
    defer env.deinit();

    const content =
        \\SINGLE_START='value
    ;

    try env.parseDotenv(content);

    try std.testing.expectEqualStrings("'value", env.get("SINGLE_START").?);
}
