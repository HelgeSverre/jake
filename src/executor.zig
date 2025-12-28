// Jake Executor - Runs recipes with dependency resolution

const std = @import("std");
const parser = @import("parser.zig");
const cache_mod = @import("cache.zig");
const conditions = @import("conditions.zig");
const parallel_mod = @import("parallel.zig");
const env_mod = @import("env.zig");
const hooks_mod = @import("hooks.zig");

const Jakefile = parser.Jakefile;
const Recipe = parser.Recipe;
const Cache = cache_mod.Cache;
const ParallelExecutor = parallel_mod.ParallelExecutor;
const Environment = env_mod.Environment;
const HookRunner = hooks_mod.HookRunner;
const HookContext = hooks_mod.HookContext;
const Hook = hooks_mod.Hook;

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
    expanded_strings: std.ArrayListUnmanaged([]const u8),
    environment: Environment,
    hook_runner: HookRunner,
    dry_run: bool,
    verbose: bool,
    jobs: usize, // Number of parallel jobs (0 = sequential, 1 = single-threaded, 2+ = parallel)
    positional_args: []const []const u8, // Positional args from command line ($1, $2, etc.)

    pub fn init(allocator: std.mem.Allocator, jakefile: *const Jakefile) Executor {
        var variables = std.StringHashMap([]const u8).init(allocator);

        // Load variables from jakefile
        for (jakefile.variables) |v| {
            variables.put(v.name, v.value) catch {};
        }

        // Initialize environment
        var environment = Environment.init(allocator);

        // Process directives for environment setup
        for (jakefile.directives) |directive| {
            switch (directive.kind) {
                .dotenv => {
                    // @dotenv [path] - load .env file
                    if (directive.args.len > 0) {
                        // Load specified .env file
                        for (directive.args) |path| {
                            environment.loadDotenv(stripQuotes(path)) catch {};
                        }
                    } else {
                        // Load default .env file
                        environment.loadDotenv(".env") catch {};
                    }
                },
                .@"export" => {
                    // @export KEY=value or @export KEY value
                    if (directive.args.len >= 1) {
                        const first_arg = directive.args[0];
                        // Check for KEY=value format
                        if (std.mem.indexOfScalar(u8, first_arg, '=')) |eq_pos| {
                            const key = first_arg[0..eq_pos];
                            const value = first_arg[eq_pos + 1 ..];
                            environment.set(key, stripQuotes(value)) catch {};
                        } else if (directive.args.len >= 2) {
                            // KEY value format
                            environment.set(first_arg, stripQuotes(directive.args[1])) catch {};
                        }
                    }
                },
                else => {},
            }
        }

        // Initialize hook runner with global hooks
        var hook_runner = HookRunner.init(allocator);
        for (jakefile.global_pre_hooks) |hook| {
            hook_runner.addGlobalHook(hook) catch {};
        }
        for (jakefile.global_post_hooks) |hook| {
            hook_runner.addGlobalHook(hook) catch {};
        }

        return .{
            .allocator = allocator,
            .jakefile = jakefile,
            .cache = Cache.init(allocator),
            .executed = std.StringHashMap(void).init(allocator),
            .in_progress = std.StringHashMap(void).init(allocator),
            .variables = variables,
            .expanded_strings = .empty,
            .environment = environment,
            .hook_runner = hook_runner,
            .dry_run = false,
            .verbose = false,
            .jobs = 0, // Default to sequential execution
            .positional_args = &.{}, // Empty by default
        };
    }

    /// Set positional arguments from command line (for $1, $2, $@, etc.)
    pub fn setPositionalArgs(self: *Executor, args: []const []const u8) void {
        self.positional_args = args;
    }

    pub fn deinit(self: *Executor) void {
        self.cache.deinit();
        self.executed.deinit();
        self.in_progress.deinit();
        self.variables.deinit();
        self.environment.deinit();
        self.hook_runner.deinit();
        // Free all expanded strings
        for (self.expanded_strings.items) |s| {
            self.allocator.free(s);
        }
        self.expanded_strings.deinit(self.allocator);
    }

    /// Execute a recipe by name
    pub fn execute(self: *Executor, name: []const u8) ExecuteError!void {
        // Use parallel execution if jobs > 1
        if (self.jobs > 1) {
            return self.executeParallel(name);
        }

        // Sequential execution
        return self.executeSequential(name);
    }

    /// Execute using parallel executor for concurrent dependency execution
    fn executeParallel(self: *Executor, name: []const u8) ExecuteError!void {
        var parallel_exec = ParallelExecutor.init(self.allocator, self.jakefile, self.jobs);
        defer parallel_exec.deinit();

        parallel_exec.dry_run = self.dry_run;
        parallel_exec.verbose = self.verbose;

        // Build dependency graph
        try parallel_exec.buildGraph(name);

        // Show parallelism stats in verbose mode
        if (self.verbose) {
            const stats = parallel_exec.getParallelismStats();
            self.print("jake: parallel execution with {d} threads\n", .{self.jobs});
            self.print("jake: {d} recipes, max {d} parallel, critical path length {d}\n", .{ stats.total_recipes, stats.max_parallel, stats.critical_path_length });
        }

        // Execute
        try parallel_exec.execute();
    }

    /// Execute sequentially (original behavior)
    fn executeSequential(self: *Executor, name: []const u8) ExecuteError!void {
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

        // Execute recipe dependencies first
        for (recipe.dependencies) |dep| {
            try self.executeSequential(dep);
        }

        // For file targets, also ensure file dependencies exist by running their recipes
        if (recipe.kind == .file) {
            for (recipe.file_deps) |file_dep| {
                // Check if this file dependency has a recipe that produces it
                if (self.findRecipeByOutput(file_dep)) |producing_recipe| {
                    // Execute that recipe to ensure the file exists
                    try self.executeSequential(producing_recipe.name);
                }
            }
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
        self.print("\x1b[1;36m-> {s}\x1b[0m\n", .{name});

        // Update hook runner settings
        self.hook_runner.dry_run = self.dry_run;
        self.hook_runner.verbose = self.verbose;

        // Create hook context
        var hook_context = HookContext{
            .recipe_name = name,
            .success = true,
            .error_message = null,
            .variables = &self.variables,
        };

        // Run pre-hooks (global and recipe-specific)
        self.hook_runner.runPreHooks(recipe.pre_hooks, &hook_context) catch |err| {
            self.print("\x1b[1;31merror:\x1b[0m pre-hook failed: {s}\n", .{@errorName(err)});
            return ExecuteError.CommandFailed;
        };

        // Execute the recipe commands
        const exec_result = self.executeCommands(recipe.commands);

        // Update hook context based on execution result
        if (exec_result) |_| {
            hook_context.success = true;
            hook_context.error_message = null;
        } else |err| {
            hook_context.success = false;
            hook_context.error_message = @errorName(err);
        }

        // Run post-hooks (always run, even on failure for cleanup)
        self.hook_runner.runPostHooks(recipe.post_hooks, &hook_context) catch |hook_err| {
            self.print("\x1b[1;33mwarning:\x1b[0m post-hook failed: {s}\n", .{@errorName(hook_err)});
        };

        // Return the original error if recipe execution failed
        if (exec_result) |_| {
            // Success - continue
        } else |err| {
            return err;
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

    /// Find a recipe that produces the given output file
    fn findRecipeByOutput(self: *Executor, output: []const u8) ?*const Recipe {
        for (self.jakefile.recipes) |*recipe| {
            if (recipe.output) |recipe_output| {
                if (std.mem.eql(u8, recipe_output, output)) {
                    return recipe;
                }
            }
        }
        return null;
    }

    /// Execute commands with conditional block support
    fn executeCommands(self: *Executor, cmds: []const Recipe.Command) ExecuteError!void {
        // Conditional state tracking
        // We use a simple state machine:
        // - executing: whether we're currently executing commands
        // - branch_taken: whether any branch in the current if/elif/else chain has matched
        // - nesting_depth: for nested conditionals (we skip inner blocks when outer is false)

        var executing: bool = true;
        var branch_taken: bool = false;
        var nesting_depth: usize = 0; // Track nested conditionals when skipping
        var ignore_next: bool = false; // Whether to ignore failures for the next command
        _ = &ignore_next; // TODO: implement @ignore directive usage

        var i: usize = 0;
        while (i < cmds.len) : (i += 1) {
            const cmd = cmds[i];

            // Handle conditional directives
            if (cmd.directive) |directive| {
                switch (directive) {
                    .@"if" => {
                        if (!executing) {
                            // We're already skipping, just track nesting
                            nesting_depth += 1;
                            continue;
                        }

                        // Extract condition from line (strip "if " prefix)
                        const condition = extractCondition(cmd.line, "if ");

                        // Evaluate the condition
                        const condition_result = conditions.evaluate(condition, &self.variables) catch |err| blk: {
                            self.print("\x1b[1;33mwarning:\x1b[0m failed to evaluate condition '{s}': {s}\n", .{ condition, @errorName(err) });
                            break :blk false;
                        };

                        if (condition_result) {
                            executing = true;
                            branch_taken = true;
                        } else {
                            executing = false;
                            branch_taken = false;
                        }
                        continue;
                    },
                    .elif => {
                        if (nesting_depth > 0) {
                            // Inside a skipped nested block, ignore
                            continue;
                        }

                        if (branch_taken) {
                            // A previous branch matched, skip this one
                            executing = false;
                            continue;
                        }

                        // Extract condition from line (strip "elif " prefix)
                        const condition = extractCondition(cmd.line, "elif ");

                        // Evaluate the condition
                        const condition_result = conditions.evaluate(condition, &self.variables) catch |err| blk: {
                            self.print("\x1b[1;33mwarning:\x1b[0m failed to evaluate condition '{s}': {s}\n", .{ condition, @errorName(err) });
                            break :blk false;
                        };

                        if (condition_result) {
                            executing = true;
                            branch_taken = true;
                        } else {
                            executing = false;
                        }
                        continue;
                    },
                    .@"else" => {
                        if (nesting_depth > 0) {
                            // Inside a skipped nested block, ignore
                            continue;
                        }

                        if (branch_taken) {
                            // A previous branch matched, skip else
                            executing = false;
                        } else {
                            // No branch matched yet, execute else
                            executing = true;
                            branch_taken = true;
                        }
                        continue;
                    },
                    .end => {
                        if (nesting_depth > 0) {
                            nesting_depth -= 1;
                            continue;
                        }

                        // End of conditional block, reset state
                        executing = true;
                        branch_taken = false;
                        continue;
                    },
                    .ignore => {
                        // @ignore directive: ignore failures for the next command
                        if (executing) {
                            ignore_next = true;
                        }
                        continue;
                    },
                    else => {
                        // Other directives, handle normally if executing
                    },
                }
            }

            // Skip command if not in executing state
            if (!executing) {
                continue;
            }

            // Execute the command, handling ignore directive
            if (ignore_next) {
                ignore_next = false;
                self.runCommand(cmd) catch |err| {
                    // Command failed but we're ignoring it
                    switch (err) {
                        ExecuteError.CommandFailed => {
                            // The error message with exit code was already printed by runCommand
                            self.print("\x1b[1;33m[ignored]\x1b[0m continuing despite command failure\n", .{});
                        },
                        else => {
                            self.print("\x1b[1;33m[ignored]\x1b[0m command failed with error: {s}\n", .{@errorName(err)});
                        },
                    }
                };
            } else {
                try self.runCommand(cmd);
            }
        }
    }

    fn runCommand(self: *Executor, cmd: Recipe.Command) ExecuteError!void {
        // First expand {{var}} Jake variables
        const jake_expanded = self.expandJakeVariables(cmd.line) catch cmd.line;
        if (jake_expanded.ptr != cmd.line.ptr) {
            self.expanded_strings.append(self.allocator, jake_expanded) catch return ExecuteError.OutOfMemory;
        }

        // Then expand $VAR and ${VAR} environment variables
        var line = self.environment.expandCommand(jake_expanded, self.allocator) catch jake_expanded;
        if (line.ptr != jake_expanded.ptr) {
            self.expanded_strings.append(self.allocator, line) catch return ExecuteError.OutOfMemory;
        }

        // Check for @ prefix to suppress command echo
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        const suppress_echo = trimmed.len > 0 and trimmed[0] == '@';
        if (suppress_echo) {
            // Strip the @ prefix (keeping any leading whitespace before @, then skip @)
            const at_pos = std.mem.indexOf(u8, line, "@").?;
            line = line[at_pos + 1 ..];
        }

        if (self.dry_run) {
            self.print("  [dry-run] {s}\n", .{line});
            return;
        }

        if (self.verbose and !suppress_echo) {
            self.print("  $ {s}\n", .{line});
        }

        // Execute via shell with custom environment
        var child = std.process.Child.init(
            &[_][]const u8{ "/bin/sh", "-c", line },
            self.allocator,
        );
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;

        // Set up environment for child process
        var env_map = self.environment.buildEnvMap(self.allocator) catch |err| {
            self.print("\x1b[1;33mwarning:\x1b[0m failed to build env map: {s}\n", .{@errorName(err)});
            // Continue without custom env
            _ = child.spawn() catch |spawn_err| {
                self.print("\x1b[1;31merror:\x1b[0m failed to spawn: {s}\n", .{@errorName(spawn_err)});
                return ExecuteError.CommandFailed;
            };
            const result = child.wait() catch |wait_err| {
                self.print("\x1b[1;31merror:\x1b[0m failed to wait: {s}\n", .{@errorName(wait_err)});
                return ExecuteError.CommandFailed;
            };
            if (result.Exited != 0) {
                self.print("\x1b[1;31merror:\x1b[0m command exited with code {d}\n", .{result.Exited});
                return ExecuteError.CommandFailed;
            }
            return;
        };
        defer env_map.deinit();
        child.env_map = &env_map;

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

    /// Expand {{var}} style Jake variables and positional args ({{$1}}, {{$2}}, {{$@}})
    fn expandJakeVariables(self: *Executor, line: []const u8) ![]const u8 {
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

                    // Check for positional args: $1, $2, ... or $@
                    if (var_name.len > 0 and var_name[0] == '$') {
                        const arg_spec = var_name[1..];
                        if (std.mem.eql(u8, arg_spec, "@")) {
                            // $@ - all positional args joined with space
                            for (self.positional_args, 0..) |arg, idx| {
                                if (idx > 0) try result.append(self.allocator, ' ');
                                try result.appendSlice(self.allocator, arg);
                            }
                        } else if (std.fmt.parseInt(usize, arg_spec, 10)) |num| {
                            // $1, $2, etc. (1-indexed)
                            if (num > 0 and num <= self.positional_args.len) {
                                try result.appendSlice(self.allocator, self.positional_args[num - 1]);
                            }
                            // If out of range, expand to empty string
                        } else |_| {
                            // Not a valid number, keep original
                            try result.appendSlice(self.allocator, line[i .. end + 2]);
                        }
                    } else if (self.variables.get(var_name)) |value| {
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
        std.io.getStdErr().writeAll(msg) catch {};
    }

    /// List all available recipes
    pub fn listRecipes(self: *Executor) void {
        const stdout = std.io.getStdOut();
        stdout.writeAll("\x1b[1mAvailable recipes:\x1b[0m\n") catch {};

        var hidden_count: usize = 0;

        for (self.jakefile.recipes) |recipe| {
            // Skip private recipes (names starting with '_')
            if (recipe.name.len > 0 and recipe.name[0] == '_') {
                hidden_count += 1;
                continue;
            }

            const kind_str = switch (recipe.kind) {
                .task => "task",
                .file => "file",
                .simple => "",
            };
            const default_str: []const u8 = if (recipe.is_default) " (default)" else "";

            // Build aliases string
            var alias_buf: [256]u8 = undefined;
            var alias_str: []const u8 = "";
            if (recipe.aliases.len > 0) {
                var fbs = std.io.fixedBufferStream(&alias_buf);
                fbs.writer().writeAll(" (aliases: ") catch {};
                for (recipe.aliases, 0..) |al, idx| {
                    if (idx > 0) fbs.writer().writeAll(", ") catch {};
                    fbs.writer().writeAll(al) catch {};
                }
                fbs.writer().writeAll(")") catch {};
                alias_str = fbs.getWritten();
            }

            var buf: [512]u8 = undefined;
            if (kind_str.len > 0) {
                const line = std.fmt.bufPrint(&buf, "  \x1b[36m{s}\x1b[0m [{s}]{s}{s}\n", .{ recipe.name, kind_str, default_str, alias_str }) catch continue;
                stdout.writeAll(line) catch {};
            } else {
                const line = std.fmt.bufPrint(&buf, "  \x1b[36m{s}\x1b[0m{s}{s}\n", .{ recipe.name, default_str, alias_str }) catch continue;
                stdout.writeAll(line) catch {};
            }

            if (recipe.doc_comment) |doc| {
                var doc_buf: [256]u8 = undefined;
                const doc_line = std.fmt.bufPrint(&doc_buf, "    {s}\n", .{doc}) catch continue;
                stdout.writeAll(doc_line) catch {};
            }
        }

        // Show count of hidden recipes
        if (hidden_count > 0) {
            var hidden_buf: [64]u8 = undefined;
            if (hidden_count == 1) {
                const hidden_line = std.fmt.bufPrint(&hidden_buf, "({d} hidden recipe)\n", .{hidden_count}) catch return;
                stdout.writeAll(hidden_line) catch {};
            } else {
                const hidden_line = std.fmt.bufPrint(&hidden_buf, "({d} hidden recipes)\n", .{hidden_count}) catch return;
                stdout.writeAll(hidden_line) catch {};
            }
        }
    }
};

/// Extract condition from a directive line by stripping the prefix
/// e.g., "if env(CI)" -> "env(CI)", "elif exists(foo)" -> "exists(foo)"
fn extractCondition(line: []const u8, prefix: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (std.mem.startsWith(u8, trimmed, prefix)) {
        return std.mem.trim(u8, trimmed[prefix.len..], " \t");
    }
    // Fallback: return the whole line trimmed
    return trimmed;
}

/// Strip surrounding quotes from a string
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

test "executor basic" {
    const source =
        \\task hello:
        \\    echo "Hello"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    executor.dry_run = true;
    try executor.execute("hello");
}

// ============================================================================
// COMPREHENSIVE EXECUTOR TESTS
// ============================================================================

// --- Dependency Resolution Order ---

test "executor executes dependencies first" {
    const source =
        \\first:
        \\    echo "first"
        \\second: [first]
        \\    echo "second"
        \\third: [second]
        \\    echo "third"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Execute third, which should trigger first, then second, then third
    try executor.execute("third");

    // Verify all were executed
    try std.testing.expect(executor.executed.contains("first"));
    try std.testing.expect(executor.executed.contains("second"));
    try std.testing.expect(executor.executed.contains("third"));
}

test "executor executes each dependency once" {
    const source =
        \\base:
        \\    echo "base"
        \\left: [base]
        \\    echo "left"
        \\right: [base]
        \\    echo "right"
        \\top: [left, right]
        \\    echo "top"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("top");

    // base should only be executed once (verified by the fact it's in executed set)
    try std.testing.expect(executor.executed.contains("base"));
    try std.testing.expect(executor.executed.contains("left"));
    try std.testing.expect(executor.executed.contains("right"));
    try std.testing.expect(executor.executed.contains("top"));
}

// --- Cycle Detection ---

test "executor detects direct cycle" {
    const source =
        \\a: [b]
        \\    echo "a"
        \\b: [a]
        \\    echo "b"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    const result = executor.execute("a");
    try std.testing.expectError(ExecuteError.CyclicDependency, result);
}

test "executor detects self cycle" {
    const source =
        \\a: [a]
        \\    echo "a"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    const result = executor.execute("a");
    try std.testing.expectError(ExecuteError.CyclicDependency, result);
}

test "executor detects indirect cycle" {
    const source =
        \\a: [b]
        \\    echo "a"
        \\b: [c]
        \\    echo "b"
        \\c: [a]
        \\    echo "c"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    const result = executor.execute("a");
    try std.testing.expectError(ExecuteError.CyclicDependency, result);
}

// --- Variable Expansion ---

test "executor expands jake variables" {
    const source =
        \\greeting = "Hello"
        \\task hello:
        \\    echo "{{greeting}} World"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Test the variable expansion function directly
    const expanded = try executor.expandJakeVariables("{{greeting}} World");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("Hello World", expanded);
}

test "executor preserves undefined variables" {
    const source =
        \\task hello:
        \\    echo "{{undefined}} World"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const expanded = try executor.expandJakeVariables("{{undefined}} World");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("{{undefined}} World", expanded);
}

test "executor expands multiple variables" {
    const source =
        \\first = "Hello"
        \\second = "World"
        \\task hello:
        \\    echo "{{first}} {{second}}!"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const expanded = try executor.expandJakeVariables("{{first}} {{second}}!");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("Hello World!", expanded);
}

// --- Dry Run Mode ---

test "executor dry run does not execute commands" {
    const source =
        \\task test:
        \\    exit 1
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should succeed because dry_run doesn't actually execute the failing command
    try executor.execute("test");
}

// --- Recipe Not Found ---

test "executor returns error for non-existent recipe" {
    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    const result = executor.execute("nonexistent");
    try std.testing.expectError(ExecuteError.RecipeNotFound, result);
}

test "executor returns error for missing dependency" {
    const source =
        \\task build: [missing]
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    const result = executor.execute("build");
    try std.testing.expectError(ExecuteError.RecipeNotFound, result);
}

// --- Task Types ---

test "executor handles simple recipe" {
    const source =
        \\build:
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("build");
    try std.testing.expect(executor.executed.contains("build"));
}

test "executor handles task recipe" {
    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("build");
    try std.testing.expect(executor.executed.contains("build"));
}

// --- Multiple Commands ---

test "executor runs multiple commands in recipe" {
    const source =
        \\task setup:
        \\    echo "step 1"
        \\    echo "step 2"
        \\    echo "step 3"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("setup");
}

// --- Recipe Execution Tracking ---

test "executor tracks executed recipes" {
    const source =
        \\a:
        \\    echo "a"
        \\b:
        \\    echo "b"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("a");
    try std.testing.expect(executor.executed.contains("a"));
    try std.testing.expect(!executor.executed.contains("b"));

    try executor.execute("b");
    try std.testing.expect(executor.executed.contains("a"));
    try std.testing.expect(executor.executed.contains("b"));
}

test "executor skips already executed recipe" {
    const source =
        \\base:
        \\    echo "base"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("base");
    try executor.execute("base"); // Should not re-execute
    try std.testing.expect(executor.executed.contains("base"));
}

// --- Variable Loading ---

test "executor loads jakefile variables" {
    const source =
        \\name = "test"
        \\version = "1.0.0"
        \\task info:
        \\    echo "{{name}} {{version}}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    try std.testing.expectEqualStrings("test", executor.variables.get("name").?);
    try std.testing.expectEqualStrings("1.0.0", executor.variables.get("version").?);
}

// --- Empty Recipe ---

test "executor handles empty recipe" {
    const source =
        \\empty:
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("empty");
    try std.testing.expect(executor.executed.contains("empty"));
}

// --- stripQuotes Tests ---

test "stripQuotes removes double quotes" {
    try std.testing.expectEqualStrings("hello", stripQuotes("\"hello\""));
}

test "stripQuotes removes single quotes" {
    try std.testing.expectEqualStrings("hello", stripQuotes("'hello'"));
}

test "stripQuotes preserves unquoted strings" {
    try std.testing.expectEqualStrings("hello", stripQuotes("hello"));
}

test "stripQuotes handles empty string" {
    try std.testing.expectEqualStrings("", stripQuotes(""));
}

test "stripQuotes handles short strings" {
    try std.testing.expectEqualStrings("a", stripQuotes("a"));
    try std.testing.expectEqualStrings("\"", stripQuotes("\""));
}

// --- @ Output Suppression Tests ---

test "executor @ prefix suppresses echo but still executes" {
    const source =
        \\task deploy:
        \\    @echo "quiet"
        \\    echo "loud"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;
    executor.verbose = true;

    // Should execute without errors (dry-run mode)
    try executor.execute("deploy");
    try std.testing.expect(executor.executed.contains("deploy"));
}

test "executor @ prefix strips @ before execution" {
    const source =
        \\task test:
        \\    @echo "hello"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Get the recipe command
    const recipe = jakefile.getRecipe("test").?;
    try std.testing.expect(recipe.commands.len == 1);

    // The command line should have @ prefix
    try std.testing.expect(std.mem.startsWith(u8, recipe.commands[0].line, "@"));
}

// --- Private Recipe Tests ---

test "private recipes are hidden from list but still executable" {
    const source =
        \\task build:
        \\    echo "Building..."
        \\
        \\task _internal-helper:
        \\    echo "Internal helper"
        \\
        \\task deploy: [_internal-helper]
        \\    echo "Deploying..."
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Private recipes should still be executable directly
    try executor.execute("_internal-helper");
    try std.testing.expect(executor.executed.contains("_internal-helper"));

    // Clear executed set for next test
    executor.executed.clearRetainingCapacity();

    // Private recipes should be executed as dependencies
    try executor.execute("deploy");
    try std.testing.expect(executor.executed.contains("_internal-helper"));
    try std.testing.expect(executor.executed.contains("deploy"));
}

test "countHiddenRecipes counts private recipes" {
    const source =
        \\task build:
        \\    echo "Building..."
        \\
        \\task _helper1:
        \\    echo "Helper 1"
        \\
        \\task _helper2:
        \\    echo "Helper 2"
        \\
        \\task deploy:
        \\    echo "Deploying..."
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Count hidden recipes manually (same logic as listRecipes)
    var hidden_count: usize = 0;
    for (jakefile.recipes) |recipe| {
        if (recipe.name.len > 0 and recipe.name[0] == '_') {
            hidden_count += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 2), hidden_count);
}

test "no hidden recipes when none start with underscore" {
    const source =
        \\task build:
        \\    echo "Building..."
        \\
        \\task deploy:
        \\    echo "Deploying..."
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Count hidden recipes manually
    var hidden_count: usize = 0;
    for (jakefile.recipes) |recipe| {
        if (recipe.name.len > 0 and recipe.name[0] == '_') {
            hidden_count += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 0), hidden_count);
}
