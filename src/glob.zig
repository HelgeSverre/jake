// Jake Glob - Pattern matching for file globs
//
// Supports:
// - * matches any characters except /
// - ** matches any characters including / (recursive)
// - ? matches a single character (except /)
// - [abc] matches any character in the set
// - [a-z] matches any character in the range
// - [!abc] or [^abc] matches any character not in the set

const std = @import("std");

/// Glob pattern matcher and file expander
pub const Glob = struct {
    allocator: std.mem.Allocator,
    pattern: []const u8,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) Glob {
        return .{
            .allocator = allocator,
            .pattern = pattern,
        };
    }

    /// Expand the glob pattern to a list of matching file paths
    pub fn expand(self: *Glob) ![][]const u8 {
        return expandGlob(self.allocator, self.pattern);
    }
};

/// Check if a path matches a glob pattern
pub fn match(pattern: []const u8, path: []const u8) bool {
    return matchImpl(pattern, path, 0, 0);
}

fn matchImpl(pattern: []const u8, path: []const u8, p_start: usize, s_start: usize) bool {
    var p_idx = p_start;
    var s_idx = s_start;

    while (p_idx < pattern.len) {
        if (pattern[p_idx] == '*') {
            // Check for **
            if (p_idx + 1 < pattern.len and pattern[p_idx + 1] == '*') {
                // ** - matches anything including /
                p_idx += 2;

                // Skip trailing / after ** if present
                if (p_idx < pattern.len and pattern[p_idx] == '/') {
                    p_idx += 1;
                }

                // If ** is at the end, match everything
                if (p_idx >= pattern.len) {
                    return true;
                }

                // Try matching the rest of the pattern at every position
                var i = s_idx;
                while (i <= path.len) : (i += 1) {
                    if (matchImpl(pattern, path, p_idx, i)) {
                        return true;
                    }
                }
                return false;
            } else {
                // * - matches anything except /
                p_idx += 1;

                // If * is at the end, match until /
                if (p_idx >= pattern.len) {
                    // Check no / in remainder
                    while (s_idx < path.len) : (s_idx += 1) {
                        if (path[s_idx] == '/') return false;
                    }
                    return true;
                }

                // Try matching the rest of the pattern at every position (not crossing /)
                var i = s_idx;
                while (i <= path.len) : (i += 1) {
                    if (i > s_idx and path[i - 1] == '/') break;
                    if (matchImpl(pattern, path, p_idx, i)) {
                        return true;
                    }
                }
                return false;
            }
        } else if (pattern[p_idx] == '?') {
            // ? - matches single character except /
            if (s_idx >= path.len or path[s_idx] == '/') {
                return false;
            }
            p_idx += 1;
            s_idx += 1;
        } else if (pattern[p_idx] == '[') {
            // Character class
            if (s_idx >= path.len) {
                return false;
            }

            const char = path[s_idx];
            if (char == '/') {
                return false; // [ ] never matches /
            }

            const class_result = matchCharClass(pattern, p_idx, char);
            if (!class_result.matched) {
                return false;
            }
            p_idx = class_result.end_idx;
            s_idx += 1;
        } else {
            // Literal character
            if (s_idx >= path.len or pattern[p_idx] != path[s_idx]) {
                return false;
            }
            p_idx += 1;
            s_idx += 1;
        }
    }

    // Pattern exhausted, check if path is also exhausted
    return s_idx >= path.len;
}

const CharClassResult = struct {
    matched: bool,
    end_idx: usize,
};

fn matchCharClass(pattern: []const u8, start: usize, char: u8) CharClassResult {
    var idx = start + 1; // Skip opening [
    var negated = false;
    var matched = false;

    // Check for negation
    if (idx < pattern.len and (pattern[idx] == '!' or pattern[idx] == '^')) {
        negated = true;
        idx += 1;
    }

    // Handle ] as first character (literal)
    if (idx < pattern.len and pattern[idx] == ']') {
        if (char == ']') matched = true;
        idx += 1;
    }

    while (idx < pattern.len and pattern[idx] != ']') {
        // Check for range
        if (idx + 2 < pattern.len and pattern[idx + 1] == '-' and pattern[idx + 2] != ']') {
            const range_start = pattern[idx];
            const range_end = pattern[idx + 2];
            if (char >= range_start and char <= range_end) {
                matched = true;
            }
            idx += 3;
        } else {
            if (pattern[idx] == char) {
                matched = true;
            }
            idx += 1;
        }
    }

    // Skip closing ]
    if (idx < pattern.len and pattern[idx] == ']') {
        idx += 1;
    }

    return .{
        .matched = if (negated) !matched else matched,
        .end_idx = idx,
    };
}

/// Expand a glob pattern to a list of matching file paths
pub fn expandGlob(allocator: std.mem.Allocator, pattern: []const u8) ![][]const u8 {
    var result: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (result.items) |item| {
            allocator.free(item);
        }
        result.deinit(allocator);
    }

    // Parse the pattern to find the base directory and the glob part
    const parsed = parsePattern(pattern);

    // Open the base directory
    var base_dir: std.fs.Dir = undefined;
    if (parsed.base.len == 0) {
        base_dir = std.fs.cwd();
    } else {
        base_dir = std.fs.cwd().openDir(parsed.base, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound or err == error.NotDir) {
                return result.toOwnedSlice(allocator);
            }
            return err;
        };
    }
    defer if (parsed.base.len > 0) base_dir.close();

    // Walk the directory tree
    try walkAndMatch(allocator, base_dir, parsed.base, parsed.glob_part, &result);

    return result.toOwnedSlice(allocator);
}

const ParsedPattern = struct {
    base: []const u8,
    glob_part: []const u8,
};

fn parsePattern(pattern: []const u8) ParsedPattern {
    // Find the first glob character
    var first_glob: ?usize = null;

    for (pattern, 0..) |c, i| {
        if (c == '*' or c == '?' or c == '[') {
            first_glob = i;
            break;
        }
    }

    if (first_glob) |idx| {
        // Find the last / before the first glob character
        var last_slash: ?usize = null;
        var i: usize = 0;
        while (i < idx) : (i += 1) {
            if (pattern[i] == '/') {
                last_slash = i;
            }
        }

        if (last_slash) |slash_idx| {
            return .{
                .base = pattern[0..slash_idx],
                .glob_part = pattern[slash_idx + 1 ..],
            };
        } else {
            return .{
                .base = "",
                .glob_part = pattern,
            };
        }
    } else {
        // No glob characters, treat as literal path
        return .{
            .base = "",
            .glob_part = pattern,
        };
    }
}

fn walkAndMatch(
    allocator: std.mem.Allocator,
    dir_arg: std.fs.Dir,
    base_path: []const u8,
    glob_pattern: []const u8,
    result: *std.ArrayListUnmanaged([]const u8),
) !void {
    var dir = dir_arg; // Make mutable copy to allow openDir calls
    // Check if pattern starts with **
    const is_recursive = glob_pattern.len >= 2 and
        glob_pattern[0] == '*' and glob_pattern[1] == '*';

    var walker = dir.iterate();
    while (try walker.next()) |entry| {
        // Build the full path for this entry
        const full_path = try buildPath(allocator, base_path, entry.name);
        defer allocator.free(full_path);

        // Build the relative path for matching (from base)
        const rel_path = entry.name;

        if (entry.kind == .directory) {
            if (is_recursive) {
                // For **, we need to recurse and also try matching
                var sub_dir = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
                defer sub_dir.close();

                // Try matching the directory itself (for patterns like **/foo)
                if (match(glob_pattern, rel_path)) {
                    const path_copy = try allocator.dupe(u8, full_path);
                    try result.append(allocator, path_copy);
                }

                // Recurse into subdirectory
                try walkAndMatchRecursive(allocator, sub_dir, full_path, glob_pattern, result);
            } else {
                // Check if we should recurse based on pattern
                const next_part = getNextPatternPart(glob_pattern);
                if (next_part.is_literal and std.mem.eql(u8, next_part.part, entry.name)) {
                    // This directory matches the next literal part
                    var sub_dir = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
                    defer sub_dir.close();
                    try walkAndMatch(allocator, sub_dir, full_path, next_part.rest, result);
                } else if (!next_part.is_literal) {
                    // Pattern part, try to match and recurse
                    if (matchPart(next_part.part, entry.name)) {
                        var sub_dir = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
                        defer sub_dir.close();
                        try walkAndMatch(allocator, sub_dir, full_path, next_part.rest, result);
                    }
                }
            }
        } else {
            // It's a file, check if it matches the pattern
            if (match(glob_pattern, rel_path)) {
                const path_copy = try allocator.dupe(u8, full_path);
                try result.append(allocator, path_copy);
            }
        }
    }
}

fn walkAndMatchRecursive(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    base_path: []const u8,
    glob_pattern: []const u8,
    result: *std.ArrayListUnmanaged([]const u8),
) !void {
    var walker = dir.iterate();
    while (try walker.next()) |entry| {
        const full_path = try buildPath(allocator, base_path, entry.name);
        defer allocator.free(full_path);

        // For **, calculate the relative path from the original base
        const rel_path = getRelativePath(full_path, glob_pattern);

        if (entry.kind == .directory) {
            // Try matching the directory path
            if (match(glob_pattern, rel_path)) {
                const path_copy = try allocator.dupe(u8, full_path);
                try result.append(allocator, path_copy);
            }

            // Always recurse for **
            var sub_dir = dir.openDir(entry.name, .{ .iterate = true }) catch continue;
            defer sub_dir.close();
            try walkAndMatchRecursive(allocator, sub_dir, full_path, glob_pattern, result);
        } else {
            // Match file against pattern
            if (match(glob_pattern, rel_path)) {
                const path_copy = try allocator.dupe(u8, full_path);
                try result.append(allocator, path_copy);
            }
        }
    }
}

fn getRelativePath(full_path: []const u8, pattern: []const u8) []const u8 {
    _ = pattern;
    // Find the part after the base
    if (std.mem.lastIndexOf(u8, full_path, "/")) |idx| {
        // Get everything after the original base
        // For now, just return the last component
        return full_path[idx + 1 ..];
    }
    return full_path;
}

const PatternPart = struct {
    part: []const u8,
    rest: []const u8,
    is_literal: bool,
};

fn getNextPatternPart(pattern: []const u8) PatternPart {
    // Find the first /
    var slash_idx: ?usize = null;
    for (pattern, 0..) |c, i| {
        if (c == '/') {
            slash_idx = i;
            break;
        }
    }

    const part = if (slash_idx) |idx| pattern[0..idx] else pattern;
    const rest = if (slash_idx) |idx| pattern[idx + 1 ..] else "";

    // Check if part contains any glob characters
    var is_literal = true;
    for (part) |c| {
        if (c == '*' or c == '?' or c == '[') {
            is_literal = false;
            break;
        }
    }

    return .{
        .part = part,
        .rest = rest,
        .is_literal = is_literal,
    };
}

fn matchPart(pattern: []const u8, name: []const u8) bool {
    // Match a single path component against a pattern part
    return match(pattern, name);
}

fn buildPath(allocator: std.mem.Allocator, base: []const u8, name: []const u8) ![]const u8 {
    if (base.len == 0) {
        return allocator.dupe(u8, name);
    }
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, name });
}

/// Check if a pattern contains any glob characters
pub fn isGlobPattern(pattern: []const u8) bool {
    for (pattern) |c| {
        if (c == '*' or c == '?' or c == '[') {
            return true;
        }
    }
    return false;
}

// Tests
test "match literal" {
    try std.testing.expect(match("hello.txt", "hello.txt"));
    try std.testing.expect(!match("hello.txt", "hello.md"));
    try std.testing.expect(!match("hello.txt", "hello.txt.bak"));
}

test "match single asterisk" {
    try std.testing.expect(match("*.txt", "hello.txt"));
    try std.testing.expect(match("*.txt", "world.txt"));
    try std.testing.expect(!match("*.txt", "hello.md"));
    try std.testing.expect(!match("*.txt", "dir/hello.txt"));
    try std.testing.expect(match("hello.*", "hello.txt"));
    try std.testing.expect(match("hello.*", "hello.md"));
    try std.testing.expect(match("*", "anything"));
    try std.testing.expect(!match("*", "with/slash"));
}

test "match double asterisk" {
    try std.testing.expect(match("**/*.txt", "hello.txt"));
    try std.testing.expect(match("**/*.txt", "dir/hello.txt"));
    try std.testing.expect(match("**/*.txt", "a/b/c/hello.txt"));
    try std.testing.expect(!match("**/*.txt", "hello.md"));
    try std.testing.expect(match("**/test.txt", "test.txt"));
    try std.testing.expect(match("**/test.txt", "foo/test.txt"));
    try std.testing.expect(match("**/test.txt", "foo/bar/test.txt"));
    try std.testing.expect(match("src/**", "src/main.zig"));
    try std.testing.expect(match("src/**", "src/foo/bar.zig"));
}

test "match question mark" {
    try std.testing.expect(match("hello?.txt", "hello1.txt"));
    try std.testing.expect(match("hello?.txt", "hellox.txt"));
    try std.testing.expect(!match("hello?.txt", "hello.txt"));
    try std.testing.expect(!match("hello?.txt", "hello12.txt"));
    try std.testing.expect(!match("?", "/"));
}

test "match character class" {
    try std.testing.expect(match("[abc].txt", "a.txt"));
    try std.testing.expect(match("[abc].txt", "b.txt"));
    try std.testing.expect(match("[abc].txt", "c.txt"));
    try std.testing.expect(!match("[abc].txt", "d.txt"));
}

test "match character range" {
    try std.testing.expect(match("[a-z].txt", "a.txt"));
    try std.testing.expect(match("[a-z].txt", "m.txt"));
    try std.testing.expect(match("[a-z].txt", "z.txt"));
    try std.testing.expect(!match("[a-z].txt", "A.txt"));
    try std.testing.expect(!match("[a-z].txt", "1.txt"));
    try std.testing.expect(match("[0-9].txt", "5.txt"));
}

test "match negated class" {
    try std.testing.expect(match("[!abc].txt", "d.txt"));
    try std.testing.expect(match("[!abc].txt", "z.txt"));
    try std.testing.expect(!match("[!abc].txt", "a.txt"));
    try std.testing.expect(match("[^abc].txt", "d.txt"));
    try std.testing.expect(!match("[^abc].txt", "b.txt"));
}

test "match complex patterns" {
    try std.testing.expect(match("src/*.zig", "src/main.zig"));
    try std.testing.expect(!match("src/*.zig", "test/main.zig"));
    try std.testing.expect(match("src/**/*.zig", "src/main.zig"));
    try std.testing.expect(match("src/**/*.zig", "src/sub/module.zig"));
    try std.testing.expect(match("test[0-9]?.txt", "test1a.txt"));
    try std.testing.expect(match("test[0-9]?.txt", "test9z.txt"));
    try std.testing.expect(!match("test[0-9]?.txt", "testab.txt"));
}

test "isGlobPattern" {
    try std.testing.expect(isGlobPattern("*.txt"));
    try std.testing.expect(isGlobPattern("hello?.txt"));
    try std.testing.expect(isGlobPattern("[abc].txt"));
    try std.testing.expect(isGlobPattern("**/*.zig"));
    try std.testing.expect(!isGlobPattern("hello.txt"));
    try std.testing.expect(!isGlobPattern("src/main.zig"));
}

test "parsePattern" {
    const p1 = parsePattern("src/*.zig");
    try std.testing.expectEqualStrings("src", p1.base);
    try std.testing.expectEqualStrings("*.zig", p1.glob_part);

    const p2 = parsePattern("*.txt");
    try std.testing.expectEqualStrings("", p2.base);
    try std.testing.expectEqualStrings("*.txt", p2.glob_part);

    const p3 = parsePattern("a/b/c/*.txt");
    try std.testing.expectEqualStrings("a/b/c", p3.base);
    try std.testing.expectEqualStrings("*.txt", p3.glob_part);
}
