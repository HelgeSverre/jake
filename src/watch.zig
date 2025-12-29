// Jake Watch - File watching for automatic recipe re-execution
//
// Uses polling-based watching since Zig doesn't have built-in inotify/FSEvents wrappers.
// Polls every 500ms for changes, with 100ms debounce after last change.

const std = @import("std");
const compat = @import("compat.zig");
const parser = @import("parser.zig");
const executor_mod = @import("executor.zig");
const glob_mod = @import("glob.zig");

const Jakefile = parser.Jakefile;
const Executor = executor_mod.Executor;

pub const WatchError = error{
    InvalidPattern,
    OutOfMemory,
    AccessDenied,
    FileNotFound,
    SystemResources,
    Unexpected,
};

/// File watcher that monitors files/directories for changes and triggers recipe re-execution
pub const Watcher = struct {
    allocator: std.mem.Allocator,
    jakefile: *const Jakefile,
    watch_patterns: std.ArrayListUnmanaged([]const u8),
    file_mtimes: std.StringHashMapUnmanaged(i128),
    resolved_files: std.ArrayListUnmanaged([]const u8),
    poll_interval_ns: u64,
    debounce_ns: u64,
    verbose: bool,
    dry_run: bool,
    last_change_time: i128,

    const POLL_INTERVAL_MS: u64 = 500;
    const DEBOUNCE_MS: u64 = 100;

    pub fn init(allocator: std.mem.Allocator, jakefile: *const Jakefile) Watcher {
        return .{
            .allocator = allocator,
            .jakefile = jakefile,
            .watch_patterns = .empty,
            .file_mtimes = .empty,
            .resolved_files = .empty,
            .poll_interval_ns = POLL_INTERVAL_MS * std.time.ns_per_ms,
            .debounce_ns = DEBOUNCE_MS * std.time.ns_per_ms,
            .verbose = false,
            .dry_run = false,
            .last_change_time = 0,
        };
    }

    pub fn deinit(self: *Watcher) void {
        for (self.watch_patterns.items) |pattern| {
            self.allocator.free(pattern);
        }
        self.watch_patterns.deinit(self.allocator);

        var mtime_iter = self.file_mtimes.keyIterator();
        while (mtime_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.file_mtimes.deinit(self.allocator);

        for (self.resolved_files.items) |file| {
            self.allocator.free(file);
        }
        self.resolved_files.deinit(self.allocator);
    }

    /// Add a glob pattern or file path to watch
    pub fn addPattern(self: *Watcher, pattern: []const u8) !void {
        const duped = try self.allocator.dupe(u8, pattern);
        try self.watch_patterns.append(self.allocator, duped);
    }

    /// Add patterns from a recipe's file dependencies
    pub fn addRecipeDeps(self: *Watcher, recipe_name: []const u8) !void {
        const recipe = self.jakefile.getRecipe(recipe_name) orelse return;

        // Add file dependencies from the recipe
        for (recipe.file_deps) |dep| {
            try self.addPattern(dep);
        }

        // Add @watch patterns from recipe commands
        try self.addRecipeWatchPatterns(recipe);

        // Also recursively add deps from dependency recipes
        for (recipe.dependencies) |dep_name| {
            try self.addRecipeDeps(dep_name);
        }
    }

    /// Add patterns from @watch directives in recipe commands
    fn addRecipeWatchPatterns(self: *Watcher, recipe: *const parser.Recipe) !void {
        for (recipe.commands) |cmd| {
            if (cmd.directive) |directive| {
                if (directive == .watch) {
                    // Parse patterns from the @watch line
                    const patterns = self.parseWatchPatterns(cmd.line);
                    for (patterns) |pattern| {
                        try self.addPattern(pattern);
                    }
                }
            }
        }
    }

    /// Parse patterns from @watch directive line (e.g., "watch src/*.zig test/*.zig")
    fn parseWatchPatterns(self: *Watcher, line: []const u8) []const []const u8 {
        _ = self;
        var trimmed = std.mem.trim(u8, line, " \t");

        // Skip the "watch" keyword
        if (std.mem.startsWith(u8, trimmed, "watch")) {
            trimmed = std.mem.trimLeft(u8, trimmed[5..], " \t");
        }

        if (trimmed.len == 0) {
            return &.{};
        }

        // For simplicity, just split on spaces and return the first pattern
        // This is a simplified version - full implementation would handle multiple patterns
        var patterns: [16][]const u8 = undefined;
        var count: usize = 0;

        var i: usize = 0;
        while (i < trimmed.len and count < 16) {
            // Skip separators
            while (i < trimmed.len and (trimmed[i] == ' ' or trimmed[i] == ',' or trimmed[i] == '\t')) {
                i += 1;
            }
            if (i >= trimmed.len) break;

            // Find end of pattern
            const start = i;
            while (i < trimmed.len and trimmed[i] != ' ' and trimmed[i] != ',' and trimmed[i] != '\t') {
                i += 1;
            }

            if (i > start) {
                patterns[count] = trimmed[start..i];
                count += 1;
            }
        }

        // Return slice pointing to stack array - caller must use immediately
        return patterns[0..count];
    }

    /// Resolve all glob patterns to actual file paths and store their mtimes
    pub fn resolvePatterns(self: *Watcher) !void {
        // Clear previous resolved files
        for (self.resolved_files.items) |file| {
            self.allocator.free(file);
        }
        self.resolved_files.clearRetainingCapacity();

        var mtime_iter = self.file_mtimes.keyIterator();
        while (mtime_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.file_mtimes.clearRetainingCapacity();

        for (self.watch_patterns.items) |pattern| {
            try self.resolvePattern(pattern);
        }

        // Store initial mtimes
        for (self.resolved_files.items) |file_path| {
            const mtime = self.getFileMtime(file_path) catch continue;
            const key = try self.allocator.dupe(u8, file_path);
            try self.file_mtimes.put(self.allocator, key, mtime);
        }
    }

    /// Resolve a single glob pattern to file paths
    fn resolvePattern(self: *Watcher, pattern: []const u8) !void {
        // Check if pattern contains glob characters
        if (glob_mod.isGlobPattern(pattern)) {
            // Use the glob module to expand the pattern
            const files = try glob_mod.expandGlob(self.allocator, pattern);
            defer self.allocator.free(files);

            for (files) |file_path| {
                try self.resolved_files.append(self.allocator, file_path);
            }
        } else {
            // Direct file path - check if it exists
            std.fs.cwd().access(pattern, .{}) catch {
                // File doesn't exist, skip
                if (self.verbose) {
                    self.print("warning: file not found: {s}\n", .{pattern});
                }
                return;
            };
            const duped = try self.allocator.dupe(u8, pattern);
            try self.resolved_files.append(self.allocator, duped);
        }
    }

    /// Get file modification time
    fn getFileMtime(self: *Watcher, path: []const u8) !i128 {
        _ = self;
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const stat = try file.stat();
        return stat.mtime;
    }

    /// Check if any watched file has changed
    pub fn checkForChanges(self: *Watcher) !?[]const u8 {
        for (self.resolved_files.items) |file_path| {
            const current_mtime = self.getFileMtime(file_path) catch continue;

            if (self.file_mtimes.get(file_path)) |cached_mtime| {
                if (current_mtime != cached_mtime) {
                    // File changed, update cached mtime
                    if (self.file_mtimes.getEntry(file_path)) |entry| {
                        entry.value_ptr.* = current_mtime;
                    }
                    return file_path;
                }
            } else {
                // New file, add to cache
                const key = try self.allocator.dupe(u8, file_path);
                try self.file_mtimes.put(self.allocator, key, current_mtime);
                return file_path;
            }
        }

        // Also check for new files matching patterns
        try self.checkForNewFiles();

        return null;
    }

    /// Check if new files matching patterns have appeared
    fn checkForNewFiles(self: *Watcher) !void {
        const prev_count = self.resolved_files.items.len;

        // Re-resolve patterns to find new files
        for (self.watch_patterns.items) |pattern| {
            if (std.mem.indexOfAny(u8, pattern, "*?[") != null) {
                try self.resolvePattern(pattern);
            }
        }

        // Deduplicate resolved files
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        defer seen.deinit(self.allocator);

        var i: usize = 0;
        while (i < self.resolved_files.items.len) {
            const file = self.resolved_files.items[i];
            if (seen.contains(file)) {
                // Duplicate, remove
                self.allocator.free(file);
                _ = self.resolved_files.swapRemove(i);
            } else {
                try seen.put(self.allocator, file, {});
                i += 1;
            }
        }

        // Add mtimes for new files
        if (self.resolved_files.items.len > prev_count) {
            for (self.resolved_files.items[prev_count..]) |file_path| {
                if (!self.file_mtimes.contains(file_path)) {
                    const mtime = self.getFileMtime(file_path) catch continue;
                    const key = try self.allocator.dupe(u8, file_path);
                    try self.file_mtimes.put(self.allocator, key, mtime);
                }
            }
        }
    }

    /// Main watch loop - watch for changes and re-execute recipe
    pub fn watch(self: *Watcher, recipe_name: []const u8) !void {
        // Resolve initial patterns
        try self.resolvePatterns();

        self.print("\x1b[1;34m[watch]\x1b[0m Watching {d} file(s) for changes...\n", .{self.resolved_files.items.len});

        if (self.verbose) {
            for (self.resolved_files.items) |file| {
                self.print("  - {s}\n", .{file});
            }
        }

        self.print("\x1b[1;34m[watch]\x1b[0m Press Ctrl+C to stop\n", .{});
        self.print("\n", .{});

        // Initial execution
        self.executeRecipe(recipe_name);

        // Watch loop
        var pending_change: bool = false;
        var change_detected_time: i128 = 0;

        while (true) {
            std.Thread.sleep(self.poll_interval_ns);

            // Check for changes
            if (try self.checkForChanges()) |changed_file| {
                if (!pending_change) {
                    self.print("\x1b[1;33m[watch]\x1b[0m Change detected: {s}\n", .{changed_file});
                    pending_change = true;
                    change_detected_time = std.time.nanoTimestamp();
                } else {
                    // Update debounce timer
                    change_detected_time = std.time.nanoTimestamp();
                }
            }

            // Check if debounce period has passed
            if (pending_change) {
                const now = std.time.nanoTimestamp();
                const elapsed: u64 = @intCast(now - change_detected_time);
                if (elapsed >= self.debounce_ns) {
                    pending_change = false;
                    self.print("\n", .{});
                    self.executeRecipe(recipe_name);
                }
            }
        }
    }

    /// Execute the recipe (handles errors gracefully for watch mode)
    fn executeRecipe(self: *Watcher, recipe_name: []const u8) void {
        self.print("\x1b[1;34m[watch]\x1b[0m Running '{s}'...\n", .{recipe_name});
        self.print("\n", .{});

        var exec = Executor.init(self.allocator, self.jakefile);
        defer exec.deinit();
        exec.dry_run = self.dry_run;
        exec.verbose = self.verbose;

        exec.execute(recipe_name) catch |err| {
            const err_name = @errorName(err);
            self.print("\x1b[1;31m[watch]\x1b[0m Recipe failed: {s}\n", .{err_name});
            self.print("\x1b[1;34m[watch]\x1b[0m Waiting for changes...\n", .{});
            return;
        };

        self.print("\n\x1b[1;32m[watch]\x1b[0m Recipe completed successfully\n", .{});
        self.print("\x1b[1;34m[watch]\x1b[0m Waiting for changes...\n", .{});
    }

    fn print(self: *Watcher, comptime fmt: []const u8, args: anytype) void {
        _ = self;
        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        compat.getStdErr().writeAll(msg) catch {};
    }
};

test "watcher init" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    const jakefile = try p.parseJakefile();

    var watcher = Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addPattern("src/*.zig");
    try std.testing.expectEqual(@as(usize, 1), watcher.watch_patterns.items.len);
}

test "watcher add multiple patterns" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    const jakefile = try p.parseJakefile();

    var watcher = Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addPattern("src/*.zig");
    try watcher.addPattern("test/*.zig");
    try watcher.addPattern("build.zig");
    try std.testing.expectEqual(@as(usize, 3), watcher.watch_patterns.items.len);
}

test "watcher add recipe deps" {
    const allocator = std.testing.allocator;

    const source =
        \\file dist/bundle.js: src/*.js
        \\    cat src/*.js > dist/bundle.js
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    const jakefile = try p.parseJakefile();

    var watcher = Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addRecipeDeps("dist/bundle.js");
    // Should have added the file dep pattern
    try std.testing.expectEqual(@as(usize, 1), watcher.watch_patterns.items.len);
    try std.testing.expectEqualStrings("src/*.js", watcher.watch_patterns.items[0]);
}

test "watcher settings" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    const jakefile = try p.parseJakefile();

    var watcher = Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    // Default settings
    try std.testing.expect(!watcher.verbose);
    try std.testing.expect(!watcher.dry_run);

    // Change settings
    watcher.verbose = true;
    watcher.dry_run = true;
    try std.testing.expect(watcher.verbose);
    try std.testing.expect(watcher.dry_run);
}

test "watcher deinit cleans up patterns" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    const jakefile = try p.parseJakefile();

    var watcher = Watcher.init(allocator, &jakefile);

    // Add patterns
    try watcher.addPattern("src/*.zig");
    try watcher.addPattern("test/*.zig");

    // deinit should clean up all allocated patterns without leaks
    watcher.deinit();
    // No assertion needed - test.allocator will catch leaks
}

test "watcher poll interval defaults" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    const jakefile = try p.parseJakefile();

    var watcher = Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    // Check default poll interval (500ms in nanoseconds)
    try std.testing.expectEqual(@as(u64, 500 * std.time.ns_per_ms), watcher.poll_interval_ns);
    // Check default debounce (100ms in nanoseconds)
    try std.testing.expectEqual(@as(u64, 100 * std.time.ns_per_ms), watcher.debounce_ns);
}

test "watcher extracts @watch patterns from recipe" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    @watch src/*.zig
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    const jakefile = try p.parseJakefile();

    var watcher = Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addRecipeDeps("build");

    // Should have extracted the @watch pattern
    try std.testing.expectEqual(@as(usize, 1), watcher.watch_patterns.items.len);
    try std.testing.expectEqualStrings("src/*.zig", watcher.watch_patterns.items[0]);
}

test "watcher extracts multiple @watch patterns" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    @watch src/*.zig test/*.zig
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    const jakefile = try p.parseJakefile();

    var watcher = Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addRecipeDeps("build");

    // Should have extracted both @watch patterns
    try std.testing.expectEqual(@as(usize, 2), watcher.watch_patterns.items.len);
    try std.testing.expectEqualStrings("src/*.zig", watcher.watch_patterns.items[0]);
    try std.testing.expectEqualStrings("test/*.zig", watcher.watch_patterns.items[1]);
}
