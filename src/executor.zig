// Jake Executor - Runs recipes with dependency resolution

const std = @import("std");
const parser = @import("parser.zig");
const cache_mod = @import("cache.zig");

const Jakefile = parser.Jakefile;
const Recipe = parser.Recipe;
const Cache = cache_mod.Cache;

pub const ExecuteError = error{
    RecipeNotFound,
    CommandFailed,
    CyclicDependency,
    OutOfMemory,
    FileNotFound,
    AccessDenied,
    SystemResources,
    Unexpected,
};

pub const Executor = struct {
    allocator: std.mem.Allocator,
    jakefile: *const Jakefile,
    cache: Cache,
    executed: std.StringHashMap(void),
    in_progress: std.StringHashMap(void),
    variables: std.StringHashMap([]const u8),
    dry_run: bool,
    verbose: bool,

    pub fn init(allocator: std.mem.Allocator, jakefile: *const Jakefile) Executor {
        var variables = std.StringHashMap([]const u8).init(allocator);

        // Load variables from jakefile
        for (jakefile.variables) |v| {
            variables.put(v.name, v.value) catch {};
        }

        return .{
            .allocator = allocator,
            .jakefile = jakefile,
            .cache = Cache.init(allocator),
            .executed = std.StringHashMap(void).init(allocator),
            .in_progress = std.StringHashMap(void).init(allocator),
            .variables = variables,
            .dry_run = false,
            .verbose = false,
        };
    }

    pub fn deinit(self: *Executor) void {
        self.cache.deinit();
        self.executed.deinit();
        self.in_progress.deinit();
        self.variables.deinit();
    }

    /// Execute a recipe by name
    pub fn execute(self: *Executor, name: []const u8) ExecuteError!void {
        // Check for cycles
        if (self.in_progress.contains(name)) {
            return ExecuteError.CyclicDependency;
        }

        // Already executed?
        if (self.executed.contains(name)) {
            return;
        }

        const recipe = self.jakefile.getRecipe(name) orelse {
            return ExecuteError.RecipeNotFound;
        };

        // Mark as in progress
        self.in_progress.put(name, {}) catch return ExecuteError.OutOfMemory;
        defer _ = self.in_progress.remove(name);

        // Execute dependencies first
        for (recipe.dependencies) |dep| {
            try self.execute(dep);
        }

        // Check if we need to run (for file targets)
        if (recipe.kind == .file) {
            const needs_run = self.checkFileTarget(recipe) catch true;
            if (!needs_run) {
                if (self.verbose) {
                    self.print("jake: '{s}' is up to date\n", .{name});
                }
                self.executed.put(name, {}) catch {};
                return;
            }
        }

        // Run the recipe
        self.print("\x1b[1;36m→ {s}\x1b[0m\n", .{name});

        for (recipe.commands) |cmd| {
            try self.runCommand(cmd, recipe);
        }

        // Update cache for file targets
        if (recipe.kind == .file) {
            if (recipe.output) |output| {
                self.cache.update(output) catch {};
            }
        }

        self.executed.put(name, {}) catch {};
    }

    fn checkFileTarget(self: *Executor, recipe: *const Recipe) !bool {
        // Check if output exists
        const output = recipe.output orelse return true;

        std.fs.cwd().access(output, .{}) catch {
            return true; // Output doesn't exist, need to build
        };

        // Check if any file deps are stale
        for (recipe.file_deps) |dep| {
            if (try self.cache.isGlobStale(dep)) {
                return true;
            }
        }

        return false;
    }

    fn runCommand(self: *Executor, cmd: Recipe.Command, recipe: *const Recipe) ExecuteError!void {
        _ = recipe;

        const line = self.expandVariables(cmd.line) catch cmd.line;

        if (self.dry_run) {
            self.print("  [dry-run] {s}\n", .{line});
            return;
        }

        if (self.verbose) {
            self.print("  $ {s}\n", .{line});
        }

        // Execute via shell
        var child = std.process.Child.init(
            &[_][]const u8{ "/bin/sh", "-c", line },
            self.allocator,
        );
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;

        _ = child.spawn() catch |err| {
            self.print("\x1b[1;31merror:\x1b[0m failed to spawn: {s}\n", .{@errorName(err)});
            return ExecuteError.CommandFailed;
        };

        const result = child.wait() catch |err| {
            self.print("\x1b[1;31merror:\x1b[0m failed to wait: {s}\n", .{@errorName(err)});
            return ExecuteError.CommandFailed;
        };

        if (result.Exited != 0) {
            self.print("\x1b[1;31merror:\x1b[0m command exited with code {d}\n", .{result.Exited});
            return ExecuteError.CommandFailed;
        }
    }

    fn expandVariables(self: *Executor, line: []const u8) ![]const u8 {
        var result: std.ArrayListUnmanaged(u8) = .empty;
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < line.len) {
            // Check for {{var}} pattern
            if (i + 1 < line.len and line[i] == '{' and line[i + 1] == '{') {
                const start = i + 2;
                var end = start;
                while (end + 1 < line.len and !(line[end] == '}' and line[end + 1] == '}')) {
                    end += 1;
                }
                if (end + 1 < line.len) {
                    const var_name = line[start..end];
                    if (self.variables.get(var_name)) |value| {
                        try result.appendSlice(self.allocator, value);
                    } else {
                        // Keep original if not found
                        try result.appendSlice(self.allocator, line[i .. end + 2]);
                    }
                    i = end + 2;
                    continue;
                }
            }
            try result.append(self.allocator, line[i]);
            i += 1;
        }

        return result.toOwnedSlice(self.allocator);
    }

    fn print(self: *Executor, comptime fmt: []const u8, args: anytype) void {
        _ = self;
        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        std.fs.File.stderr().writeAll(msg) catch {};
    }

    /// List all available recipes
    pub fn listRecipes(self: *Executor) void {
        const stdout = std.fs.File.stdout();
        stdout.writeAll("\x1b[1mAvailable recipes:\x1b[0m\n") catch {};

        for (self.jakefile.recipes) |recipe| {
            const kind_str = switch (recipe.kind) {
                .task => "task",
                .file => "file",
                .simple => "",
            };
            const default_str: []const u8 = if (recipe.is_default) " (default)" else "";

            var buf: [256]u8 = undefined;
            if (kind_str.len > 0) {
                const line = std.fmt.bufPrint(&buf, "  \x1b[36m{s}\x1b[0m [{s}]{s}\n", .{ recipe.name, kind_str, default_str }) catch continue;
                stdout.writeAll(line) catch {};
            } else {
                const line = std.fmt.bufPrint(&buf, "  \x1b[36m{s}\x1b[0m{s}\n", .{ recipe.name, default_str }) catch continue;
                stdout.writeAll(line) catch {};
            }

            if (recipe.doc_comment) |doc| {
                var doc_buf: [256]u8 = undefined;
                const doc_line = std.fmt.bufPrint(&doc_buf, "    {s}\n", .{doc}) catch continue;
                stdout.writeAll(doc_line) catch {};
            }
        }
    }
};

test "executor basic" {
    const source =
        \\task hello:
        \\    echo "Hello"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    const jakefile = try p.parseJakefile();

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    executor.dry_run = true;
    try executor.execute("hello");
}
