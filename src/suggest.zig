// suggest.zig - Recipe name suggestion using Levenshtein distance
//
// When a user mistypes a recipe name, this module finds similar recipes
// and suggests them in the error message.

const std = @import("std");
const Recipe = @import("parser.zig").Recipe;

/// Compute Levenshtein distance between two strings.
/// Uses Wagner-Fischer algorithm with O(min(m,n)) space optimization.
pub fn levenshteinDistance(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    // Ensure s1 is shorter for space optimization
    const s1 = if (a.len <= b.len) a else b;
    const s2 = if (a.len <= b.len) b else a;

    // Use stack-allocated arrays (max string length 256)
    var prev_row: [257]usize = undefined;
    var curr_row: [257]usize = undefined;

    // Handle strings longer than our buffer
    if (s1.len > 256) return s1.len + s2.len; // Fallback: max distance

    // Initialize first row: distance from empty string
    for (0..s1.len + 1) |i| {
        prev_row[i] = i;
    }

    // Fill in the matrix row by row
    for (s2, 0..) |c2, j| {
        curr_row[0] = j + 1;
        for (s1, 0..) |c1, i| {
            const cost: usize = if (c1 == c2) 0 else 1;
            curr_row[i + 1] = @min(
                @min(curr_row[i] + 1, prev_row[i + 1] + 1),
                prev_row[i] + cost,
            );
        }
        @memcpy(prev_row[0 .. s1.len + 1], curr_row[0 .. s1.len + 1]);
    }

    return prev_row[s1.len];
}

/// Entry for a recipe match with its distance
const Match = struct {
    name: []const u8,
    distance: usize,
};

/// Find recipe names within a given distance threshold.
/// Checks both recipe names and aliases.
/// Returns slice of matching names sorted by distance (caller must free).
pub fn findSimilarRecipes(
    allocator: std.mem.Allocator,
    target: []const u8,
    recipes: []const Recipe,
    max_distance: usize,
) ![]const []const u8 {
    var matches: std.ArrayListUnmanaged(Match) = .{};
    defer matches.deinit(allocator);

    for (recipes) |*recipe| {
        // Skip private recipes
        if (recipe.name.len > 0 and recipe.name[0] == '_') continue;

        // Check main recipe name
        const dist = levenshteinDistance(target, recipe.name);
        if (dist <= max_distance and dist > 0) { // dist > 0 to skip exact matches
            try matches.append(allocator, .{ .name = recipe.name, .distance = dist });
        }

        // Check aliases
        for (recipe.aliases) |alias| {
            const alias_dist = levenshteinDistance(target, alias);
            if (alias_dist <= max_distance and alias_dist > 0) {
                try matches.append(allocator, .{ .name = alias, .distance = alias_dist });
            }
        }
    }

    // Sort by distance (closest first)
    std.mem.sort(Match, matches.items, {}, struct {
        fn lessThan(_: void, a: Match, b: Match) bool {
            return a.distance < b.distance;
        }
    }.lessThan);

    // Extract just the names
    var result = try allocator.alloc([]const u8, matches.items.len);
    for (matches.items, 0..) |match, i| {
        result[i] = match.name;
    }

    return result;
}

/// Format a suggestion message for display.
/// Returns a slice into the provided buffer.
pub fn formatSuggestion(buf: []u8, suggestions: []const []const u8) []const u8 {
    if (suggestions.len == 0) return "";

    var fbs = std.io.fixedBufferStream(buf);
    const writer = fbs.writer();

    writer.writeAll("Did you mean: ") catch return "";
    for (suggestions, 0..) |name, i| {
        if (i > 0) writer.writeAll(", ") catch return fbs.getWritten();
        if (i >= 3) {
            writer.writeAll("...") catch return fbs.getWritten();
            break;
        }
        writer.writeAll(name) catch return fbs.getWritten();
    }
    writer.writeAll("?\n") catch return fbs.getWritten();

    return fbs.getWritten();
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "levenshteinDistance identical strings" {
    try testing.expectEqual(@as(usize, 0), levenshteinDistance("build", "build"));
    try testing.expectEqual(@as(usize, 0), levenshteinDistance("", ""));
    try testing.expectEqual(@as(usize, 0), levenshteinDistance("test", "test"));
}

test "levenshteinDistance empty strings" {
    try testing.expectEqual(@as(usize, 5), levenshteinDistance("", "build"));
    try testing.expectEqual(@as(usize, 5), levenshteinDistance("build", ""));
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("", "a"));
}

test "levenshteinDistance single char difference" {
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("build", "bild")); // missing 'u'
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("test", "tast")); // 'e' -> 'a'
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("hello", "hallo")); // 'e' -> 'a'
}

test "levenshteinDistance insertions" {
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("build", "builds")); // add 's'
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("test", "atest")); // add 'a' at start
}

test "levenshteinDistance deletions" {
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("builds", "build")); // remove 's'
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("testing", "testin")); // remove 'g'
}

test "levenshteinDistance transpositions" {
    try testing.expectEqual(@as(usize, 2), levenshteinDistance("biuld", "build")); // 'iu' -> 'ui'
    try testing.expectEqual(@as(usize, 2), levenshteinDistance("tset", "test")); // 'se' -> 'es'
}

test "levenshteinDistance common typos" {
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("buld", "build")); // missing 'i'
    try testing.expectEqual(@as(usize, 2), levenshteinDistance("delpoy", "deploy")); // transposition: lp -> pl
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("dploy", "deploy")); // missing 'e'
}

test "levenshteinDistance completely different" {
    try testing.expectEqual(@as(usize, 3), levenshteinDistance("abc", "xyz"));
    try testing.expectEqual(@as(usize, 4), levenshteinDistance("test", "prod"));
}

test "levenshteinDistance case sensitive" {
    try testing.expectEqual(@as(usize, 1), levenshteinDistance("Build", "build"));
    try testing.expectEqual(@as(usize, 5), levenshteinDistance("BUILD", "build"));
}

test "formatSuggestion single match" {
    var buf: [256]u8 = undefined;
    const suggestions = [_][]const u8{"build"};
    const result = formatSuggestion(&buf, &suggestions);
    try testing.expectEqualStrings("Did you mean: build?\n", result);
}

test "formatSuggestion multiple matches" {
    var buf: [256]u8 = undefined;
    const suggestions = [_][]const u8{ "build", "built" };
    const result = formatSuggestion(&buf, &suggestions);
    try testing.expectEqualStrings("Did you mean: build, built?\n", result);
}

test "formatSuggestion empty" {
    var buf: [256]u8 = undefined;
    const suggestions = [_][]const u8{};
    const result = formatSuggestion(&buf, &suggestions);
    try testing.expectEqualStrings("", result);
}

test "formatSuggestion truncates at 3" {
    var buf: [256]u8 = undefined;
    const suggestions = [_][]const u8{ "a", "b", "c", "d", "e" };
    const result = formatSuggestion(&buf, &suggestions);
    try testing.expectEqualStrings("Did you mean: a, b, c, ...?\n", result);
}
