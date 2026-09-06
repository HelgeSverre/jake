//! File watcher using FSEvents (macOS) or inotify (Linux).
//!
//! Uses polling-based watching since Zig doesn't have built-in inotify/FSEvents wrappers.
// Polls every 500ms for changes, with 100ms debounce after last change.

const std = @import("std");
const compat = @import("../compat.zig");
const parser = @import("../frontend/parser.zig");
const executor_mod = @import("executor.zig");
const JakefileIndex = @import("../frontend/jakefile_index.zig").JakefileIndex;
const jakefile_loader = @import("../frontend/jakefile_loader.zig");
const glob_mod = @import("../util/glob.zig");
const color_mod = @import("../output/color.zig");
const context_mod = @import("context.zig");
const RuntimeContext = context_mod.RuntimeContext;
const Context = context_mod.Context;

const Jakefile = parser.Jakefile;
const Executor = executor_mod.Executor;
const LoadedJakefile = jakefile_loader.LoadedJakefile;

/// Default CLI context used by init() and initWithIndex() for backwards compatibility.
var default_context: Context = .{
    .color = color_mod.Color{ .enabled = false },
};

/// File watcher that monitors files/directories for changes and triggers recipe re-execution
pub const Watcher = struct {
    allocator: std.mem.Allocator,
    jakefile: *const Jakefile,
    index: *const JakefileIndex,
    owned_index: ?*JakefileIndex = null,
    watch_patterns: std.ArrayListUnmanaged([]const u8),
    file_mtimes: std.StringHashMapUnmanaged(i128),
    resolved_files: std.ArrayListUnmanaged([]const u8),
    poll_interval_ns: u64,
    debounce_ns: u64,
    last_change_time: i128,
    color: color_mod.Color,
    theme: color_mod.Theme,

    // CLI context (flags from user)
    ctx: *Context,
    runtime: ?*RuntimeContext,
    loaded_jakefile: ?*LoadedJakefile,
    requested_jakefile_path: ?[]const u8,
    auto_watch_patterns: bool,

    const POLL_INTERVAL_MS: u64 = 500;
    const DEBOUNCE_MS: u64 = 100;
    const MISSING_MTIME = std.math.minInt(i128);

    pub fn init(allocator: std.mem.Allocator, jakefile: *const Jakefile) !Watcher {
        const owned_index = try allocator.create(JakefileIndex);
        owned_index.* = JakefileIndex.build(allocator, jakefile) catch |err| {
            allocator.destroy(owned_index);
            return err;
        };
        var watcher = initInternal(allocator, jakefile, owned_index);
        watcher.owned_index = owned_index;
        watcher.index = owned_index;
        return watcher;
    }

    pub fn initWithIndex(allocator: std.mem.Allocator, jakefile: *const Jakefile, index: *const JakefileIndex) Watcher {
        return initInternal(allocator, jakefile, index);
    }

    /// Initialize with a pre-configured RuntimeContext (shares color, theme) and CLI Context.
    /// This is the preferred initialization method.
    pub fn initWithIndexAndContext(allocator: std.mem.Allocator, jakefile: *const Jakefile, index: *const JakefileIndex, ctx: *Context, runtime: *RuntimeContext) Watcher {
        return .{
            .allocator = allocator,
            .jakefile = jakefile,
            .index = index,
            .watch_patterns = .empty,
            .file_mtimes = .empty,
            .resolved_files = .empty,
            .poll_interval_ns = POLL_INTERVAL_MS * std.time.ns_per_ms,
            .debounce_ns = DEBOUNCE_MS * std.time.ns_per_ms,
            .last_change_time = 0,
            .color = runtime.color,
            .theme = runtime.theme,
            .ctx = ctx,
            .runtime = runtime,
            .loaded_jakefile = null,
            .requested_jakefile_path = null,
            .auto_watch_patterns = false,
        };
    }

    fn initInternal(allocator: std.mem.Allocator, jakefile: *const Jakefile, index: *const JakefileIndex) Watcher {
        // Reset default context to initial state (important for tests that reuse this)
        default_context = .{
            .color = color_mod.Color{ .enabled = false },
        };

        return .{
            .allocator = allocator,
            .jakefile = jakefile,
            .index = index,
            .watch_patterns = .empty,
            .file_mtimes = .empty,
            .resolved_files = .empty,
            .poll_interval_ns = POLL_INTERVAL_MS * std.time.ns_per_ms,
            .debounce_ns = DEBOUNCE_MS * std.time.ns_per_ms,
            .last_change_time = 0,
            .color = color_mod.init(),
            .theme = color_mod.Theme.init(),
            .ctx = &default_context,
            .runtime = null,
            .loaded_jakefile = null,
            .requested_jakefile_path = null,
            .auto_watch_patterns = false,
        };
    }

    pub fn initWithLoadedJakefile(allocator: std.mem.Allocator, requested_jakefile_path: []const u8, loaded_jakefile: LoadedJakefile, ctx: *Context) !Watcher {
        const requested_path = try allocator.dupe(u8, requested_jakefile_path);
        errdefer allocator.free(requested_path);

        const owned_loaded = try allocator.create(LoadedJakefile);
        errdefer allocator.destroy(owned_loaded);
        owned_loaded.* = loaded_jakefile;

        var watcher = Watcher{
            .allocator = allocator,
            .jakefile = undefined,
            .index = undefined,
            .owned_index = null,
            .watch_patterns = .empty,
            .file_mtimes = .empty,
            .resolved_files = .empty,
            .poll_interval_ns = POLL_INTERVAL_MS * std.time.ns_per_ms,
            .debounce_ns = DEBOUNCE_MS * std.time.ns_per_ms,
            .last_change_time = 0,
            .color = loaded_jakefile.runtime.color,
            .theme = loaded_jakefile.runtime.theme,
            .ctx = ctx,
            .runtime = null,
            .loaded_jakefile = owned_loaded,
            .requested_jakefile_path = requested_path,
            .auto_watch_patterns = false,
        };
        watcher.refreshLoadedState();
        return watcher;
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

        if (self.owned_index) |owned| {
            owned.deinit();
            self.allocator.destroy(owned);
            self.owned_index = null;
        }

        if (self.requested_jakefile_path) |path| {
            self.allocator.free(path);
            self.requested_jakefile_path = null;
        }

        if (self.loaded_jakefile) |loaded| {
            loaded.deinit();
            self.allocator.destroy(loaded);
            self.loaded_jakefile = null;
        }
    }

    /// Add a glob pattern or file path to watch
    pub fn addPattern(self: *Watcher, pattern: []const u8) !void {
        for (self.watch_patterns.items) |existing| {
            if (std.mem.eql(u8, existing, pattern)) {
                return;
            }
        }
        const duped = try self.allocator.dupe(u8, pattern);
        errdefer self.allocator.free(duped);
        try self.watch_patterns.append(self.allocator, duped);
    }

    pub fn configureAutomaticPatterns(self: *Watcher, recipe_name: []const u8) !void {
        self.refreshLoadedState();
        self.auto_watch_patterns = true;
        try self.rebuildAutomaticPatterns(recipe_name);
    }

    /// Add patterns from a recipe's file dependencies
    pub fn addRecipeDeps(self: *Watcher, recipe_name: []const u8) !void {
        self.refreshLoadedState();
        var visited: std.StringHashMapUnmanaged(void) = .empty;
        defer visited.deinit(self.allocator);
        try self.addRecipeDepsVisited(recipe_name, &visited);
    }

    fn addRecipeDepsVisited(self: *Watcher, recipe_name: []const u8, visited: *std.StringHashMapUnmanaged(void)) !void {
        if (visited.contains(recipe_name)) {
            return;
        }
        try visited.put(self.allocator, recipe_name, {});

        const recipe = self.index.getRecipe(recipe_name) orelse return;

        // Add file dependencies from the recipe
        for (recipe.file_deps) |dep| {
            try self.addPattern(dep);
        }

        // Add @watch patterns from recipe commands
        try self.addRecipeWatchPatterns(recipe);

        // Also recursively add deps from dependency recipes
        for (recipe.dependencies) |dep_name| {
            try self.addRecipeDepsVisited(dep_name, visited);
        }
    }

    /// Add patterns from @watch directives in recipe commands
    fn addRecipeWatchPatterns(self: *Watcher, recipe: *const parser.Recipe) !void {
        for (recipe.commands) |cmd| {
            if (cmd.directive) |directive| {
                if (directive == .watch) {
                    // Parse patterns from the @watch line directly into watch_patterns
                    try self.parseAndAddWatchPatterns(cmd.line);
                }
            }
        }
    }

    /// Parse patterns from @watch directive line and add them directly
    fn parseAndAddWatchPatterns(self: *Watcher, line: []const u8) !void {
        var trimmed = std.mem.trim(u8, line, " \t");

        // Skip the "watch" keyword
        if (std.mem.startsWith(u8, trimmed, "watch")) {
            trimmed = std.mem.trimLeft(u8, trimmed[5..], " \t");
        }

        if (trimmed.len == 0) {
            return;
        }

        // Parse and add patterns one by one
        var i: usize = 0;
        while (i < trimmed.len) {
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
                try self.addPattern(trimmed[start..i]);
            }
        }
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
            if (std.fs.path.isAbsolute(pattern)) {
                std.fs.accessAbsolute(pattern, .{}) catch {
                    if (self.ctx.verbose) {
                        self.print("warning: file not found: {s}\n", .{pattern});
                    }
                    return;
                };
            } else {
                std.fs.cwd().access(pattern, .{}) catch {
                    // File doesn't exist, skip
                    if (self.ctx.verbose) {
                        self.print("warning: file not found: {s}\n", .{pattern});
                    }
                    return;
                };
            }
            const duped = try self.allocator.dupe(u8, pattern);
            try self.resolved_files.append(self.allocator, duped);
        }
    }

    /// Get file modification time
    fn getFileMtime(self: *Watcher, path: []const u8) !i128 {
        _ = self;
        const file = if (std.fs.path.isAbsolute(path))
            try std.fs.openFileAbsolute(path, .{})
        else
            try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const stat = try file.stat();
        return stat.mtime;
    }

    /// Check if any watched file has changed
    pub fn checkForChanges(self: *Watcher) !?[]const u8 {
        for (self.resolved_files.items) |file_path| {
            const current_mtime = self.getFileMtime(file_path) catch |err| {
                if (err == error.FileNotFound) {
                    if (self.file_mtimes.getEntry(file_path)) |entry| {
                        if (entry.value_ptr.* != MISSING_MTIME) {
                            entry.value_ptr.* = MISSING_MTIME;
                            return file_path;
                        }
                    }
                }
                continue;
            };

            if (self.file_mtimes.getEntry(file_path)) |entry| {
                if (entry.value_ptr.* == MISSING_MTIME or current_mtime != entry.value_ptr.*) {
                    entry.value_ptr.* = current_mtime;
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
        self.refreshLoadedState();

        // Resolve initial patterns
        try self.resolvePatterns();

        // v4 format: ◉ watching <pattern> with ◉ in info blue, pattern in muted
        self.print("   {s} ", .{self.theme.watchingSymbol()});
        self.print("{s}watching{s} ", .{ self.color.bold(), self.color.reset() });
        if (self.watch_patterns.items.len > 0) {
            self.print("{s}", .{self.color.muted()});
            for (self.watch_patterns.items, 0..) |pattern, i| {
                if (i > 0) self.print(", ", .{});
                self.print("{s}", .{pattern});
            }
            self.print("{s}", .{self.color.reset()});
        } else {
            self.print("{s}{d} file(s){s}", .{ self.color.muted(), self.resolved_files.items.len, self.color.reset() });
        }
        self.print("\n", .{});

        if (self.ctx.verbose) {
            for (self.resolved_files.items) |file| {
                self.print("  - {s}\n", .{file});
            }
        }

        self.print("\n", .{});

        // Initial execution
        self.executeRecipe(recipe_name);

        // Watch loop
        var pending_change: bool = false;
        var pending_reload: bool = false;
        var change_detected_time: i128 = 0;

        while (true) {
            std.Thread.sleep(self.poll_interval_ns);

            // Check for changes
            if (try self.checkForChanges()) |changed_file| {
                if (!pending_change) {
                    // v4 format: ⟳ changed <file> with ⟳ in warning yellow, file in muted
                    self.print("   {s} {s}changed{s} {s}{s}{s}\n", .{
                        self.theme.changedSymbol(),
                        self.color.muted(),
                        self.color.reset(),
                        self.color.muted(),
                        changed_file,
                        self.color.reset(),
                    });
                    pending_change = true;
                    change_detected_time = std.time.nanoTimestamp();
                } else {
                    // Update debounce timer
                    change_detected_time = std.time.nanoTimestamp();
                }

                if (self.shouldReloadForChange(changed_file)) {
                    pending_reload = true;
                }
            }

            // Check if debounce period has passed
            if (pending_change) {
                const now = std.time.nanoTimestamp();
                const elapsed: u64 = @intCast(now - change_detected_time);
                if (elapsed >= self.debounce_ns) {
                    pending_change = false;
                    self.print("\n", .{});

                    if (pending_reload) {
                        self.reloadConfiguration(recipe_name) catch |err| {
                            const err_name = @errorName(err);
                            self.print("\n   {s}Failed to reload Jakefile: {s}{s}\n", .{ self.color.errorRed(), err_name, self.color.reset() });
                            self.printWatchFooter();
                            pending_reload = false;
                            continue;
                        };
                        pending_reload = false;
                    }

                    self.executeRecipe(recipe_name);
                }
            }
        }
    }

    /// Execute the recipe (handles errors gracefully for watch mode)
    fn executeRecipe(self: *Watcher, recipe_name: []const u8) void {
        self.refreshLoadedState();

        var exec = self.initExecutor() catch |err| {
            const err_name = @errorName(err);
            self.print("\n   {s}Failed to initialize executor: {s}{s}\n", .{ self.color.errorRed(), err_name, self.color.reset() });
            self.printWatchFooter();
            return;
        };
        defer exec.deinit();

        exec.validateRequiredEnv() catch |err| {
            if (err != error.MissingRequiredEnv) {
                const err_name = @errorName(err);
                self.print("\n   {s}Failed to validate environment: {s}{s}\n", .{ self.color.errorRed(), err_name, self.color.reset() });
            }
            self.printWatchFooter();
            return;
        };

        exec.execute(recipe_name) catch |err| {
            const err_name = @errorName(err);
            self.print("\n   {s}Recipe failed: {s}{s}\n", .{ self.color.errorRed(), err_name, self.color.reset() });
            self.printWatchFooter();
            return;
        };

        self.printWatchFooter();
    }

    /// Print the v4 watch mode footer
    fn printWatchFooter(self: *Watcher) void {
        self.print("\n   {s}watching for changes (ctrl+c to stop){s}\n", .{ self.color.muted(), self.color.reset() });
    }

    fn print(self: *Watcher, comptime fmt: []const u8, args: anytype) void {
        _ = self;
        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        compat.getStdErr().writeAll(msg) catch {};
    }

    fn refreshLoadedState(self: *Watcher) void {
        if (self.loaded_jakefile) |loaded| {
            self.jakefile = &loaded.jakefile;
            self.index = &loaded.index;
            self.runtime = &loaded.runtime;
            self.color = loaded.runtime.color;
            self.theme = loaded.runtime.theme;
        }
    }

    fn rebuildAutomaticPatterns(self: *Watcher, recipe_name: []const u8) !void {
        self.clearWatchPatterns();
        try self.addConfigurationWatchPatterns();
        try self.addRecipeDeps(recipe_name);
    }

    fn clearWatchPatterns(self: *Watcher) void {
        for (self.watch_patterns.items) |pattern| {
            self.allocator.free(pattern);
        }
        self.watch_patterns.clearRetainingCapacity();
    }

    fn addConfigurationWatchPatterns(self: *Watcher) !void {
        if (self.loaded_jakefile) |loaded| {
            for (loaded.watch_files) |watch_file| {
                try self.addPattern(watch_file);
            }
        }
    }

    fn shouldReloadForChange(self: *Watcher, changed_file: []const u8) bool {
        if (self.loaded_jakefile) |loaded| {
            for (loaded.watch_files) |watch_file| {
                if (std.mem.eql(u8, watch_file, changed_file)) {
                    return true;
                }
            }
        }
        return false;
    }

    fn reloadConfiguration(self: *Watcher, recipe_name: []const u8) !void {
        const requested_jakefile_path = self.requested_jakefile_path orelse return;

        var reloaded = try jakefile_loader.loadJakefile(self.allocator, requested_jakefile_path);
        var reloaded_owned = false;
        errdefer if (!reloaded_owned) reloaded.deinit();

        if (self.loaded_jakefile) |loaded| {
            loaded.deinit();
            loaded.* = reloaded;
        } else {
            const owned_loaded = try self.allocator.create(LoadedJakefile);
            errdefer self.allocator.destroy(owned_loaded);
            owned_loaded.* = reloaded;
            self.loaded_jakefile = owned_loaded;
        }
        reloaded_owned = true;
        self.refreshLoadedState();

        if (self.auto_watch_patterns) {
            try self.rebuildAutomaticPatterns(recipe_name);
        }
        try self.resolvePatterns();
    }

    fn initExecutor(self: *Watcher) !Executor {
        if (self.runtime) |runtime| {
            return try Executor.initWithIndexAndContext(self.allocator, self.jakefile, self.index, self.ctx, runtime);
        }

        var exec = try Executor.init(self.allocator, self.jakefile);
        exec.ctx.dry_run = self.ctx.dry_run;
        exec.ctx.verbose = self.ctx.verbose;
        exec.ctx.auto_yes = self.ctx.auto_yes;
        exec.ctx.watch_mode = true;
        exec.ctx.jobs = self.ctx.jobs;
        exec.ctx.color = self.ctx.color;
        exec.ctx.positional_args = self.ctx.positional_args;
        exec.ctx.cancellation_flag = self.ctx.cancellation_flag;
        exec.ctx.current_child_pid = self.ctx.current_child_pid;
        exec.ctx.output_callback = self.ctx.output_callback;
        exec.ctx.output_callback_ctx = self.ctx.output_callback_ctx;
        return exec;
    }
};

test "watcher init" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
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
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
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
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addRecipeDeps("dist/bundle.js");
    // Should have added the file dep pattern
    try std.testing.expectEqual(@as(usize, 1), watcher.watch_patterns.items.len);
    try std.testing.expectEqualStrings("src/*.js", watcher.watch_patterns.items[0]);
}

test "watcher add recipe deps handles cycles" {
    const allocator = std.testing.allocator;

    const source =
        \\task a: b
        \\    echo "a"
        \\
        \\task b: a dep
        \\    echo "b"
        \\
        \\file dep: src/*.txt
        \\    echo "dep"
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addRecipeDeps("a");
}

test "watcher settings" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    // Default settings (accessed via ctx)
    try std.testing.expect(!watcher.ctx.verbose);
    try std.testing.expect(!watcher.ctx.dry_run);

    // Change settings via ctx
    watcher.ctx.verbose = true;
    watcher.ctx.dry_run = true;
    try std.testing.expect(watcher.ctx.verbose);
    try std.testing.expect(watcher.ctx.dry_run);
}

test "watcher deinit cleans up patterns" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);

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
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
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
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
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
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addRecipeDeps("build");

    // Should have extracted both @watch patterns
    try std.testing.expectEqual(@as(usize, 2), watcher.watch_patterns.items.len);
    try std.testing.expectEqualStrings("src/*.zig", watcher.watch_patterns.items[0]);
    try std.testing.expectEqualStrings("test/*.zig", watcher.watch_patterns.items[1]);
}

test "watcher handles non-existent recipe gracefully" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    // Try to add deps for a non-existent recipe - should not crash
    watcher.addRecipeDeps("nonexistent") catch {};

    // No patterns should have been added
    try std.testing.expectEqual(@as(usize, 0), watcher.watch_patterns.items.len);
}

test "watcher handles empty @watch pattern" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    @watch
        \\    echo "building"
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addRecipeDeps("build");

    // Empty @watch should not add any patterns
    try std.testing.expectEqual(@as(usize, 0), watcher.watch_patterns.items.len);
}

test "watcher handles recipe with no commands" {
    const allocator = std.testing.allocator;

    const source =
        \\task empty:
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addRecipeDeps("empty");

    // No patterns from empty recipe
    try std.testing.expectEqual(@as(usize, 0), watcher.watch_patterns.items.len);
}

test "watcher automatic patterns include imports and external build files" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makePath("lib/nested");
    try tmp_dir.dir.makePath("src");
    try tmp_dir.dir.writeFile(.{
        .sub_path = "Jakefile",
        .data =
        \\@import "lib/tasks.jake" as lib
        ,
    });
    try tmp_dir.dir.writeFile(.{
        .sub_path = "lib/tasks.jake",
        .data =
        \\@import "nested/util.jake" as nested
        ,
    });
    try tmp_dir.dir.writeFile(.{
        .sub_path = "lib/nested/util.jake",
        .data =
        \\file nested: src/*.zig
        \\    echo "nested"
        ,
    });
    try tmp_dir.dir.writeFile(.{
        .sub_path = "Makefile",
        .data =
        \\build:
        \\    echo "external"
        ,
    });

    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    const loaded = try jakefile_loader.loadJakefile(std.testing.allocator, "Jakefile");
    var ctx = Context.initWithColor(false);
    ctx.watch_mode = true;

    var watcher = try Watcher.initWithLoadedJakefile(std.testing.allocator, "Jakefile", loaded, &ctx);
    defer watcher.deinit();

    try std.testing.expect(watcher.index.getRecipe("lib.nested.nested") != null);

    try watcher.configureAutomaticPatterns("lib.nested.nested");

    try expectWatchPattern(&watcher, "Jakefile");
    try expectWatchPattern(&watcher, "lib/tasks.jake");
    try expectWatchPattern(&watcher, "lib/nested/util.jake");
    try expectWatchPattern(&watcher, "Makefile");
    try expectWatchPattern(&watcher, "src/*.zig");
}

test "watcher reloads automatic patterns after jakefile change" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makePath("src");
    try tmp_dir.dir.writeFile(.{
        .sub_path = "Jakefile",
        .data =
        \\file build: src/*.zig
        \\    echo "build"
        ,
    });

    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    const loaded = try jakefile_loader.loadJakefile(std.testing.allocator, "Jakefile");
    var ctx = Context.initWithColor(false);
    ctx.watch_mode = true;

    var watcher = try Watcher.initWithLoadedJakefile(std.testing.allocator, "Jakefile", loaded, &ctx);
    defer watcher.deinit();

    try watcher.configureAutomaticPatterns("build");
    try std.testing.expectEqualStrings("src/*.zig", watcher.watch_patterns.items[1]);

    for (0..16) |i| {
        const pattern = if (i % 2 == 0) "lib/*.zig" else "src/*.zig";
        const updated = try std.fmt.allocPrint(std.testing.allocator, "file build: {s}\n    echo build\n", .{pattern});
        defer std.testing.allocator.free(updated);
        try tmp_dir.dir.writeFile(.{ .sub_path = "Jakefile", .data = updated });
        try watcher.reloadConfiguration("build");
        try std.testing.expectEqual(@as(usize, 2), watcher.watch_patterns.items.len);
        try std.testing.expectEqualStrings("Jakefile", watcher.watch_patterns.items[0]);
        try std.testing.expectEqualStrings(pattern, watcher.watch_patterns.items[1]);
    }
}

test "watcher detects deleted files and reappearance once" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{
        .sub_path = "Jakefile",
        .data =
        \\task build:
        \\    echo "build"
        ,
    });
    try tmp_dir.dir.writeFile(.{
        .sub_path = "watched.txt",
        .data = "hello",
    });

    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    const source =
        \\task build:
        \\    echo "build"
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var watcher = try Watcher.init(std.testing.allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addPattern("watched.txt");
    try watcher.resolvePatterns();

    try tmp_dir.dir.deleteFile("watched.txt");

    const deleted = (try watcher.checkForChanges()) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("watched.txt", deleted);
    try std.testing.expect((try watcher.checkForChanges()) == null);

    try tmp_dir.dir.writeFile(.{
        .sub_path = "watched.txt",
        .data = "hello again",
    });

    const recreated = (try watcher.checkForChanges()) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("watched.txt", recreated);
}

fn expectWatchPattern(watcher: *Watcher, pattern: []const u8) !void {
    // Normalize separators so the test passes on Windows (where stored patterns
    // may use '\') as well as POSIX.
    var pattern_buf: [std.fs.max_path_bytes]u8 = undefined;
    const normalized_pattern = normalizeForCompare(&pattern_buf, pattern) orelse return error.TestExpectedEqual;
    for (watcher.watch_patterns.items) |existing| {
        var existing_buf: [std.fs.max_path_bytes]u8 = undefined;
        const normalized_existing = normalizeForCompare(&existing_buf, existing) orelse continue;
        if (std.mem.eql(u8, normalized_existing, normalized_pattern)) {
            return;
        }
    }

    return error.TestExpectedEqual;
}

fn normalizeForCompare(buf: []u8, path: []const u8) ?[]const u8 {
    if (path.len > buf.len) return null;
    @memcpy(buf[0..path.len], path);
    for (buf[0..path.len]) |*c| {
        if (c.* == '\\') c.* = '/';
    }
    return buf[0..path.len];
}

// --- Pattern feedback tests ---

test "pattern feedback - empty patterns list" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    // No patterns added - feedback should show nothing
    try std.testing.expectEqual(@as(usize, 0), watcher.watch_patterns.items.len);
}

test "pattern feedback - single pattern" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addPattern("src/**/*.zig");

    // Single pattern should be stored correctly
    try std.testing.expectEqual(@as(usize, 1), watcher.watch_patterns.items.len);
    try std.testing.expectEqualStrings("src/**/*.zig", watcher.watch_patterns.items[0]);
}

test "pattern feedback - multiple patterns comma-separated format" {
    const allocator = std.testing.allocator;

    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addPattern("src/**/*.zig");
    try watcher.addPattern("Jakefile");
    try watcher.addPattern("lib/*.jake");

    // Multiple patterns should be stored in order for comma-separated display
    try std.testing.expectEqual(@as(usize, 3), watcher.watch_patterns.items.len);
    try std.testing.expectEqualStrings("src/**/*.zig", watcher.watch_patterns.items[0]);
    try std.testing.expectEqualStrings("Jakefile", watcher.watch_patterns.items[1]);
    try std.testing.expectEqualStrings("lib/*.jake", watcher.watch_patterns.items[2]);
}

test "pattern feedback - patterns from file recipe deps" {
    const allocator = std.testing.allocator;

    const source =
        \\file dist/bundle.js: src/*.js lib/*.js
        \\    cat src/*.js lib/*.js > dist/bundle.js
    ;
    var lex = @import("../frontend/lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var watcher = try Watcher.init(allocator, &jakefile);
    defer watcher.deinit();

    try watcher.addRecipeDeps("dist/bundle.js");

    // Should have both file dependency patterns
    try std.testing.expectEqual(@as(usize, 2), watcher.watch_patterns.items.len);
    try std.testing.expectEqualStrings("src/*.js", watcher.watch_patterns.items[0]);
    try std.testing.expectEqualStrings("lib/*.js", watcher.watch_patterns.items[1]);
}
