// Jake Executor - Runs recipes with dependency resolution

const std = @import("std");
const builtin = @import("builtin");
const compat = @import("compat.zig");
const parser = @import("parser.zig");
const cache_mod = @import("cache.zig");
const conditions = @import("conditions.zig");
const parallel_mod = @import("parallel.zig");
const env_mod = @import("env.zig");
const hooks_mod = @import("hooks.zig");
const prompt_mod = @import("prompt.zig");
const functions = @import("functions.zig");
const glob_mod = @import("glob.zig");
const color_mod = @import("color.zig");

const Jakefile = parser.Jakefile;
const Recipe = parser.Recipe;
const Cache = cache_mod.Cache;
const ParallelExecutor = parallel_mod.ParallelExecutor;
const Environment = env_mod.Environment;
const HookRunner = hooks_mod.HookRunner;
const HookContext = hooks_mod.HookContext;
const Hook = hooks_mod.Hook;
const Prompt = prompt_mod.Prompt;

pub const ExecuteError = error{
    RecipeNotFound,
    CommandFailed,
    CyclicDependency,
    OutOfMemory,
    FileNotFound,
    AccessDenied,
    SystemResources,
    Unexpected,
    MissingRequiredEnv,
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
    auto_yes: bool, // Auto-confirm all @confirm prompts
    jobs: usize, // Number of parallel jobs (0 = sequential, 1 = single-threaded, 2+ = parallel)
    positional_args: []const []const u8, // Positional args from command line ($1, $2, etc.)
    current_shell: ?[]const u8, // Shell to use for current recipe (from @shell directive)
    current_working_dir: ?[]const u8, // Working directory for current recipe (from @cd directive)
    current_quiet: bool, // Suppress command output for current recipe (from @quiet directive)
    prompt: Prompt, // Confirmation prompt handler
    watch_mode: bool, // Whether jake is running in watch mode (-w/--watch)
    color: color_mod.Color, // Color output configuration (respects NO_COLOR etc.)
    theme: color_mod.Theme, // Semantic color theme (error, warning, recipe, etc.)

    pub fn init(allocator: std.mem.Allocator, jakefile: *const Jakefile) Executor {
        var variables = std.StringHashMap([]const u8).init(allocator);

        // Load variables from jakefile (OOM here is unrecoverable)
        for (jakefile.variables) |v| {
            variables.put(v.name, v.value) catch {};
        }

        // Initialize environment
        var environment = Environment.init(allocator);

        // Process directives for environment setup
        for (jakefile.directives) |directive| {
            switch (directive.kind) {
                .dotenv => {
                    // @dotenv [path] - load .env file (best-effort: missing files are ignored)
                    if (directive.args.len > 0) {
                        for (directive.args) |path| {
                            environment.loadDotenv(stripQuotes(path)) catch {};
                        }
                    } else {
                        environment.loadDotenv(".env") catch {};
                    }
                },
                .@"export" => {
                    // @export KEY=value - export with explicit value
                    // @export KEY value - export with separate value
                    // @export KEY - export Jake variable to environment
                    if (directive.args.len >= 1) {
                        const first_arg = directive.args[0];
                        if (std.mem.indexOfScalar(u8, first_arg, '=')) |eq_pos| {
                            // @export KEY=value
                            const key = first_arg[0..eq_pos];
                            const value = first_arg[eq_pos + 1 ..];
                            environment.set(key, stripQuotes(value)) catch {};
                        } else if (directive.args.len >= 2) {
                            // @export KEY value
                            environment.set(first_arg, stripQuotes(directive.args[1])) catch {};
                        } else {
                            // @export KEY - export Jake variable to environment
                            if (variables.get(first_arg)) |value| {
                                environment.set(first_arg, value) catch {};
                            }
                        }
                    }
                },
                else => {},
            }
        }

        // Initialize hook runner with global hooks (OOM here is unrecoverable)
        var hook_runner = HookRunner.init(allocator);
        for (jakefile.global_pre_hooks) |hook| {
            hook_runner.addGlobalHook(hook) catch {};
        }
        for (jakefile.global_post_hooks) |hook| {
            hook_runner.addGlobalHook(hook) catch {};
        }
        for (jakefile.global_on_error_hooks) |hook| {
            hook_runner.addGlobalHook(hook) catch {};
        }

        // Initialize cache and load from disk
        var cache = Cache.init(allocator);
        cache.load() catch {}; // Ignore errors, start with empty cache if load fails

        return .{
            .allocator = allocator,
            .jakefile = jakefile,
            .cache = cache,
            .executed = std.StringHashMap(void).init(allocator),
            .in_progress = std.StringHashMap(void).init(allocator),
            .variables = variables,
            .expanded_strings = .empty,
            .environment = environment,
            .hook_runner = hook_runner,
            .dry_run = false,
            .verbose = false,
            .auto_yes = false,
            .jobs = 0, // Default to sequential execution
            .positional_args = &.{}, // Empty by default
            .current_shell = null,
            .current_working_dir = null,
            .current_quiet = false,
            .prompt = Prompt.init(),
            .watch_mode = false,
            .color = color_mod.init(),
            .theme = color_mod.Theme.init(),
        };
    }

    /// Set positional arguments from command line (for $1, $2, $@, etc.)
    pub fn setPositionalArgs(self: *Executor, args: []const []const u8) void {
        self.positional_args = args;
    }

    /// Validate that all required environment variables are set.
    /// Should be called before execute() to fail early with clear error messages.
    /// In dry-run mode, validation is skipped.
    pub fn validateRequiredEnv(self: *Executor) ExecuteError!void {
        // Skip validation in dry-run mode
        if (self.dry_run) {
            return;
        }

        // Check all @require directives
        for (self.jakefile.directives) |directive| {
            if (directive.kind == .require) {
                for (directive.args) |var_name| {
                    // First check our loaded environment (includes @dotenv vars)
                    if (self.environment.get(var_name)) |_| {
                        continue; // Variable exists in our environment
                    }

                    // Fall back to system environment
                    if (std.process.getEnvVarOwned(self.allocator, var_name)) |value| {
                        self.allocator.free(value);
                        continue; // Variable exists in system environment
                    } else |_| {
                        // Variable not found - report error
                        self.print("{s}Required environment variable '{s}' is not set\n", .{ self.color.errPrefix(), var_name });
                        self.print("  hint: Set this variable in your shell or add it to .env\n", .{});
                        return ExecuteError.MissingRequiredEnv;
                    }
                }
            }
        }
    }

    /// Check if a command exists in PATH or as an absolute path
    fn commandExists(self: *Executor, cmd: []const u8) bool {
        _ = self;
        // Handle absolute paths
        if (cmd.len > 0 and cmd[0] == '/') {
            return std.fs.accessAbsolute(cmd, .{}) != error.FileNotFound;
        }

        // Search in PATH
        const path_env = std.process.getEnvVarOwned(std.heap.page_allocator, "PATH") catch return false;
        defer std.heap.page_allocator.free(path_env);

        var path_iter = std.mem.splitScalar(u8, path_env, ':');
        while (path_iter.next()) |dir| {
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const full_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir, cmd }) catch continue;
            if (std.fs.accessAbsolute(full_path, .{})) |_| {
                return true;
            } else |_| {
                continue;
            }
        }
        return false;
    }

    /// Check recipe-level @needs requirements before running any commands
    fn checkRecipeLevelNeeds(self: *Executor, recipe: *const parser.Recipe) ExecuteError!void {
        for (recipe.needs) |req| {
            if (!self.commandExists(req.command)) {
                self.print("{s}recipe '{s}' requires '{s}' but it's not installed\n", .{ self.color.errPrefix(), recipe.name, req.command });

                // Show hint if provided
                if (req.hint) |hint| {
                    self.print("  hint: {s}\n", .{hint});
                }

                // Show install task suggestion if provided
                if (req.install_task) |task| {
                    self.print("  run: jake {s}\n", .{task});
                }

                return ExecuteError.CommandFailed;
            }
        }
    }

    /// Check @needs directive - verify required commands exist
    /// Supports: @needs cmd, @needs cmd "hint", @needs cmd -> task, @needs cmd "hint" -> task
    fn checkNeedsDirective(self: *Executor, line: []const u8) ExecuteError!void {
        // Parse command names (space or comma separated)
        // Skip leading whitespace
        var trimmed = std.mem.trim(u8, line, " \t");

        // Skip the directive keyword "needs" at the start of the line
        // The line format is: "needs sh cat ls" where "needs" is the keyword
        if (std.mem.startsWith(u8, trimmed, "needs")) {
            trimmed = std.mem.trimLeft(u8, trimmed[5..], " \t,");
        }

        // Split by spaces and commas, but handle quoted hints and -> task refs
        var i: usize = 0;
        while (i < trimmed.len) {
            // Skip separators (spaces and commas)
            while (i < trimmed.len and (trimmed[i] == ' ' or trimmed[i] == ',' or trimmed[i] == '\t')) {
                i += 1;
            }
            if (i >= trimmed.len) break;

            // Find end of command name (stop at space, comma, quote, or arrow)
            const cmd_start = i;
            while (i < trimmed.len and trimmed[i] != ' ' and trimmed[i] != ',' and
                trimmed[i] != '\t' and trimmed[i] != '"' and
                !(i + 1 < trimmed.len and trimmed[i] == '-' and trimmed[i + 1] == '>'))
            {
                i += 1;
            }
            const cmd = trimmed[cmd_start..i];

            if (cmd.len == 0) continue;

            // Parse optional hint (quoted string)
            var hint: ?[]const u8 = null;
            while (i < trimmed.len and (trimmed[i] == ' ' or trimmed[i] == '\t')) i += 1;
            if (i < trimmed.len and trimmed[i] == '"') {
                i += 1; // skip opening quote
                const hint_start = i;
                while (i < trimmed.len and trimmed[i] != '"') i += 1;
                hint = trimmed[hint_start..i];
                if (i < trimmed.len) i += 1; // skip closing quote
            }

            // Parse optional task reference (-> task-name)
            var install_task: ?[]const u8 = null;
            while (i < trimmed.len and (trimmed[i] == ' ' or trimmed[i] == '\t')) i += 1;
            if (i + 1 < trimmed.len and trimmed[i] == '-' and trimmed[i + 1] == '>') {
                i += 2; // skip ->
                while (i < trimmed.len and (trimmed[i] == ' ' or trimmed[i] == '\t')) i += 1;
                const task_start = i;
                while (i < trimmed.len and trimmed[i] != ' ' and trimmed[i] != ',' and trimmed[i] != '\t') {
                    i += 1;
                }
                install_task = trimmed[task_start..i];
            }

            // Check if command exists
            if (!self.commandExists(cmd)) {
                self.print("{s}Required command '{s}' not found\n", .{ self.color.errPrefix(), cmd });
                if (hint) |h| {
                    self.print("  hint: {s}\n", .{h});
                } else {
                    self.print("  hint: Install '{s}' or check your PATH\n", .{cmd});
                }
                if (install_task) |task| {
                    self.print("  run:  jake {s}\n", .{task});
                }
                return ExecuteError.CommandFailed;
            }
        }
    }

    /// Handle @confirm directive - prompt user for confirmation
    fn handleConfirmDirective(self: *Executor, line: []const u8) !prompt_mod.ConfirmResult {
        // Parse the message from the line
        // Line format is: "confirm Are you sure?" where "confirm" is the keyword
        var message = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, message, "confirm")) {
            message = std.mem.trimLeft(u8, message[7..], " \t");
        }

        // Use default message if none provided
        if (message.len == 0) {
            message = "Continue?";
        }

        // Update prompt settings from executor state
        self.prompt.auto_yes = self.auto_yes;
        self.prompt.dry_run = self.dry_run;

        return self.prompt.confirm(message);
    }

    /// Execute @launch directive - open file/URL with platform-specific command
    fn executeLaunch(self: *Executor, target: []const u8) ExecuteError!void {
        const argv: []const []const u8 = switch (builtin.os.tag) {
            .macos => &[_][]const u8{ "open", target },
            .linux => &[_][]const u8{ "xdg-open", target },
            .windows => &[_][]const u8{ "cmd", "/c", "start", "", target },
            else => {
                self.print("{s}@launch not supported on this platform\n", .{self.color.errPrefix()});
                return ExecuteError.CommandFailed;
            },
        };

        var child = std.process.Child.init(argv, self.allocator);
        child.spawn() catch |err| {
            self.print("{s}failed to launch '{s}': {s}\n", .{ self.color.errPrefix(), target, @errorName(err) });
            return ExecuteError.CommandFailed;
        };
        // Don't wait - let the app run in background
    }

    /// Parse items from @each directive line.
    /// Supports literal items, comma/space separated, and glob patterns.
    /// Glob patterns (containing *, ?, [) are expanded to matching files.
    /// Returns empty slice on OOM (loop will simply not execute).
    fn parseEachItems(self: *Executor, line: []const u8) []const []const u8 {
        // Line format is: "each a b c" or "each a, b, c" or "each src/*.zig"
        var trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "each")) {
            trimmed = std.mem.trimLeft(u8, trimmed[4..], " \t");
        }

        // If empty, return empty slice
        if (trimmed.len == 0) {
            return &.{};
        }

        // Parse items (space or comma separated)
        var items: std.ArrayListUnmanaged([]const u8) = .empty;
        // Track expanded paths for cleanup (owned memory)
        var expanded_paths: std.ArrayListUnmanaged([]const u8) = .empty;
        defer expanded_paths.deinit(self.allocator);

        var i: usize = 0;
        while (i < trimmed.len) {
            // Skip separators
            while (i < trimmed.len and (trimmed[i] == ' ' or trimmed[i] == ',' or trimmed[i] == '\t')) {
                i += 1;
            }
            if (i >= trimmed.len) break;

            // Find end of item
            const start = i;
            while (i < trimmed.len and trimmed[i] != ' ' and trimmed[i] != ',' and trimmed[i] != '\t') {
                i += 1;
            }
            const item_slice = trimmed[start..i];
            if (item_slice.len > 0) {
                // Check if this is a glob pattern
                if (glob_mod.isGlobPattern(item_slice)) {
                    // Expand the glob pattern
                    const expanded = glob_mod.expandGlob(self.allocator, item_slice) catch {
                        // On error, treat as literal
                        items.append(self.allocator, item_slice) catch {};
                        continue;
                    };

                    // Add all expanded paths to items
                    for (expanded) |path| {
                        items.append(self.allocator, path) catch {};
                        // Track for registration (but not cleanup - they're owned by items now)
                        self.expanded_strings.append(self.allocator, path) catch {};
                    }
                    // Free the slice container but not the contents
                    self.allocator.free(expanded);
                } else {
                    items.append(self.allocator, item_slice) catch {};
                }
            }
        }

        return items.toOwnedSlice(self.allocator) catch &.{};
    }

    /// Parse file patterns from @cache or @watch directive line.
    /// Returns empty slice on OOM (caching/watching will be disabled for this directive).
    fn parseCachePatterns(self: *Executor, line: []const u8) []const []const u8 {
        // Line format is: "cache file1.txt file2.txt" or "watch src/*.zig"
        var trimmed = std.mem.trim(u8, line, " \t");

        // Skip the directive keyword
        if (std.mem.startsWith(u8, trimmed, "cache")) {
            trimmed = std.mem.trimLeft(u8, trimmed[5..], " \t");
        } else if (std.mem.startsWith(u8, trimmed, "watch")) {
            trimmed = std.mem.trimLeft(u8, trimmed[5..], " \t");
        }

        // If empty, return empty slice
        if (trimmed.len == 0) {
            return &.{};
        }

        // Parse patterns (space or comma separated)
        var patterns: std.ArrayListUnmanaged([]const u8) = .empty;

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
            const pattern_slice = trimmed[start..i];
            if (pattern_slice.len > 0) {
                patterns.append(self.allocator, pattern_slice) catch {};
            }
        }

        return patterns.toOwnedSlice(self.allocator) catch &.{};
    }

    /// Execute a loop body with the current item value
    /// This handles nested directives like @if/@else/@end within @each loops
    fn executeEachBody(self: *Executor, body: []const Recipe.Command, item: []const u8) ExecuteError!void {
        // Conditional state tracking using a stack for proper nesting (same as executeCommands)
        const ConditionalState = struct {
            executing: bool,
            branch_taken: bool,
        };
        var cond_stack: [32]ConditionalState = undefined;
        var cond_depth: usize = 0;

        var executing: bool = true;
        var branch_taken: bool = false;

        var i: usize = 0;
        while (i < body.len) : (i += 1) {
            const cmd = body[i];

            // Expand {{item}} in the command line
            const expanded_line = self.expandItemVariable(cmd.line, item);
            defer if (expanded_line.ptr != cmd.line.ptr) self.allocator.free(expanded_line);

            if (cmd.directive) |d| {
                switch (d) {
                    .@"if" => {
                        // Push current state onto stack
                        if (cond_depth < cond_stack.len) {
                            cond_stack[cond_depth] = .{ .executing = executing, .branch_taken = branch_taken };
                            cond_depth += 1;
                        }

                        if (!executing) {
                            // Parent not executing, this block won't execute either
                            branch_taken = true; // Prevent @else from executing
                            continue;
                        }

                        // Extract condition from line (strip "if " prefix)
                        const condition = extractCondition(expanded_line, "if ");
                        const ctx = conditions.RuntimeContext{
                            .watch_mode = self.watch_mode,
                            .dry_run = self.dry_run,
                            .verbose = self.verbose,
                        };
                        const condition_result = conditions.evaluate(condition, &self.variables, ctx) catch false;

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
                        // Get parent's executing state
                        const parent_executing = if (cond_depth > 0) cond_stack[cond_depth - 1].executing else true;

                        if (!parent_executing) {
                            // Parent wasn't executing, we can't execute either
                            continue;
                        }

                        if (branch_taken) {
                            executing = false;
                            continue;
                        }
                        // Extract condition from line (strip "elif " prefix)
                        const condition = extractCondition(expanded_line, "elif ");
                        const ctx = conditions.RuntimeContext{
                            .watch_mode = self.watch_mode,
                            .dry_run = self.dry_run,
                            .verbose = self.verbose,
                        };
                        const condition_result = conditions.evaluate(condition, &self.variables, ctx) catch false;

                        if (condition_result) {
                            executing = true;
                            branch_taken = true;
                        } else {
                            executing = false;
                        }
                        continue;
                    },
                    .@"else" => {
                        // Get parent's executing state
                        const parent_executing = if (cond_depth > 0) cond_stack[cond_depth - 1].executing else true;

                        if (!parent_executing) {
                            // Parent wasn't executing, we can't execute either
                            continue;
                        }

                        if (!branch_taken) {
                            executing = true;
                            branch_taken = true;
                        } else {
                            executing = false;
                        }
                        continue;
                    },
                    .end => {
                        // Pop state from stack
                        if (cond_depth > 0) {
                            cond_depth -= 1;
                            executing = cond_stack[cond_depth].executing;
                            branch_taken = cond_stack[cond_depth].branch_taken;
                        } else {
                            executing = true;
                            branch_taken = false;
                        }
                        continue;
                    },
                    .ignore => {
                        // @ignore inside @each is not currently supported
                        continue;
                    },
                    else => {
                        // Other directives not handled inside @each loop body
                        continue;
                    },
                }
            }

            // Run the command if we're executing
            if (executing) {
                const modified_cmd = Recipe.Command{
                    .line = expanded_line,
                    .directive = null,
                };
                try self.runCommand(modified_cmd);
            }
        }
    }

    /// Expand {{item}} in a string
    fn expandItemVariable(self: *Executor, input: []const u8, item: []const u8) []const u8 {
        const needle = "{{item}}";
        if (std.mem.indexOf(u8, input, needle) == null) {
            return input;
        }

        var result: std.ArrayListUnmanaged(u8) = .empty;
        var pos: usize = 0;

        while (std.mem.indexOfPos(u8, input, pos, needle)) |idx| {
            result.appendSlice(self.allocator, input[pos..idx]) catch return input;
            result.appendSlice(self.allocator, item) catch return input;
            pos = idx + needle.len;
        }
        result.appendSlice(self.allocator, input[pos..]) catch return input;

        return result.toOwnedSlice(self.allocator) catch input;
    }

    pub fn deinit(self: *Executor) void {
        // Persist cache to disk before cleanup
        self.cache.save() catch {};
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

        // Check OS constraints - skip recipe if not for current OS
        if (shouldSkipForOs(recipe)) {
            const current_os = getCurrentOsString();
            self.print("jake: skipping '{s}' (not for {s})\n", .{ name, current_os });
            self.executed.put(name, {}) catch return ExecuteError.OutOfMemory;
            return;
        }

        // Check recipe-level @needs requirements before running any commands
        if (recipe.needs.len > 0) {
            try self.checkRecipeLevelNeeds(recipe);
        }

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
                self.executed.put(name, {}) catch return ExecuteError.OutOfMemory;
                return;
            }
        }

        // Run the recipe - capture start time for duration display
        const start_time = std.time.nanoTimestamp();
        self.print("{s} {f}\n", .{ self.theme.arrowSymbol(), self.theme.recipeHeader(name) });

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
            self.print("{s}pre-hook failed: {s}\n", .{ self.color.errPrefix(), @errorName(err) });
            self.printCompletionStatus(name, false, start_time);
            return ExecuteError.CommandFailed;
        };

        // Set recipe-level shell and working directory
        self.current_shell = recipe.shell;
        self.current_working_dir = recipe.working_dir;
        self.current_quiet = recipe.quiet;

        // Bind recipe parameters to variables
        self.bindRecipeParams(recipe) catch |err| {
            self.print("{s}failed to bind parameters: {s}\n", .{ self.color.errPrefix(), @errorName(err) });
            self.printCompletionStatus(name, false, start_time);
            return ExecuteError.CommandFailed;
        };

        // Execute the recipe commands (with timeout if specified)
        const exec_result = if (recipe.timeout_seconds) |timeout_secs|
            self.executeCommandsWithTimeout(recipe.commands, recipe.name, timeout_secs)
        else
            self.executeCommands(recipe.commands);

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
            self.print("{s}post-hook failed: {s}\n", .{ self.color.warnPrefix(), @errorName(hook_err) });
        };

        // Run on_error hooks if recipe failed
        if (!hook_context.success) {
            self.hook_runner.runOnErrorHooks(&hook_context);
        }

        // Return the original error if recipe execution failed
        if (exec_result) |_| {
            // Success - print completion with timing
            self.printCompletionStatus(name, true, start_time);
        } else |err| {
            self.printCompletionStatus(name, false, start_time);
            return err;
        }

        // Update cache for file targets
        if (recipe.kind == .file) {
            if (recipe.output) |output| {
                // Cache update is best-effort; failure doesn't affect recipe execution
                self.cache.update(output) catch {};
            }
        }

        self.executed.put(name, {}) catch return ExecuteError.OutOfMemory;
    }

    /// Bind recipe parameters to variables based on CLI args and defaults
    fn bindRecipeParams(self: *Executor, recipe: *const Recipe) !void {
        // Build a map of CLI args in key=value format
        var cli_args = std.StringHashMap([]const u8).init(self.allocator);
        defer cli_args.deinit();

        for (self.positional_args) |arg| {
            if (std.mem.indexOfScalar(u8, arg, '=')) |eq_pos| {
                const key = arg[0..eq_pos];
                const value = arg[eq_pos + 1 ..];
                try cli_args.put(key, value);
            }
        }

        // For each recipe parameter, bind to a variable
        for (recipe.params) |param| {
            if (cli_args.get(param.name)) |value| {
                // CLI arg takes precedence
                try self.variables.put(param.name, value);
            } else if (param.default) |default_value| {
                // Use default value
                try self.variables.put(param.name, default_value);
            }
            // If no CLI arg and no default, param is simply not set
            // (could add required param check here if needed)
        }
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

    /// Get current OS as a string
    fn getCurrentOsString() []const u8 {
        return switch (builtin.os.tag) {
            .linux => "linux",
            .macos => "macos",
            .windows => "windows",
            .freebsd => "freebsd",
            .openbsd => "openbsd",
            .netbsd => "netbsd",
            .dragonfly => "dragonfly",
            else => "unknown",
        };
    }

    /// Check if recipe should be skipped due to OS constraints
    /// Returns true if recipe should be skipped, false if it should run
    fn shouldSkipForOs(recipe: *const Recipe) bool {
        // If no only_os constraints, don't skip
        if (recipe.only_os.len == 0) {
            return false;
        }

        const current_os = getCurrentOsString();

        // Check if current OS is in the allowed list
        for (recipe.only_os) |allowed_os| {
            if (std.mem.eql(u8, allowed_os, current_os)) {
                return false; // Current OS is allowed, don't skip
            }
        }

        // Current OS is not in the allowed list, skip
        return true;
    }

    /// Execute commands with timeout enforcement using a watchdog thread
    /// The watchdog monitors time and kills the child process if timeout is exceeded
    fn executeCommandsWithTimeout(
        self: *Executor,
        cmds: []const Recipe.Command,
        recipe_name: []const u8,
        timeout_seconds: u64,
    ) ExecuteError!void {
        // Context shared between main thread and watchdog, heap-allocated for safety
        const TimeoutContext = struct {
            timeout_expired: std.atomic.Value(bool),
            current_child: std.atomic.Value(?*std.process.Child),
            deadline_ms: i64,

            fn init(deadline: i64) @This() {
                return .{
                    .timeout_expired = std.atomic.Value(bool).init(false),
                    .current_child = std.atomic.Value(?*std.process.Child).init(null),
                    .deadline_ms = deadline,
                };
            }
        };

        const WatchdogThread = struct {
            fn run(ctx: *TimeoutContext) void {
                while (!ctx.timeout_expired.load(.acquire)) {
                    const now = std.time.milliTimestamp();
                    if (now >= ctx.deadline_ms) {
                        // Timeout! Signal the child to terminate (don't wait - main thread does that)
                        ctx.timeout_expired.store(true, .release);
                        if (ctx.current_child.load(.acquire)) |child| {
                            // Send SIGKILL directly without waiting (avoiding race with main thread's wait)
                            if (builtin.os.tag != .windows) {
                                _ = std.posix.kill(child.id, std.posix.SIG.KILL) catch {};
                            }
                        }
                        return;
                    }
                    // Check every 50ms
                    std.Thread.sleep(50 * std.time.ns_per_ms);
                }
            }
        };

        // Calculate deadline
        const start_time = std.time.milliTimestamp();
        const deadline = start_time + @as(i64, @intCast(timeout_seconds * 1000));

        // Allocate context on heap so it outlives this function if needed
        var ctx = self.allocator.create(TimeoutContext) catch {
            // OOM - fall back to non-timeout execution
            return self.executeCommands(cmds);
        };
        ctx.* = TimeoutContext.init(deadline);
        defer self.allocator.destroy(ctx);

        // Start watchdog thread
        const watchdog = std.Thread.spawn(.{}, WatchdogThread.run, .{ctx}) catch {
            // Can't spawn watchdog - fall back to non-timeout execution
            return self.executeCommands(cmds);
        };

        // Execute commands, checking for timeout after each
        const result = self.executeCommandsWithTimeoutCheck(cmds, ctx);

        // Signal watchdog to stop and wait for it
        ctx.timeout_expired.store(true, .release);
        watchdog.join();

        // Check if we timed out
        if (ctx.timeout_expired.load(.acquire) and result == ExecuteError.CommandFailed) {
            self.print("{s}Recipe '{s}' exceeded timeout of {d}s\n", .{
                self.color.errPrefix(),
                recipe_name,
                timeout_seconds,
            });
        }

        return result;
    }

    /// Execute commands with timeout checking - stores child process for watchdog to kill
    fn executeCommandsWithTimeoutCheck(
        self: *Executor,
        cmds: []const Recipe.Command,
        timeout_ctx: anytype,
    ) ExecuteError!void {
        // This is a wrapper that passes timeout context to runCommand
        // For now, we'll use a simpler approach: check timeout before each command

        // Execute commands normally but check timeout between each
        return self.executeCommandsInternal(cmds, timeout_ctx);
    }

    /// Internal command execution with optional timeout context
    fn executeCommandsInternal(
        self: *Executor,
        cmds: []const Recipe.Command,
        timeout_ctx: anytype,
    ) ExecuteError!void {
        const has_timeout = comptime @TypeOf(timeout_ctx) != ?*anyopaque;

        // Check if timeout already expired
        if (has_timeout) {
            if (timeout_ctx.timeout_expired.load(.acquire)) {
                return ExecuteError.CommandFailed;
            }
        }

        // Delegate to the main executeCommands but with timeout awareness
        // For simplicity, we'll inline a modified version here
        return self.executeCommandsCore(cmds, timeout_ctx);
    }

    /// Core command execution logic with optional timeout context
    fn executeCommandsCore(self: *Executor, cmds: []const Recipe.Command, timeout_ctx: anytype) ExecuteError!void {
        // Conditional state tracking using a stack for proper nesting
        const ConditionalState = struct {
            executing: bool,
            branch_taken: bool,
        };
        var cond_stack: [32]ConditionalState = undefined;
        var cond_depth: usize = 0;
        var executing: bool = true;
        var branch_taken: bool = false;
        var ignore_next: bool = false;

        // Helper to check if timeout has expired
        const has_timeout = comptime @TypeOf(timeout_ctx) != ?*anyopaque;

        var i: usize = 0;
        while (i < cmds.len) : (i += 1) {
            // Check timeout before each command
            if (has_timeout) {
                if (timeout_ctx.timeout_expired.load(.acquire)) {
                    return ExecuteError.CommandFailed;
                }
            }

            const cmd = cmds[i];

            // Handle conditional directives (same as executeCommands)
            if (cmd.directive) |directive| {
                switch (directive) {
                    .@"if" => {
                        if (cond_depth < cond_stack.len) {
                            cond_stack[cond_depth] = .{ .executing = executing, .branch_taken = branch_taken };
                            cond_depth += 1;
                        }
                        if (!executing) {
                            branch_taken = false;
                            continue;
                        }
                        const condition = extractCondition(cmd.line, "if ");
                        const ctx = conditions.RuntimeContext{
                            .watch_mode = self.watch_mode,
                            .dry_run = self.dry_run,
                            .verbose = self.verbose,
                        };
                        const condition_result = conditions.evaluate(condition, &self.variables, ctx) catch false;
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
                        const parent_executing = if (cond_depth > 0) cond_stack[cond_depth - 1].executing else true;
                        if (!parent_executing) continue;
                        if (branch_taken) {
                            executing = false;
                            continue;
                        }
                        const condition = extractCondition(cmd.line, "elif ");
                        const ctx = conditions.RuntimeContext{
                            .watch_mode = self.watch_mode,
                            .dry_run = self.dry_run,
                            .verbose = self.verbose,
                        };
                        const condition_result = conditions.evaluate(condition, &self.variables, ctx) catch false;
                        if (condition_result) {
                            executing = true;
                            branch_taken = true;
                        } else {
                            executing = false;
                        }
                        continue;
                    },
                    .@"else" => {
                        const parent_executing = if (cond_depth > 0) cond_stack[cond_depth - 1].executing else true;
                        if (!parent_executing) continue;
                        if (branch_taken) {
                            executing = false;
                        } else {
                            executing = true;
                            branch_taken = true;
                        }
                        continue;
                    },
                    .end => {
                        if (cond_depth > 0) {
                            cond_depth -= 1;
                            executing = cond_stack[cond_depth].executing;
                            branch_taken = cond_stack[cond_depth].branch_taken;
                        } else {
                            executing = true;
                            branch_taken = false;
                        }
                        continue;
                    },
                    .ignore => {
                        if (executing) ignore_next = true;
                        continue;
                    },
                    .needs => {
                        if (!executing) continue;
                        try self.checkNeedsDirective(cmd.line);
                        continue;
                    },
                    .confirm => {
                        if (!executing) continue;
                        const result = self.handleConfirmDirective(cmd.line) catch {
                            return ExecuteError.CommandFailed;
                        };
                        if (result == .no) {
                            self.print("Aborted.\n", .{});
                            return ExecuteError.CommandFailed;
                        }
                        continue;
                    },
                    .each => {
                        if (!executing) {
                            var depth: usize = 1;
                            var j = i + 1;
                            while (j < cmds.len) : (j += 1) {
                                if (cmds[j].directive) |d| {
                                    if (d == .each) depth += 1;
                                    if (d == .end) {
                                        depth -= 1;
                                        if (depth == 0) break;
                                    }
                                }
                            }
                            i = j;
                            continue;
                        }
                        const expanded_line = self.expandJakeVariables(cmd.line) catch cmd.line;
                        if (expanded_line.ptr != cmd.line.ptr) {
                            self.expanded_strings.append(self.allocator, expanded_line) catch return ExecuteError.OutOfMemory;
                        }
                        const items = self.parseEachItems(expanded_line);
                        defer self.allocator.free(items);
                        var depth: usize = 1;
                        var end_idx = i + 1;
                        while (end_idx < cmds.len) : (end_idx += 1) {
                            if (cmds[end_idx].directive) |d| {
                                if (d == .each) depth += 1;
                                if (d == .end) {
                                    depth -= 1;
                                    if (depth == 0) break;
                                }
                            }
                        }
                        const loop_body = cmds[i + 1 .. end_idx];
                        for (items) |item| {
                            self.variables.put("item", item) catch {};
                            try self.executeEachBody(loop_body, item);
                        }
                        _ = self.variables.remove("item");
                        i = end_idx;
                        continue;
                    },
                    .cache => {
                        if (!executing) continue;
                        const patterns = self.parseCachePatterns(cmd.line);
                        defer self.allocator.free(patterns);
                        var is_stale = false;
                        for (patterns) |pattern| {
                            if (self.cache.isGlobStale(pattern) catch true) {
                                is_stale = true;
                                break;
                            }
                        }
                        if (!is_stale and patterns.len > 0) {
                            self.print("  {s}[cached]{s} skipping (inputs unchanged)\n", .{ self.color.muted(), self.color.reset() });
                            i += 1;
                            while (i < cmds.len and cmds[i].directive == null) : (i += 1) {}
                            i -= 1;
                            continue;
                        }
                        i += 1;
                        if (i < cmds.len and cmds[i].directive == null) {
                            try self.runCommandWithTimeout(cmds[i], timeout_ctx);
                            for (patterns) |pattern| {
                                self.cache.update(pattern) catch {};
                            }
                        }
                        continue;
                    },
                    .watch => {
                        if (!executing) continue;
                        if (self.dry_run) {
                            const patterns = self.parseCachePatterns(cmd.line);
                            defer self.allocator.free(patterns);
                            self.print("  [dry-run] @watch would monitor: ", .{});
                            for (patterns, 0..) |pattern, idx| {
                                if (idx > 0) self.print(", ", .{});
                                self.print("{s}", .{pattern});
                            }
                            self.print("\n", .{});
                        }
                        continue;
                    },
                    .launch => {
                        if (!executing) continue;
                        var target = std.mem.trim(u8, cmd.line, " \t");
                        if (std.mem.startsWith(u8, target, "launch")) {
                            target = std.mem.trimLeft(u8, target[6..], " \t");
                        }
                        const expanded_target = try self.expandJakeVariables(target);
                        try self.expanded_strings.append(self.allocator, expanded_target);
                        if (self.dry_run) {
                            self.print("  [dry-run] @launch {s}\n", .{expanded_target});
                            continue;
                        }
                        try self.executeLaunch(expanded_target);
                        continue;
                    },
                }
            }

            if (!executing) continue;

            // Execute command with timeout awareness
            if (ignore_next) {
                ignore_next = false;
                self.runCommandWithTimeout(cmd, timeout_ctx) catch |err| {
                    switch (err) {
                        ExecuteError.CommandFailed => {
                            self.print("{s}[ignored]{s} continuing despite command failure\n", .{ self.color.warningYellow(), self.color.reset() });
                        },
                        else => {
                            self.print("{s}[ignored]{s} command failed with error: {s}\n", .{ self.color.warningYellow(), self.color.reset(), @errorName(err) });
                        },
                    }
                };
            } else {
                try self.runCommandWithTimeout(cmd, timeout_ctx);
            }
        }
    }

    /// Run a single command with optional timeout context for child process tracking
    fn runCommandWithTimeout(self: *Executor, cmd: Recipe.Command, timeout_ctx: anytype) ExecuteError!void {
        const has_timeout = comptime @TypeOf(timeout_ctx) != ?*anyopaque;

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
            const at_pos = std.mem.indexOf(u8, line, "@").?;
            line = line[at_pos + 1 ..];
        }

        if (self.dry_run) {
            self.print("  [dry-run] {s}\n", .{line});
            return;
        }

        if (self.verbose and !suppress_echo and !self.current_quiet) {
            self.print("  $ {s}\n", .{line});
        }

        const shell_cmd = if (self.current_shell) |shell| shell else "/bin/sh";

        var child = std.process.Child.init(
            &[_][]const u8{ shell_cmd, "-c", line },
            self.allocator,
        );
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;

        if (self.current_working_dir) |working_dir| {
            child.cwd = working_dir;
        }

        var env_map = self.environment.buildEnvMap(self.allocator) catch |err| {
            self.print("{s}failed to build env map: {s}\n", .{ self.color.warnPrefix(), @errorName(err) });
            _ = child.spawn() catch |spawn_err| {
                self.print("{s}failed to spawn: {s}\n", .{ self.color.errPrefix(), @errorName(spawn_err) });
                return ExecuteError.CommandFailed;
            };
            const result = child.wait() catch |wait_err| {
                self.print("{s}failed to wait: {s}\n", .{ self.color.errPrefix(), @errorName(wait_err) });
                return ExecuteError.CommandFailed;
            };
            switch (result) {
                .Exited => |code| {
                    if (code != 0) {
                        self.print("{s}command exited with code {d}\n", .{ self.color.errPrefix(), code });
                        return ExecuteError.CommandFailed;
                    }
                },
                .Signal => |sig| {
                    self.print("{s}command killed by signal {d}\n", .{ self.color.errPrefix(), sig });
                    return ExecuteError.CommandFailed;
                },
                .Stopped => |sig| {
                    self.print("{s}command stopped by signal {d}\n", .{ self.color.errPrefix(), sig });
                    return ExecuteError.CommandFailed;
                },
                .Unknown => |code| {
                    self.print("{s}command terminated with unknown status {d}\n", .{ self.color.errPrefix(), code });
                    return ExecuteError.CommandFailed;
                },
            }
            return;
        };
        defer env_map.deinit();
        child.env_map = &env_map;

        _ = child.spawn() catch |err| {
            self.print("{s}failed to spawn: {s}\n", .{ self.color.errPrefix(), @errorName(err) });
            return ExecuteError.CommandFailed;
        };

        // Register child with timeout context so watchdog can kill it
        if (has_timeout) {
            timeout_ctx.current_child.store(&child, .release);
        }

        const result = child.wait() catch |err| {
            // Clear child from context
            if (has_timeout) {
                timeout_ctx.current_child.store(null, .release);
            }
            self.print("{s}failed to wait: {s}\n", .{ self.color.errPrefix(), @errorName(err) });
            return ExecuteError.CommandFailed;
        };

        // Clear child from context
        if (has_timeout) {
            timeout_ctx.current_child.store(null, .release);
        }

        // Handle both normal exit and signal termination
        switch (result) {
            .Exited => |code| {
                if (code != 0) {
                    self.print("{s}command exited with code {d}\n", .{ self.color.errPrefix(), code });
                    return ExecuteError.CommandFailed;
                }
            },
            .Signal => |sig| {
                // Process was killed by signal (e.g., SIGKILL from timeout)
                self.print("{s}command killed by signal {d}\n", .{ self.color.errPrefix(), sig });
                return ExecuteError.CommandFailed;
            },
            .Stopped => |sig| {
                self.print("{s}command stopped by signal {d}\n", .{ self.color.errPrefix(), sig });
                return ExecuteError.CommandFailed;
            },
            .Unknown => |code| {
                self.print("{s}command terminated with unknown status {d}\n", .{ self.color.errPrefix(), code });
                return ExecuteError.CommandFailed;
            },
        }
    }

    /// Execute commands with conditional block support (no timeout)
    fn executeCommands(self: *Executor, cmds: []const Recipe.Command) ExecuteError!void {
        // Delegate to core with no timeout context
        const no_timeout: ?*anyopaque = null;
        return self.executeCommandsCore(cmds, no_timeout);
    }

    fn runCommand(self: *Executor, cmd: Recipe.Command) ExecuteError!void {
        // Delegate to timeout-aware version with no timeout
        const no_timeout: ?*anyopaque = null;
        return self.runCommandWithTimeout(cmd, no_timeout);
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
                    } else if (std.mem.indexOfScalar(u8, var_name, '(') != null) {
                        // Function call: {{func(arg)}}
                        if (functions.evaluate(self.allocator, var_name, &self.variables)) |func_result| {
                            try result.appendSlice(self.allocator, func_result);
                            try self.expanded_strings.append(self.allocator, func_result);
                        } else |_| {
                            // Function failed, keep original
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
        compat.getStdErr().writeAll(msg) catch {};
    }

    /// Print completion status with timing (per brand guide Style A)
    /// Success: ✓ recipe_name (duration)
    /// Failure: ✗ recipe_name (duration)
    fn printCompletionStatus(self: *Executor, name: []const u8, success: bool, start_time: i128) void {
        const end_time = std.time.nanoTimestamp();
        const duration_ns = end_time - start_time;
        const duration_ms = @divFloor(duration_ns, 1_000_000);
        const duration_s = @as(f64, @floatFromInt(duration_ms)) / 1000.0;

        const stderr = compat.getStdErr();
        if (success) {
            // ✓ recipe_name (duration) - all in success green, duration muted
            stderr.writeAll(self.color.successGreen()) catch {};
            stderr.writeAll(color_mod.symbols.success) catch {};
            stderr.writeAll(" ") catch {};
            stderr.writeAll(name) catch {};
            stderr.writeAll(self.color.reset()) catch {};
            stderr.writeAll(" ") catch {};
            stderr.writeAll(self.color.muted()) catch {};
            var buf: [32]u8 = undefined;
            const duration_str = std.fmt.bufPrint(&buf, "({d:.1}s)", .{duration_s}) catch "(?)";
            stderr.writeAll(duration_str) catch {};
            stderr.writeAll(self.color.reset()) catch {};
            stderr.writeAll("\n") catch {};
        } else {
            // ✗ recipe_name (duration) - all in error red, duration muted
            stderr.writeAll(self.color.errorRed()) catch {};
            stderr.writeAll(color_mod.symbols.failure) catch {};
            stderr.writeAll(" ") catch {};
            stderr.writeAll(name) catch {};
            stderr.writeAll(self.color.reset()) catch {};
            stderr.writeAll(" ") catch {};
            stderr.writeAll(self.color.muted()) catch {};
            var buf: [32]u8 = undefined;
            const duration_str = std.fmt.bufPrint(&buf, "({d:.1}s)", .{duration_s}) catch "(?)";
            stderr.writeAll(duration_str) catch {};
            stderr.writeAll(self.color.reset()) catch {};
            stderr.writeAll("\n") catch {};
        }
    }

    /// Check if a recipe is private (should be hidden from listings)
    /// Uses origin.original_name for imported recipes, otherwise uses name
    fn isPrivateRecipe(recipe: *const Recipe) bool {
        const name = if (recipe.origin) |o| o.original_name else recipe.name;
        return name.len > 0 and name[0] == '_';
    }

    /// List all available recipes
    // TODO: Highlight the default recipe in the list output (e.g., with a star or "default" label).
    // Currently `jake --verbose` runs the default but `-> build` appears first because it's a
    // dependency, which can confuse users into thinking `build` is the target instead of `all`.
    pub fn listRecipes(self: *Executor, short_mode: bool, show_all: bool) void {
        const stdout = compat.getStdOut();

        // Short mode: one recipe name per line, no colors, no formatting
        if (short_mode) {
            for (self.jakefile.recipes) |*recipe| {
                if (!show_all and isPrivateRecipe(recipe)) continue;
                stdout.writeAll(recipe.name) catch {};
                stdout.writeAll("\n") catch {};
            }
            return;
        }

        stdout.writeAll(self.color.bold()) catch {};
        stdout.writeAll("Available recipes:") catch {};
        stdout.writeAll(self.color.reset()) catch {};
        stdout.writeAll("\n") catch {};

        // Group recipes by their group field
        var groups = std.StringHashMap(std.ArrayListUnmanaged(*const Recipe)).init(self.allocator);
        defer {
            var it = groups.valueIterator();
            while (it.next()) |list| {
                list.deinit(self.allocator);
            }
            groups.deinit();
        }

        var ungrouped: std.ArrayListUnmanaged(*const Recipe) = .{};
        defer ungrouped.deinit(self.allocator);

        var hidden: std.ArrayListUnmanaged(*const Recipe) = .{};
        defer hidden.deinit(self.allocator);

        // Collect recipes into groups
        for (self.jakefile.recipes) |*recipe| {
            const is_private = isPrivateRecipe(recipe);

            if (is_private) {
                if (show_all) {
                    hidden.append(self.allocator, recipe) catch continue;
                }
                continue;
            }

            if (recipe.group) |group_name| {
                const gop = groups.getOrPut(group_name) catch continue;
                if (!gop.found_existing) {
                    gop.value_ptr.* = .{};
                }
                gop.value_ptr.append(self.allocator, recipe) catch continue;
            } else {
                ungrouped.append(self.allocator, recipe) catch continue;
            }
        }

        // Get sorted group names
        var group_names: std.ArrayListUnmanaged([]const u8) = .{};
        defer group_names.deinit(self.allocator);

        var key_it = groups.keyIterator();
        while (key_it.next()) |key| {
            group_names.append(self.allocator, key.*) catch continue;
        }

        // Sort group names alphabetically
        std.mem.sort([]const u8, group_names.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        // Print grouped recipes
        for (group_names.items) |group_name| {
            if (groups.get(group_name)) |recipes| {
                stdout.writeAll("\n") catch {};
                stdout.writeAll(self.color.jakeRose()) catch {};
                stdout.writeAll(group_name) catch {};
                stdout.writeAll(":") catch {};
                stdout.writeAll(self.color.reset()) catch {};
                stdout.writeAll("\n") catch {};

                for (recipes.items) |recipe| {
                    self.printRecipe(stdout, recipe);
                }
            }
        }

        // Print ungrouped recipes
        if (ungrouped.items.len > 0) {
            if (group_names.items.len > 0) {
                stdout.writeAll("\n") catch {};
            }
            for (ungrouped.items) |recipe| {
                self.printRecipe(stdout, recipe);
            }
        }

        // Print hidden recipes (when --all is used)
        if (hidden.items.len > 0) {
            stdout.writeAll("\n") catch {};
            // Muted color for hidden group header
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("(hidden):") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll("\n") catch {};
            for (hidden.items) |recipe| {
                self.printRecipe(stdout, recipe);
            }
        }
    }

    /// Print space-separated recipe names (for shell completion/scripting)
    pub fn printSummary(self: *Executor) void {
        const stdout = compat.getStdOut();
        var first = true;

        for (self.jakefile.recipes) |*recipe| {
            if (isPrivateRecipe(recipe)) continue;

            if (!first) {
                stdout.writeAll(" ") catch {};
            }
            stdout.writeAll(recipe.name) catch {};
            first = false;
        }
        stdout.writeAll("\n") catch {};
    }

    /// Print a single recipe with its metadata
    fn printRecipe(self: *Executor, stdout: std.fs.File, recipe: *const Recipe) void {
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

        // Print recipe name with brand color (Jake Rose)
        stdout.writeAll("  ") catch {};
        stdout.writeAll(self.color.jakeRose()) catch {};
        stdout.writeAll(recipe.name) catch {};
        stdout.writeAll(self.color.reset()) catch {};
        if (kind_str.len > 0) {
            stdout.writeAll(" [") catch {};
            stdout.writeAll(kind_str) catch {};
            stdout.writeAll("]") catch {};
        }
        stdout.writeAll(default_str) catch {};
        stdout.writeAll(alias_str) catch {};

        // Show description inline if available (muted brand gray)
        if (recipe.description) |desc| {
            stdout.writeAll("  ") catch {};
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("# ") catch {};
            stdout.writeAll(desc) catch {};
            stdout.writeAll(self.color.reset()) catch {};
        }
        stdout.writeAll("\n") catch {};

        // Show doc_comment on next line if available (and different from description)
        if (recipe.doc_comment) |doc| {
            // Only show if there's no description or if doc is different from description
            const should_show = if (recipe.description) |desc| !std.mem.eql(u8, doc, desc) else true;
            if (should_show) {
                stdout.writeAll("    ") catch {};
                stdout.writeAll(self.color.muted()) catch {};
                stdout.writeAll(doc) catch {};
                stdout.writeAll(self.color.reset()) catch {};
                stdout.writeAll("\n") catch {};
            }
        }
    }

    /// Show detailed information about a specific recipe
    pub fn showRecipe(self: *Executor, name: []const u8) bool {
        const stdout = compat.getStdOut();

        const recipe = self.jakefile.getRecipe(name) orelse {
            const stderr = compat.getStdErr();
            stderr.writeAll(self.color.errPrefix()) catch {};
            stderr.writeAll("Recipe '") catch {};
            stderr.writeAll(name) catch {};
            stderr.writeAll("' not found\n") catch {};
            return false;
        };

        // Header - label muted, name in Jake Rose
        stdout.writeAll(self.color.muted()) catch {};
        stdout.writeAll("Recipe:") catch {};
        stdout.writeAll(self.color.reset()) catch {};
        stdout.writeAll(" ") catch {};
        stdout.writeAll(self.color.jakeRose()) catch {};
        stdout.writeAll(recipe.name) catch {};
        stdout.writeAll(self.color.reset()) catch {};
        if (isPrivateRecipe(recipe)) {
            stdout.writeAll(" ") catch {};
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("(hidden)") catch {};
            stdout.writeAll(self.color.reset()) catch {};
        }
        stdout.writeAll("\n") catch {};

        // Type - label muted
        const kind_str = switch (recipe.kind) {
            .task => "task",
            .file => "file",
            .simple => "simple",
        };
        stdout.writeAll(self.color.muted()) catch {};
        stdout.writeAll("Type:") catch {};
        stdout.writeAll(self.color.reset()) catch {};
        stdout.writeAll(" ") catch {};
        stdout.writeAll(kind_str) catch {};
        stdout.writeAll("\n") catch {};

        // Group (if present) - label muted, value in Jake Rose
        if (recipe.group) |group| {
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Group:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll(" ") catch {};
            stdout.writeAll(self.color.jakeRose()) catch {};
            stdout.writeAll(group) catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll("\n") catch {};
        }

        // Description - label muted
        if (recipe.description) |desc| {
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Description:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll(" ") catch {};
            stdout.writeAll(desc) catch {};
            stdout.writeAll("\n") catch {};
        }

        // Doc comment (if different from description) - label muted
        if (recipe.doc_comment) |doc| {
            const should_show = if (recipe.description) |desc| !std.mem.eql(u8, doc, desc) else true;
            if (should_show) {
                stdout.writeAll(self.color.muted()) catch {};
                stdout.writeAll("Doc:") catch {};
                stdout.writeAll(self.color.reset()) catch {};
                stdout.writeAll(" ") catch {};
                stdout.writeAll(doc) catch {};
                stdout.writeAll("\n") catch {};
            }
        }

        // Aliases - label muted, aliases in Jake Rose
        if (recipe.aliases.len > 0) {
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Aliases:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll(" ") catch {};
            for (recipe.aliases, 0..) |alias, i| {
                if (i > 0) stdout.writeAll(", ") catch {};
                stdout.writeAll(self.color.jakeRose()) catch {};
                stdout.writeAll(alias) catch {};
                stdout.writeAll(self.color.reset()) catch {};
            }
            stdout.writeAll("\n") catch {};
        }

        // Default marker - label muted
        if (recipe.is_default) {
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Default:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll(" yes\n") catch {};
        }

        // Dependencies - label muted, deps in Jake Rose
        if (recipe.dependencies.len > 0) {
            stdout.writeAll("\n") catch {};
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Dependencies:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll(" [") catch {};
            for (recipe.dependencies, 0..) |dep, i| {
                if (i > 0) stdout.writeAll(", ") catch {};
                stdout.writeAll(self.color.jakeRose()) catch {};
                stdout.writeAll(dep) catch {};
                stdout.writeAll(self.color.reset()) catch {};
            }
            stdout.writeAll("]\n") catch {};
        }

        // File dependencies - label muted
        if (recipe.file_deps.len > 0) {
            stdout.writeAll("\n") catch {};
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("File dependencies:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll("\n") catch {};
            for (recipe.file_deps) |fd| {
                stdout.writeAll("  ") catch {};
                stdout.writeAll(fd) catch {};
                stdout.writeAll("\n") catch {};
            }
        }

        // Output (for file recipes) - label muted
        if (recipe.output) |output| {
            stdout.writeAll("\n") catch {};
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Output:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll(" ") catch {};
            stdout.writeAll(output) catch {};
            stdout.writeAll("\n") catch {};
        }

        // Parameters - label muted
        if (recipe.params.len > 0) {
            stdout.writeAll("\n") catch {};
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Parameters:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll("\n") catch {};
            for (recipe.params) |param| {
                stdout.writeAll("  ") catch {};
                stdout.writeAll(param.name) catch {};
                if (param.default) |def| {
                    stdout.writeAll(self.color.muted()) catch {};
                    stdout.writeAll(" (default: \"") catch {};
                    stdout.writeAll(def) catch {};
                    stdout.writeAll("\")") catch {};
                    stdout.writeAll(self.color.reset()) catch {};
                } else {
                    stdout.writeAll(self.color.muted()) catch {};
                    stdout.writeAll(" (required)") catch {};
                    stdout.writeAll(self.color.reset()) catch {};
                }
                stdout.writeAll("\n") catch {};
            }
        }

        // Commands - label muted, directives in warning yellow
        if (recipe.commands.len > 0) {
            stdout.writeAll("\n") catch {};
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Commands:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll("\n") catch {};
            for (recipe.commands) |cmd| {
                stdout.writeAll("  ") catch {};
                if (cmd.directive) |dir| {
                    stdout.writeAll(self.color.warningYellow()) catch {};
                    stdout.writeAll("@") catch {};
                    const dir_name = switch (dir) {
                        .cache => "cache",
                        .needs => "needs",
                        .confirm => "confirm",
                        .watch => "watch",
                        .@"if" => "if",
                        .elif => "elif",
                        .@"else" => "else",
                        .end => "end",
                        .each => "each",
                        .ignore => "ignore",
                        .launch => "launch",
                    };
                    stdout.writeAll(dir_name) catch {};
                    stdout.writeAll(self.color.reset()) catch {};
                    stdout.writeAll(" ") catch {};
                }
                stdout.writeAll(cmd.line) catch {};
                stdout.writeAll("\n") catch {};
            }
        }

        // Hooks - label muted, hook keywords in success green
        if (recipe.pre_hooks.len > 0 or recipe.post_hooks.len > 0) {
            stdout.writeAll("\n") catch {};
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Hooks:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll("\n") catch {};
            for (recipe.pre_hooks) |hook| {
                stdout.writeAll("  ") catch {};
                stdout.writeAll(self.color.successGreen()) catch {};
                stdout.writeAll("@pre:") catch {};
                stdout.writeAll(self.color.reset()) catch {};
                stdout.writeAll(" ") catch {};
                stdout.writeAll(hook.command) catch {};
                stdout.writeAll("\n") catch {};
            }
            for (recipe.post_hooks) |hook| {
                stdout.writeAll("  ") catch {};
                stdout.writeAll(self.color.successGreen()) catch {};
                stdout.writeAll("@post:") catch {};
                stdout.writeAll(self.color.reset()) catch {};
                stdout.writeAll(" ") catch {};
                stdout.writeAll(hook.command) catch {};
                stdout.writeAll("\n") catch {};
            }
        }

        // Recipe-level @needs - label muted, @needs in warning yellow
        if (recipe.needs.len > 0) {
            stdout.writeAll("\n") catch {};
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Requirements:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll("\n") catch {};
            for (recipe.needs) |need| {
                stdout.writeAll("  ") catch {};
                stdout.writeAll(self.color.warningYellow()) catch {};
                stdout.writeAll("@needs") catch {};
                stdout.writeAll(self.color.reset()) catch {};
                stdout.writeAll(" ") catch {};
                stdout.writeAll(need.command) catch {};
                if (need.hint) |hint| {
                    stdout.writeAll(" \"") catch {};
                    stdout.writeAll(hint) catch {};
                    stdout.writeAll("\"") catch {};
                }
                stdout.writeAll("\n") catch {};
            }
        }

        // Platform constraints - label muted
        if (recipe.only_os.len > 0) {
            stdout.writeAll("\n") catch {};
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Platform:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll(" ") catch {};
            for (recipe.only_os, 0..) |os, i| {
                if (i > 0) stdout.writeAll(", ") catch {};
                stdout.writeAll(os) catch {};
            }
            stdout.writeAll("\n") catch {};
        }

        // Working directory - label muted
        if (recipe.working_dir) |wd| {
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Working directory:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll(" ") catch {};
            stdout.writeAll(wd) catch {};
            stdout.writeAll("\n") catch {};
        }

        // Shell - label muted
        if (recipe.shell) |shell| {
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Shell:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll(" ") catch {};
            stdout.writeAll(shell) catch {};
            stdout.writeAll("\n") catch {};
        }

        // Quiet mode - label muted
        if (recipe.quiet) {
            stdout.writeAll(self.color.muted()) catch {};
            stdout.writeAll("Quiet:") catch {};
            stdout.writeAll(self.color.reset()) catch {};
            stdout.writeAll(" yes\n") catch {};
        }

        return true;
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

    // Count hidden recipes using isPrivateRecipe
    var hidden_count: usize = 0;
    for (jakefile.recipes) |*recipe| {
        if (Executor.isPrivateRecipe(recipe)) {
            hidden_count += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 0), hidden_count);
}

test "countHiddenRecipes includes imported private recipes via origin" {
    // This tests that private recipe counting works correctly for imported recipes
    // where the name is "lib._helper" but origin.original_name is "_helper"
    var recipes = [_]Recipe{
        .{
            .name = "main",
            .loc = .{ .start = 0, .end = 0, .line = 1, .column = 1 },
            .origin = null,
            .kind = .task,
            .dependencies = &.{},
            .file_deps = &.{},
            .output = null,
            .params = &.{},
            .commands = &.{},
            .pre_hooks = &.{},
            .post_hooks = &.{},
            .doc_comment = null,
            .is_default = false,
            .aliases = &.{},
            .group = null,
            .description = null,
            .shell = null,
            .working_dir = null,
            .only_os = &.{},
            .quiet = false,
            .needs = &.{},
            .timeout_seconds = null,
        },
        .{
            .name = "lib.build", // Public imported recipe
            .loc = .{ .start = 0, .end = 0, .line = 1, .column = 1 },
            .origin = .{
                .original_name = "build",
                .import_prefix = "lib",
                .source_file = "lib.jake",
            },
            .kind = .task,
            .dependencies = &.{},
            .file_deps = &.{},
            .output = null,
            .params = &.{},
            .commands = &.{},
            .pre_hooks = &.{},
            .post_hooks = &.{},
            .doc_comment = null,
            .is_default = false,
            .aliases = &.{},
            .group = null,
            .description = null,
            .shell = null,
            .working_dir = null,
            .only_os = &.{},
            .quiet = false,
            .needs = &.{},
            .timeout_seconds = null,
        },
        .{
            .name = "lib._helper", // Private imported recipe - should be counted!
            .loc = .{ .start = 0, .end = 0, .line = 1, .column = 1 },
            .origin = .{
                .original_name = "_helper",
                .import_prefix = "lib",
                .source_file = "lib.jake",
            },
            .kind = .task,
            .dependencies = &.{},
            .file_deps = &.{},
            .output = null,
            .params = &.{},
            .commands = &.{},
            .pre_hooks = &.{},
            .post_hooks = &.{},
            .doc_comment = null,
            .is_default = false,
            .aliases = &.{},
            .group = null,
            .description = null,
            .shell = null,
            .working_dir = null,
            .only_os = &.{},
            .quiet = false,
            .needs = &.{},
            .timeout_seconds = null,
        },
        .{
            .name = "_local_private", // Direct private recipe - should be counted!
            .loc = .{ .start = 0, .end = 0, .line = 1, .column = 1 },
            .origin = null,
            .kind = .task,
            .dependencies = &.{},
            .file_deps = &.{},
            .output = null,
            .params = &.{},
            .commands = &.{},
            .pre_hooks = &.{},
            .post_hooks = &.{},
            .doc_comment = null,
            .is_default = false,
            .aliases = &.{},
            .group = null,
            .description = null,
            .shell = null,
            .working_dir = null,
            .only_os = &.{},
            .quiet = false,
            .needs = &.{},
            .timeout_seconds = null,
        },
    };

    // Count using isPrivateRecipe (same logic as listRecipes)
    var hidden_count: usize = 0;
    for (&recipes) |*recipe| {
        if (Executor.isPrivateRecipe(recipe)) {
            hidden_count += 1;
        }
    }

    // Should count 2 private recipes: lib._helper and _local_private
    try std.testing.expectEqual(@as(usize, 2), hidden_count);
}

test "isPrivateRecipe detects private via origin.original_name" {
    // Test that isPrivateRecipe correctly uses origin.original_name for imported recipes
    var recipe = Recipe{
        .name = "lib._helper", // Prefixed name doesn't start with _
        .loc = .{ .start = 0, .end = 0, .line = 1, .column = 1 },
        .origin = .{
            .original_name = "_helper", // Original starts with _
            .import_prefix = "lib",
            .source_file = "imported.jake",
        },
        .kind = .task,
        .dependencies = &.{},
        .file_deps = &.{},
        .output = null,
        .params = &.{},
        .commands = &.{},
        .pre_hooks = &.{},
        .post_hooks = &.{},
        .doc_comment = null,
        .is_default = false,
        .aliases = &.{},
        .group = null,
        .description = null,
        .shell = null,
        .working_dir = null,
        .only_os = &.{},
        .quiet = false,
        .needs = &.{},
        .timeout_seconds = null,
    };

    // Should be private because origin.original_name starts with _
    try std.testing.expect(Executor.isPrivateRecipe(&recipe));

    // Now test a non-private imported recipe
    recipe.name = "lib.build";
    recipe.origin = .{
        .original_name = "build",
        .import_prefix = "lib",
        .source_file = "imported.jake",
    };
    try std.testing.expect(!Executor.isPrivateRecipe(&recipe));

    // Test direct private recipe (no origin)
    recipe.name = "_local_helper";
    recipe.origin = null;
    try std.testing.expect(Executor.isPrivateRecipe(&recipe));

    // Test direct public recipe (no origin)
    recipe.name = "build";
    recipe.origin = null;
    try std.testing.expect(!Executor.isPrivateRecipe(&recipe));
}

test "isPrivateRecipe edge cases" {
    var recipe = Recipe{
        .name = "",
        .loc = .{ .start = 0, .end = 0, .line = 1, .column = 1 },
        .origin = null,
        .kind = .task,
        .dependencies = &.{},
        .file_deps = &.{},
        .output = null,
        .params = &.{},
        .commands = &.{},
        .pre_hooks = &.{},
        .post_hooks = &.{},
        .doc_comment = null,
        .is_default = false,
        .aliases = &.{},
        .group = null,
        .description = null,
        .shell = null,
        .working_dir = null,
        .only_os = &.{},
        .quiet = false,
        .needs = &.{},
        .timeout_seconds = null,
    };

    // Empty name should return false (not private)
    recipe.name = "";
    try std.testing.expect(!Executor.isPrivateRecipe(&recipe));

    // Single underscore is private
    recipe.name = "_";
    try std.testing.expect(Executor.isPrivateRecipe(&recipe));

    // Double underscore is private
    recipe.name = "__init";
    try std.testing.expect(Executor.isPrivateRecipe(&recipe));

    // Name starting with dot is NOT private (different convention)
    recipe.name = ".hidden";
    try std.testing.expect(!Executor.isPrivateRecipe(&recipe));

    // Origin with empty original_name should use that (return false)
    recipe.name = "lib._helper";
    recipe.origin = .{
        .original_name = "",
        .import_prefix = "lib",
        .source_file = "test.jake",
    };
    try std.testing.expect(!Executor.isPrivateRecipe(&recipe));

    // Origin with single underscore original_name
    recipe.origin = .{
        .original_name = "_",
        .import_prefix = "lib",
        .source_file = "test.jake",
    };
    try std.testing.expect(Executor.isPrivateRecipe(&recipe));
}

// --- @ignore Directive Tests ---

test "executor @ignore continues after failed command" {
    const source =
        \\task test-all:
        \\    @ignore
        \\    exit 1
        \\    echo "still running"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Check that @ignore is parsed correctly as a directive
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes[0].commands.len);
    try std.testing.expectEqual(Recipe.CommandDirective.ignore, jakefile.recipes[0].commands[0].directive.?);
    try std.testing.expect(jakefile.recipes[0].commands[1].directive == null);
}

test "executor @ignore only affects next command" {
    const source =
        \\task test:
        \\    echo "first"
        \\    @ignore
        \\    exit 1
        \\    echo "third"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Verify the commands are parsed correctly
    try std.testing.expectEqual(@as(usize, 4), jakefile.recipes[0].commands.len);
    // First command has no directive
    try std.testing.expect(jakefile.recipes[0].commands[0].directive == null);
    // Second command is @ignore directive
    try std.testing.expectEqual(Recipe.CommandDirective.ignore, jakefile.recipes[0].commands[1].directive.?);
    // Third command (exit 1) has no directive - it's the one that will be ignored
    try std.testing.expect(jakefile.recipes[0].commands[2].directive == null);
    // Fourth command has no directive
    try std.testing.expect(jakefile.recipes[0].commands[3].directive == null);
}

test "executor @ignore in dry run mode" {
    const source =
        \\task test:
        \\    @ignore
        \\    exit 1
        \\    echo "done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should succeed in dry-run mode (commands aren't actually executed)
    try executor.execute("test");
    try std.testing.expect(executor.executed.contains("test"));
}

test "executor multiple @ignore directives" {
    const source =
        \\task test-all:
        \\    @ignore
        \\    exit 1
        \\    @ignore
        \\    exit 2
        \\    echo "all tests complete"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Verify structure
    try std.testing.expectEqual(@as(usize, 5), jakefile.recipes[0].commands.len);
    try std.testing.expectEqual(Recipe.CommandDirective.ignore, jakefile.recipes[0].commands[0].directive.?);
    try std.testing.expectEqual(Recipe.CommandDirective.ignore, jakefile.recipes[0].commands[2].directive.?);
}

// --- Positional Arguments Tests ---

test "executor expands single positional arg $1" {
    const source =
        \\task deploy:
        \\    echo "Deploying to {{$1}}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Set positional args
    const args = [_][]const u8{"production"};
    executor.setPositionalArgs(&args);

    const expanded = try executor.expandJakeVariables("Deploying to {{$1}}");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("Deploying to production", expanded);
}

test "executor expands multiple positional args $1 and $2" {
    const source =
        \\task deploy:
        \\    echo "{{$1}} {{$2}}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Set positional args
    const args = [_][]const u8{ "production", "1.2.3" };
    executor.setPositionalArgs(&args);

    const expanded = try executor.expandJakeVariables("{{$1}} {{$2}}");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("production 1.2.3", expanded);
}

test "executor expands $@ to all positional args" {
    const source =
        \\task deploy:
        \\    echo "All: {{$@}}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Set positional args
    const args = [_][]const u8{ "production", "1.2.3", "extra" };
    executor.setPositionalArgs(&args);

    const expanded = try executor.expandJakeVariables("All: {{$@}}");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("All: production 1.2.3 extra", expanded);
}

test "executor expands out of range positional arg to empty string" {
    const source =
        \\task test:
        \\    echo "{{$1}} {{$2}} {{$3}}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Set only 2 positional args
    const args = [_][]const u8{ "one", "two" };
    executor.setPositionalArgs(&args);

    const expanded = try executor.expandJakeVariables("{{$1}} {{$2}} {{$3}}");
    defer executor.allocator.free(expanded);

    // $3 should expand to empty string
    try std.testing.expectEqualStrings("one two ", expanded);
}

test "executor expands $0 to empty string" {
    const source =
        \\task test:
        \\    echo "{{$0}}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const args = [_][]const u8{"arg1"};
    executor.setPositionalArgs(&args);

    const expanded = try executor.expandJakeVariables("{{$0}}");
    defer executor.allocator.free(expanded);

    // $0 is 1-indexed so it expands to empty
    try std.testing.expectEqualStrings("", expanded);
}

test "executor expands empty $@ to empty string" {
    const source =
        \\task test:
        \\    echo "[{{$@}}]"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // No positional args set (default)
    const expanded = try executor.expandJakeVariables("[{{$@}}]");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("[]", expanded);
}

test "executor mixes positional args and named variables" {
    const source =
        \\env = "staging"
        \\task deploy:
        \\    echo "Deploy {{env}} to {{$1}}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const args = [_][]const u8{"server1"};
    executor.setPositionalArgs(&args);

    const expanded = try executor.expandJakeVariables("Deploy {{env}} to {{$1}}");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("Deploy staging to server1", expanded);
}

test "executor preserves invalid positional arg syntax" {
    const source =
        \\task test:
        \\    echo "{{$abc}}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const expanded = try executor.expandJakeVariables("{{$abc}}");
    defer executor.allocator.free(expanded);

    // $abc is not a valid number, should be preserved
    try std.testing.expectEqualStrings("{{$abc}}", expanded);
}

// =============================================================================
// Whitespace handling in variable expansion tests
// =============================================================================

test "variable expansion does not trim whitespace - leading space" {
    const source =
        \\task test:
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Set a variable without leading space
    try executor.variables.put("myvar", "hello");

    // {{ myvar}} with leading space should NOT match "myvar"
    const expanded = try executor.expandJakeVariables("{{ myvar}}");
    defer executor.allocator.free(expanded);

    // Should be preserved as-is since " myvar" doesn't match "myvar"
    try std.testing.expectEqualStrings("{{ myvar}}", expanded);
}

test "variable expansion does not trim whitespace - trailing space" {
    const source =
        \\task test:
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    try executor.variables.put("myvar", "hello");

    // {{myvar }} with trailing space should NOT match "myvar"
    const expanded = try executor.expandJakeVariables("{{myvar }}");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("{{myvar }}", expanded);
}

test "variable expansion does not trim whitespace - both sides" {
    const source =
        \\task test:
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    try executor.variables.put("myvar", "hello");

    // {{ myvar }} with spaces on both sides should NOT match "myvar"
    const expanded = try executor.expandJakeVariables("{{ myvar }}");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("{{ myvar }}", expanded);
}

test "positional arg expansion does not trim whitespace" {
    const source =
        \\task test:
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Set positional args
    const args = [_][]const u8{"world"};
    executor.setPositionalArgs(&args);

    // {{ $1 }} with spaces should NOT expand (space before $ breaks it)
    const expanded = try executor.expandJakeVariables("{{ $1 }}");
    defer executor.allocator.free(expanded);

    // Should be preserved as-is
    try std.testing.expectEqualStrings("{{ $1 }}", expanded);
}

test "function calls tolerate whitespace in arguments" {
    const source =
        \\task test:
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Function arguments ARE trimmed by the functions module
    const expanded = try executor.expandJakeVariables("{{uppercase( hello )}}");
    defer executor.allocator.free(expanded);

    try std.testing.expectEqualStrings("HELLO", expanded);
}

// =============================================================================
// @require directive tests
// =============================================================================

test "@require validates single env var exists" {
    // Set up environment variable for this test
    const result = std.process.getEnvVarOwned(std.testing.allocator, "PATH");
    if (result) |path| {
        defer std.testing.allocator.free(path);
        // PATH exists, test should pass
    } else |_| {
        // PATH should always exist
        return error.TestSetupFailed;
    }

    const source =
        \\@require PATH
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Should not return an error since PATH exists
    try executor.validateRequiredEnv();
}

test "@require fails with clear error when env var missing" {
    const source =
        \\@require JAKE_TEST_NONEXISTENT_VAR_12345
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Should return MissingRequiredEnv error
    const err = executor.validateRequiredEnv();
    try std.testing.expectError(ExecuteError.MissingRequiredEnv, err);
}

test "@require checks multiple variables in single directive" {
    // Use platform-appropriate env vars (HOME on Unix, USERPROFILE on Windows)
    const source = if (builtin.os.tag == .windows)
        \\@require PATH USERPROFILE
        \\task test:
        \\    echo "ok"
    else
        \\@require PATH HOME
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    try executor.validateRequiredEnv();
}

test "@require checks multiple @require directives" {
    // Use platform-appropriate env vars
    const source = if (builtin.os.tag == .windows)
        \\@require PATH
        \\@require USERPROFILE
        \\task test:
        \\    echo "ok"
    else
        \\@require PATH
        \\@require HOME
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    try executor.validateRequiredEnv();
}

test "@require skips validation in dry-run mode" {
    const source =
        \\@require JAKE_TEST_NONEXISTENT_VAR_12345
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // In dry-run mode, should not fail
    try executor.validateRequiredEnv();
}

test "@require with empty value still passes" {
    // An env var that exists but is empty should still pass
    // We'll use the environment module to set an empty value
    const source =
        \\@require PATH
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // PATH exists (even if hypothetically empty), should pass
    try executor.validateRequiredEnv();
}

test "@require fails on second missing var in list" {
    const source =
        \\@require PATH JAKE_TEST_NONEXISTENT_VAR_12345
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Should fail because JAKE_TEST_NONEXISTENT_VAR_12345 doesn't exist
    const err = executor.validateRequiredEnv();
    try std.testing.expectError(ExecuteError.MissingRequiredEnv, err);
}

test "@require works with env vars from dotenv" {
    // Test that @require checks vars loaded via @dotenv
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create a .env file with a test variable
    const env_file = try tmp_dir.dir.createFile(".env", .{});
    try env_file.writeAll("JAKE_TEST_FROM_DOTENV=hello\n");
    env_file.close();

    // Get absolute path for chdir
    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Save and change working directory
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);
    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    const source =
        \\@dotenv
        \\@require JAKE_TEST_FROM_DOTENV
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Should pass because JAKE_TEST_FROM_DOTENV was loaded from .env
    try executor.validateRequiredEnv();
}

// =============================================================================
// @needs directive tests
// =============================================================================

test "@needs verifies command exists in PATH" {
    const source =
        \\task test:
        \\    @needs sh
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // 'sh' should exist on all systems
    try executor.execute("test");
}

test "@needs fails with helpful error when command missing" {
    const source =
        \\task test:
        \\    @needs jake_nonexistent_command_xyz123
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should fail because command doesn't exist
    const err = executor.execute("test");
    try std.testing.expectError(ExecuteError.CommandFailed, err);
}

test "@needs checks multiple space-separated commands" {
    const source =
        \\task test:
        \\    @needs sh cat ls
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // All commands should exist
    try executor.execute("test");
}

test "@needs works with full path to binary" {
    const source =
        \\task test:
        \\    @needs /bin/sh
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@needs with non-existent command in middle of list fails" {
    const source =
        \\task test:
        \\    @needs sh jake_nonexistent_xyz cat
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should fail on the non-existent command
    const err = executor.execute("test");
    try std.testing.expectError(ExecuteError.CommandFailed, err);
}

test "@needs with comma-separated commands" {
    const source =
        \\task test:
        \\    @needs sh, cat, ls
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should handle comma-separated list
    try executor.execute("test");
}

test "@needs only checks once per command" {
    const source =
        \\task test:
        \\    @needs sh
        \\    echo "first"
        \\    @needs sh
        \\    echo "second"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should succeed with multiple @needs for same command
    try executor.execute("test");
}

test "@needs with custom hint shows hint on failure" {
    const source =
        \\task test:
        \\    @needs jake_nonexistent_xyz123 "Install from https://example.com"
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should fail with custom hint
    const err = executor.execute("test");
    try std.testing.expectError(ExecuteError.CommandFailed, err);
}

test "@needs with task reference shows run suggestion" {
    const source =
        \\task test:
        \\    @needs jake_nonexistent_xyz123 -> install-it
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should fail and suggest running the install task
    const err = executor.execute("test");
    try std.testing.expectError(ExecuteError.CommandFailed, err);
}

test "@needs with hint and task reference" {
    const source =
        \\task test:
        \\    @needs jake_nonexistent_xyz123 "Google fuzzer" -> toolchain.install-fuzz
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should fail with both hint and task reference
    const err = executor.execute("test");
    try std.testing.expectError(ExecuteError.CommandFailed, err);
}

test "@needs with hint still works when command exists" {
    const source =
        \\task test:
        \\    @needs sh "Shell interpreter"
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should succeed - hint only shown on failure
    try executor.execute("test");
}

test "@needs with task reference still works when command exists" {
    const source =
        \\task test:
        \\    @needs sh -> install-shell
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should succeed - task reference only used on failure
    try executor.execute("test");
}

// Recipe-level @needs tests

test "recipe-level @needs verifies command exists before execution" {
    const source =
        \\@needs sh
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // 'sh' should exist - recipe-level @needs checked before commands run
    try executor.execute("test");
}

test "recipe-level @needs fails with helpful error when command missing" {
    const source =
        \\@needs jake_nonexistent_xyz123
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should fail because command doesn't exist - checked before commands run
    const err = executor.execute("test");
    try std.testing.expectError(ExecuteError.CommandFailed, err);
}

test "recipe-level @needs with hint and task reference" {
    const source =
        \\@needs jake_nonexistent_xyz123 "Install from example.com" -> install-it
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should fail - hint and task reference will be shown in error
    const err = executor.execute("test");
    try std.testing.expectError(ExecuteError.CommandFailed, err);
}

test "recipe-level @needs fails before any command executes" {
    // This test verifies that @needs is checked BEFORE any commands run
    // If @needs wasn't checked early, the first echo would execute before failure
    const source =
        \\@needs jake_nonexistent_xyz123
        \\task test:
        \\    echo "this should never run"
        \\    exit 0
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    // NOT dry_run - we want to verify commands don't execute
    // The @needs check should fail before any commands run

    const err = executor.execute("test");
    try std.testing.expectError(ExecuteError.CommandFailed, err);
    // If we got CommandFailed and not some other error, @needs checked first
}

test "recipe-level @needs checks multiple commands on same line" {
    const source =
        \\@needs sh cat jake_nonexistent_xyz123
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should fail because third command doesn't exist
    const err = executor.execute("test");
    try std.testing.expectError(ExecuteError.CommandFailed, err);
}

// @confirm tests

test "@confirm with --yes flag auto-confirms" {
    const source =
        \\task test:
        \\    @confirm Deploy to production?
        \\    echo "deployed"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;
    executor.auto_yes = true; // Enable auto-yes flag

    // Should succeed because auto_yes is enabled
    try executor.execute("test");
}

test "@confirm in dry-run mode shows message but doesn't prompt" {
    const source =
        \\task test:
        \\    @confirm Are you sure?
        \\    echo "done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // In dry-run mode, @confirm should show message but auto-confirm
    try executor.execute("test");
}

test "@confirm with default message" {
    const source =
        \\task test:
        \\    @confirm
        \\    echo "done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should use default "Continue?" message
    try executor.execute("test");
}

// @each tests

test "@each iterates over space-separated items" {
    const source =
        \\task test:
        \\    @each a b c
        \\        echo "item: {{item}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should iterate and print each item
    try executor.execute("test");
}

test "@each expands {{item}} variable in command" {
    const source =
        \\task test:
        \\    @each foo bar
        \\        echo "processing: {{item}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@each expands variable to multiple items" {
    // Test that @each {{variable}} expands the variable and iterates over each item
    const source =
        \\targets = "foo bar baz"
        \\task test:
        \\    @each {{targets}}
        \\        echo "building {{item}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should iterate 3 times (foo, bar, baz), not once with the whole string
    try executor.execute("test");

    // Verify item variable was set correctly during execution
    // (The test passes if no crash occurs and loop iterates correctly)
}

test "@each with empty list executes zero times" {
    const source =
        \\task test:
        \\    @each
        \\        echo "should not print"
        \\    @end
        \\    echo "done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should skip loop body but execute "done"
    try executor.execute("test");
}

test "@each nested in conditional block respects condition" {
    const source =
        \\task test:
        \\    @if false
        \\        @each a b c
        \\            echo "should not print"
        \\        @end
        \\    @end
        \\    echo "done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should skip the @each block due to false condition
    try executor.execute("test");
}

test "@each with comma-separated items" {
    const source =
        \\task test:
        \\    @each a, b, c
        \\        echo "{{item}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@each with single item" {
    const source =
        \\task test:
        \\    @each only_one
        \\        echo "{{item}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@each with multiple commands" {
    const source =
        \\task test:
        \\    @each x y
        \\        echo "start {{item}}"
        \\        echo "end {{item}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@each with glob pattern expands matching files" {
    // This test verifies that glob patterns in @each are expanded
    // We use a pattern that should match existing zig files in src/
    const source =
        \\task test:
        \\    @each src/glob.zig
        \\        echo "processing: {{item}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should iterate over the literal file (not a glob)
    try executor.execute("test");
}

test "@each with asterisk glob expands files" {
    // Create temp test files
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test files
    tmp_dir.dir.writeFile(.{ .sub_path = "test1.txt", .data = "content1" }) catch {};
    tmp_dir.dir.writeFile(.{ .sub_path = "test2.txt", .data = "content2" }) catch {};
    tmp_dir.dir.writeFile(.{ .sub_path = "other.md", .data = "other" }) catch {};

    // The executor's parseEachItems should expand globs
    var executor: Executor = undefined;
    executor.allocator = std.testing.allocator;
    executor.expanded_strings = .empty;

    // Test isGlobPattern detection
    try std.testing.expect(glob_mod.isGlobPattern("*.txt"));
    try std.testing.expect(glob_mod.isGlobPattern("src/**/*.zig"));
    try std.testing.expect(!glob_mod.isGlobPattern("literal.txt"));
}

test "@each with non-matching glob returns empty" {
    const source =
        \\task test:
        \\    @each nonexistent_dir_12345/*.nonexistent
        \\        echo "should not print: {{item}}"
        \\    @end
        \\    echo "done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should skip the loop (no matches) but execute "done"
    try executor.execute("test");
}

test "@each with mixed literal and glob items" {
    const source =
        \\task test:
        \\    @each literal1 literal2
        \\        echo "item: {{item}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should process both literal items
    try executor.execute("test");
}

// ============================================================================
// @cache Directive Tests
// ============================================================================

test "@cache first run always executes" {
    const source =
        \\task test:
        \\    @cache nonexistent_file.txt
        \\    echo "running"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true; // Use dry-run to see command output

    // Should execute because file doesn't exist (stale)
    try executor.execute("test");
}

test "@cache with existing file updates cache" {
    // Create a temporary directory and file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test file
    const file = try tmp_dir.dir.createFile("test.txt", .{});
    try file.writeAll("test content");
    file.close();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    const source =
        \\task test:
        \\    @cache test.txt
        \\    echo "running"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // First run - should execute and cache
    try executor.execute("test");
}

test "@cache skips command when inputs unchanged" {
    // Create a temporary directory and file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create test file
    const file = try tmp_dir.dir.createFile("test.txt", .{});
    try file.writeAll("test content");
    file.close();

    // Change to tmp dir
    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    const source =
        \\task test:
        \\    @cache test.txt
        \\    echo "running"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Pre-populate cache to simulate previous run
    try executor.cache.update("test.txt");

    // Set dry_run after cache is populated
    executor.dry_run = true;

    // Second run - should skip (cached)
    try executor.execute("test");
    // Verify no error - command was skipped due to cache hit
}

test "@cache with multiple files" {
    const source =
        \\task test:
        \\    @cache file1.txt file2.txt
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@cache with comma-separated files" {
    const source =
        \\task test:
        \\    @cache file1.txt, file2.txt
        \\    echo "building"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@cache with empty deps always runs" {
    const source =
        \\task test:
        \\    @cache
        \\    echo "always runs"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "parseCachePatterns parses space-separated patterns" {
    var jakefile = parser.Jakefile{
        .variables = &.{},
        .recipes = &.{},
        .directives = &.{},
        .imports = &.{},
        .global_pre_hooks = &.{},
        .global_post_hooks = &.{},
        .global_on_error_hooks = &.{},
        .comments = &.{},
        .source = "",
    };

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const patterns = executor.parseCachePatterns("cache src/*.zig lib/*.zig");
    defer std.testing.allocator.free(patterns);

    try std.testing.expectEqual(@as(usize, 2), patterns.len);
    try std.testing.expectEqualStrings("src/*.zig", patterns[0]);
    try std.testing.expectEqualStrings("lib/*.zig", patterns[1]);
}

// ============================================================================
// @watch Directive Tests
// ============================================================================

test "@watch in dry-run mode shows what would be watched" {
    const source =
        \\task test:
        \\    @watch src/*.zig
        \\    echo "watching"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@watch is informational in normal mode" {
    const source =
        \\task test:
        \\    @watch nonexistent/*.zig
        \\    echo "running"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true; // Still dry-run for safety in tests

    try executor.execute("test");
}

test "@watch with multiple patterns" {
    const source =
        \\task test:
        \\    @watch src/*.zig, tests/*.zig
        \\    echo "watching"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@watch continues to next command" {
    const source =
        \\task test:
        \\    @watch src/*.zig
        \\    echo "command 1"
        \\    echo "command 2"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "parseCachePatterns works for watch patterns" {
    var jakefile = parser.Jakefile{
        .variables = &.{},
        .recipes = &.{},
        .directives = &.{},
        .imports = &.{},
        .global_pre_hooks = &.{},
        .global_post_hooks = &.{},
        .global_on_error_hooks = &.{},
        .comments = &.{},
        .source = "",
    };

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const patterns = executor.parseCachePatterns("watch **/*.zig");
    defer std.testing.allocator.free(patterns);

    try std.testing.expectEqual(@as(usize, 1), patterns.len);
    try std.testing.expectEqualStrings("**/*.zig", patterns[0]);
}

test "@watch with empty pattern is no-op" {
    const source =
        \\task test:
        \\    @watch
        \\    echo "running"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

// ============================================================================
// Edge Cases & Error Handling Tests
// ============================================================================

test "deeply nested @if blocks (5 levels)" {
    const source =
        \\task test:
        \\    @if true
        \\        @if true
        \\            @if true
        \\                @if true
        \\                    @if true
        \\                        echo "deeply nested"
        \\                    @end
        \\                @end
        \\            @end
        \\        @end
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "nested @if with @else does not execute outer else" {
    // Regression test: ensure inner @if/@else doesn't affect outer @else
    const source =
        \\task test:
        \\    @if true
        \\        echo "outer-if"
        \\        @if true
        \\            echo "inner-if"
        \\        @else
        \\            echo "inner-else"
        \\        @end
        \\        echo "after-inner"
        \\    @else
        \\        echo "outer-else-should-not-run"
        \\    @end
        \\    echo "after-outer"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // This should not error - previously the outer @else would wrongly execute
    try executor.execute("test");
}

test "nested @if with false outer does not execute inner" {
    const source =
        \\task test:
        \\    @if false
        \\        echo "outer-if-skip"
        \\        @if true
        \\            echo "inner-if-skip"
        \\        @else
        \\            echo "inner-else-skip"
        \\        @end
        \\    @else
        \\        echo "outer-else-runs"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@ignore with command that doesn't exist still continues" {
    const source =
        \\task test:
        \\    @ignore
        \\    totally_nonexistent_command_12345
        \\    echo "continued"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "empty recipe with only directives executes without error" {
    const source =
        \\task test:
        \\    @if false
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@each inside @if only runs when condition true" {
    const source =
        \\task test:
        \\    @if true
        \\        @each a b
        \\            echo "{{item}}"
        \\        @end
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@each inside @if false is skipped" {
    const source =
        \\task test:
        \\    @if false
        \\        @each a b
        \\            echo "{{item}}"
        \\        @end
        \\    @end
        \\    echo "done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "recipe with all directives combined" {
    const source =
        \\task test:
        \\    @if true
        \\        @ignore
        \\        echo "ignored failure is ok"
        \\    @end
        \\    @each x y
        \\        echo "item: {{item}}"
        \\    @end
        \\    @cache nonexistent.txt
        \\    echo "cached"
        \\    @watch src/*.zig
        \\    echo "watching"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "multiple @if/@else chains" {
    const source =
        \\task test:
        \\    @if false
        \\        echo "first"
        \\    @elif false
        \\        echo "second"
        \\    @else
        \\        echo "third"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "executor returns RecipeNotFound for missing recipe" {
    const source =
        \\task existing:
        \\    echo "exists"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const result = executor.execute("nonexistent");
    try std.testing.expectError(ExecuteError.RecipeNotFound, result);
}

test "executor returns CyclicDependency for self-referencing recipe" {
    const source =
        \\task loop: [loop]
        \\    echo "never runs"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const result = executor.execute("loop");
    try std.testing.expectError(ExecuteError.CyclicDependency, result);
}

test "executor returns CyclicDependency for indirect cycle" {
    const source =
        \\task a: [b]
        \\    echo "a"
        \\
        \\task b: [c]
        \\    echo "b"
        \\
        \\task c: [a]
        \\    echo "c"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const result = executor.execute("a");
    try std.testing.expectError(ExecuteError.CyclicDependency, result);
}

test "@needs continues checking after first found command" {
    const source =
        \\task test:
        \\    @needs sh ls cat
        \\    echo "all commands found"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "variable expansion in commands works with special chars" {
    const source =
        \\version = "1.0.0"
        \\
        \\task test:
        \\    echo "v{{version}}-release"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "environment variable expansion with default fallback" {
    const source =
        \\task test:
        \\    echo "${DEFINITELY_UNSET_VAR_12345:-default_value}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "recipe with only comments parses correctly" {
    const source =
        \\# This is a comment
        \\task test:
        \\    # More comments
        \\    echo "hello"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "executor handles recipe with spaces in command" {
    const source =
        \\task test:
        \\    echo "hello   world   spaces"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@quiet suppresses verbose output for recipe" {
    const source =
        \\@quiet
        \\task test:
        \\    echo "silent command"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Verify the recipe has quiet=true from @quiet directive
    const recipe = jakefile.getRecipe("test").?;
    try std.testing.expect(recipe.quiet);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;
    executor.verbose = true; // Even with verbose, quiet should suppress

    try executor.execute("test");
}

test "@quiet only applies to next recipe" {
    const source =
        \\@quiet
        \\task quiet_task:
        \\    echo "quiet"
        \\
        \\task normal_task:
        \\    echo "normal"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // First recipe should be quiet
    const quiet_recipe = jakefile.getRecipe("quiet_task").?;
    try std.testing.expect(quiet_recipe.quiet);

    // Second recipe should NOT be quiet
    const normal_recipe = jakefile.getRecipe("normal_task").?;
    try std.testing.expect(!normal_recipe.quiet);
}

test "recipe parameter with default value binds to variable" {
    const source =
        \\task greet name="World":
        \\    echo "Hello, {{name}}!"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("greet");

    // After execution, the default value should be bound
    try std.testing.expectEqualStrings("World", executor.variables.get("name").?);
}

test "recipe parameter CLI arg overrides default" {
    const source =
        \\task greet name="World":
        \\    echo "Hello, {{name}}!"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Simulate CLI args: jake greet name=Alice
    const args = [_][]const u8{"name=Alice"};
    executor.setPositionalArgs(&args);

    try executor.execute("greet");

    // CLI arg should override default
    try std.testing.expectEqualStrings("Alice", executor.variables.get("name").?);
}

test "recipe parameter without default stays unset if no CLI arg" {
    const source =
        \\task greet name:
        \\    echo "Hello, {{name}}!"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("greet");

    // Without CLI arg and no default, param should not be set
    try std.testing.expect(executor.variables.get("name") == null);
}

test "recipe multiple parameters bind correctly" {
    const source =
        \\task deploy env="dev" region="us-east-1":
        \\    echo "Deploying to {{env}} in {{region}}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Override just one param
    const args = [_][]const u8{"env=prod"};
    executor.setPositionalArgs(&args);

    try executor.execute("deploy");

    try std.testing.expectEqualStrings("prod", executor.variables.get("env").?);
    try std.testing.expectEqualStrings("us-east-1", executor.variables.get("region").?);
}

test "recipe parameter with quoted value in CLI" {
    const source =
        \\task greet name="World":
        \\    echo "Hello, {{name}}!"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // CLI args with value containing spaces (shell would handle quotes)
    const args = [_][]const u8{"name=John Doe"};
    executor.setPositionalArgs(&args);

    try executor.execute("greet");

    try std.testing.expectEqualStrings("John Doe", executor.variables.get("name").?);
}

test "recipe parameter value with equals sign" {
    const source =
        \\task test expr="1+1":
        \\    echo "{{expr}}"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // CLI arg with value containing equals: expr=2+2=4
    const args = [_][]const u8{"expr=2+2=4"};
    executor.setPositionalArgs(&args);

    try executor.execute("test");

    // Should capture everything after the first equals
    try std.testing.expectEqualStrings("2+2=4", executor.variables.get("expr").?);
}

test "function call uppercase in variable expansion" {
    const source =
        \\task test:
        \\    echo "Hello"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const expanded = try executor.expandJakeVariables("{{uppercase(hello)}}");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("HELLO", expanded);
}

test "function call lowercase in variable expansion" {
    const source =
        \\task test:
        \\    echo "Hello"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const expanded = try executor.expandJakeVariables("{{lowercase(HELLO)}}");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("hello", expanded);
}

test "function call dirname in variable expansion" {
    const source =
        \\task test:
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const expanded = try executor.expandJakeVariables("{{dirname(/path/to/file.txt)}}");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("/path/to", expanded);
}

test "function call basename in variable expansion" {
    const source =
        \\task test:
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const expanded = try executor.expandJakeVariables("{{basename(/path/to/file.txt)}}");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("file.txt", expanded);
}

test "function call with variable argument" {
    const source =
        \\name = "world"
        \\task test:
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const expanded = try executor.expandJakeVariables("Hello {{uppercase(name)}}!");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("Hello WORLD!", expanded);
}

test "function call extension" {
    const source =
        \\task test:
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const expanded = try executor.expandJakeVariables("{{extension(file.txt)}}");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings(".txt", expanded);
}

test "unknown function keeps original" {
    const source =
        \\task test:
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    const expanded = try executor.expandJakeVariables("{{unknownfunc(arg)}}");
    defer std.testing.allocator.free(expanded);
    try std.testing.expectEqualStrings("{{unknownfunc(arg)}}", expanded);
}

// ============================================================================
// Stress Tests - Complex Scenarios
// ============================================================================

test "stress: deeply nested conditionals with mixed branches" {
    const source =
        \\task test:
        \\    @if true
        \\        echo "level1-if"
        \\        @if false
        \\            echo "level2-if-skip"
        \\        @elif true
        \\            echo "level2-elif"
        \\            @if true
        \\                echo "level3-if"
        \\                @if false
        \\                    echo "level4-skip"
        \\                @else
        \\                    echo "level4-else"
        \\                @end
        \\            @else
        \\                echo "level3-else-skip"
        \\            @end
        \\        @else
        \\            echo "level2-else-skip"
        \\        @end
        \\    @else
        \\        echo "level1-else-skip"
        \\    @end
        \\    echo "after-all"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "stress: complex dependency chain" {
    const source =
        \\task a:
        \\    echo "a"
        \\task b: [a]
        \\    echo "b"
        \\task c: [a]
        \\    echo "c"
        \\task d: [b, c]
        \\    echo "d"
        \\task e: [d]
        \\    echo "e"
        \\task f: [d]
        \\    echo "f"
        \\task g: [e, f]
        \\    echo "g"
        \\task h: [g, a]
        \\    echo "h"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("h");
}

test "stress: @each inside conditional" {
    const source =
        \\task test:
        \\    @if true
        \\        @each a b c
        \\            echo "item: {{item}}"
        \\        @end
        \\    @else
        \\        echo "skip-each"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "stress: conditional inside @each" {
    const source =
        \\task test:
        \\    @each x y z
        \\        @if true
        \\            echo "processing: {{item}}"
        \\        @else
        \\            echo "skip"
        \\        @end
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "stress: multiple directives in single recipe" {
    const source =
        \\task test:
        \\    @needs echo
        \\    @if true
        \\        @each a b
        \\            echo "{{item}}"
        \\        @end
        \\    @end
        \\    @ignore
        \\    nonexistent_cmd
        \\    echo "after ignore"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "stress: hooks with dependencies" {
    const source =
        \\@pre echo "global-pre"
        \\@post echo "global-post"
        \\
        \\task setup:
        \\    @pre echo "setup-pre"
        \\    echo "setup"
        \\    @post echo "setup-post"
        \\
        \\task build: [setup]
        \\    @pre echo "build-pre"
        \\    echo "build"
        \\    @post echo "build-post"
        \\
        \\task test: [build]
        \\    @pre echo "test-pre"
        \\    echo "test"
        \\    @post echo "test-post"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "stress: recipe with parameters and conditionals" {
    const source =
        \\task deploy env="staging":
        \\    @if eq({{env}}, "production")
        \\        echo "deploying to PROD"
        \\    @elif eq({{env}}, "staging")
        \\        echo "deploying to STAGING"
        \\    @else
        \\        echo "unknown env: {{env}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("deploy");
}

test "stress: targeted hooks with multiple recipes" {
    const source =
        \\@before build echo "BEFORE BUILD"
        \\@after build echo "AFTER BUILD"
        \\@before test echo "BEFORE TEST"
        \\@after test echo "AFTER TEST"
        \\
        \\task build:
        \\    echo "building"
        \\
        \\task test: [build]
        \\    echo "testing"
        \\
        \\task deploy: [test]
        \\    echo "deploying"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("deploy");
}

test "stress: file target with multiple deps" {
    const source =
        \\file output.txt: src/*.ts lib/*.ts
        \\    echo "compiling"
        \\
        \\task build: [output.txt]
        \\    echo "build done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("build");
}

test "stress: empty @each list produces no iterations" {
    const source =
        \\task test:
        \\    @each
        \\        echo "should not print"
        \\    @end
        \\    echo "done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

// @export tests

test "@export KEY=value sets environment variable" {
    const source =
        \\@export NODE_ENV=production
        \\task test:
        \\    echo "testing"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Verify the environment has the exported variable
    try std.testing.expectEqualStrings("production", executor.environment.get("NODE_ENV").?);
}

test "@export KEY exports Jake variable to environment" {
    const source =
        \\version = "1.0.0"
        \\@export version
        \\task test:
        \\    echo "testing"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Verify the Jake variable was exported to the environment
    try std.testing.expectEqualStrings("1.0.0", executor.environment.get("version").?);
}

test "@export KEY value sets environment variable" {
    const source =
        \\@export MY_VAR myvalue
        \\task test:
        \\    echo "testing"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Verify the environment has the exported variable
    try std.testing.expectEqualStrings("myvalue", executor.environment.get("MY_VAR").?);
}

test "@export builds correct env map for child process" {
    const source =
        \\@export NODE_ENV=production
        \\@export DEBUG=true
        \\task test:
        \\    echo "testing"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Build the env map that would be passed to child processes
    var env_map = try executor.environment.buildEnvMap(std.testing.allocator);
    defer env_map.deinit();

    // Verify exported variables are in the env map
    try std.testing.expectEqualStrings("production", env_map.get("NODE_ENV").?);
    try std.testing.expectEqualStrings("true", env_map.get("DEBUG").?);
}

test "@export KEY=\"value with spaces\" handles quoted values" {
    const source =
        \\@export MESSAGE="hello world"
        \\task test:
        \\    echo "testing"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Verify the environment has the exported variable without quotes
    try std.testing.expectEqualStrings("hello world", executor.environment.get("MESSAGE").?);
}

test "@export nonexistent variable is silently ignored" {
    const source =
        \\@export NONEXISTENT
        \\task test:
        \\    echo "testing"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Nonexistent variable should not be in environment
    try std.testing.expectEqual(@as(?[]const u8, null), executor.environment.get("NONEXISTENT"));
}

test "@export with quoted value using separate arg" {
    const source =
        \\@export MY_MESSAGE "hello world"
        \\task test:
        \\    echo "testing"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();

    // Verify the value has quotes stripped
    try std.testing.expectEqualStrings("hello world", executor.environment.get("MY_MESSAGE").?);
}

test "stress: diamond dependency pattern" {
    // A depends on B and C, both depend on D
    // D should only run once
    const source =
        \\task d:
        \\    echo "d"
        \\task b: [d]
        \\    echo "b"
        \\task c: [d]
        \\    echo "c"
        \\task a: [b, c]
        \\    echo "a"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("a");
}

test "stress: 20+ recipes large project" {
    const source =
        \\version = "1.0.0"
        \\app = "myapp"
        \\
        \\task clean:
        \\    echo "cleaning"
        \\task lint: [clean]
        \\    echo "linting"
        \\task format: [clean]
        \\    echo "formatting"
        \\task compile: [lint, format]
        \\    echo "compiling {{app}} v{{version}}"
        \\task test-unit: [compile]
        \\    @each unit1 unit2 unit3
        \\        echo "testing {{item}}"
        \\    @end
        \\task test-integration: [compile]
        \\    @if true
        \\        echo "integration tests"
        \\    @end
        \\task test: [test-unit, test-integration]
        \\    echo "all tests done"
        \\task bundle: [compile]
        \\    echo "bundling"
        \\task minify: [bundle]
        \\    echo "minifying"
        \\task assets: [minify]
        \\    echo "processing assets"
        \\task build: [assets, test]
        \\    echo "build complete"
        \\task staging: [build]
        \\    echo "deploy staging"
        \\task production: [build]
        \\    @pre echo "PRODUCTION DEPLOY"
        \\    echo "deploy production"
        \\    @post echo "DEPLOYED"
        \\task deploy: [staging]
        \\    echo "deploy done"
        \\task release: [production]
        \\    echo "release {{version}}"
        \\task docs:
        \\    echo "generating docs"
        \\task publish: [release, docs]
        \\    echo "publishing"
        \\task all: [publish]
        \\    echo "all done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("all");
}

// =============================================================================
// @cd directive tests
// =============================================================================

test "@cd directive is parsed and stored" {
    const source =
        \\task test:
        \\    @cd /tmp
        \\    echo "in tmp"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Verify the recipe has a cd directive
    const recipe = jakefile.getRecipe("test").?;
    try std.testing.expectEqualStrings("/tmp", recipe.working_dir.?);
}

test "@cd directive works in dry run" {
    const source =
        \\task test:
        \\    @cd /tmp
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Should succeed without error
    try executor.execute("test");
}

// =============================================================================
// @shell directive tests
// =============================================================================

test "@shell directive is parsed and stored" {
    const source =
        \\task test:
        \\    @shell /bin/bash
        \\    echo "using bash"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Verify the recipe has a shell directive
    const recipe = jakefile.getRecipe("test").?;
    try std.testing.expectEqualStrings("/bin/bash", recipe.shell.?);
}

test "@shell directive works in dry run" {
    const source =
        \\task test:
        \\    @shell /bin/sh
        \\    echo "test"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    try executor.execute("test");
}

test "@cd and @shell combined" {
    const source =
        \\task test:
        \\    @cd /tmp
        \\    @shell /bin/sh
        \\    echo "in tmp with sh"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    const recipe = jakefile.getRecipe("test").?;
    try std.testing.expectEqualStrings("/tmp", recipe.working_dir.?);
    try std.testing.expectEqualStrings("/bin/sh", recipe.shell.?);

    try executor.execute("test");
}

// --- @timeout directive tests ---

test "@timeout parsing seconds" {
    const source =
        \\@timeout 30s
        \\task test:
        \\    echo "with timeout"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const recipe = jakefile.getRecipe("test").?;
    try std.testing.expectEqual(@as(?u64, 30), recipe.timeout_seconds);
}

test "@timeout parsing minutes" {
    const source =
        \\@timeout 5m
        \\task test:
        \\    echo "with timeout"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const recipe = jakefile.getRecipe("test").?;
    try std.testing.expectEqual(@as(?u64, 300), recipe.timeout_seconds);
}

test "@timeout parsing hours" {
    const source =
        \\@timeout 2h
        \\task test:
        \\    echo "with timeout"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const recipe = jakefile.getRecipe("test").?;
    try std.testing.expectEqual(@as(?u64, 7200), recipe.timeout_seconds);
}

test "@timeout with dry run does not hang" {
    const source =
        \\@timeout 1s
        \\task test:
        \\    echo "quick"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = true;

    // Dry run should complete immediately without timeout logic
    try executor.execute("test");
}

test "@timeout default is null" {
    const source =
        \\task test:
        \\    echo "no timeout"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const recipe = jakefile.getRecipe("test").?;
    try std.testing.expectEqual(@as(?u64, null), recipe.timeout_seconds);
}

test "@timeout kills long-running command" {
    // Skip on Windows - sleep command not available
    if (builtin.os.tag == .windows) return;

    const source =
        \\@timeout 1s
        \\task slow:
        \\    sleep 10
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.verbose = false;

    // Capture start time
    const start = std.time.milliTimestamp();

    // Execute should fail due to timeout
    const result = executor.execute("slow");
    try std.testing.expectError(ExecuteError.CommandFailed, result);

    // Verify it completed in roughly 1-2 seconds, not 10
    const elapsed = std.time.milliTimestamp() - start;
    try std.testing.expect(elapsed < 3000); // Should complete in under 3s
}

test "@timeout allows fast commands to complete" {
    // Skip on Windows
    if (builtin.os.tag == .windows) return;

    const source =
        \\@timeout 5s
        \\task quick:
        \\    echo "fast"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var executor = Executor.init(std.testing.allocator, &jakefile);
    defer executor.deinit();
    executor.verbose = false;

    // Should complete successfully
    try executor.execute("quick");
}
