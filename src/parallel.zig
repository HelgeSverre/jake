//! Thread pool for parallel recipe execution (-j N).
//!
//! This module provides parallel execution of recipes by:
// 1. Building a dependency graph from recipes
// 2. Identifying recipes that can run in parallel (no dependencies on each other)
// 3. Using Zig's std.Thread to run them concurrently
// 4. Collecting and merging results with synchronized output

const std = @import("std");
const builtin = @import("builtin");
const compat = @import("compat.zig");
const parser = @import("parser.zig");
const executor_mod = @import("executor.zig");
const cache_mod = @import("cache.zig");
const JakefileIndex = @import("jakefile_index.zig").JakefileIndex;
const color_mod = @import("color.zig");
const context_mod = @import("context.zig");
const system = @import("system.zig");

const Jakefile = parser.Jakefile;
const Recipe = parser.Recipe;
const Executor = executor_mod.Executor;
const ExecuteError = executor_mod.ExecuteError;
const Context = context_mod.Context;

fn printParallelWarning(prefix: []const u8, err: anyerror) void {
    const stderr = compat.getStdErr();
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "warning: {s}: {s}\n", .{ prefix, @errorName(err) }) catch return;
    stderr.writeAll(msg) catch {};
}

/// Dependency graph node
const GraphNode = struct {
    recipe: *const Recipe,
    dependencies: std.ArrayListUnmanaged(usize),
    dependents: std.ArrayListUnmanaged(usize),
    in_degree: usize, // Number of unfinished dependencies
    state: State,

    const State = enum {
        pending,
        ready, // All dependencies satisfied
        running,
        completed,
        failed,
    };
};

/// Parallel executor that runs independent recipes concurrently
pub const ParallelExecutor = struct {
    allocator: std.mem.Allocator,
    jakefile: *const Jakefile,
    index: *const JakefileIndex,
    owned_index: ?*JakefileIndex = null,
    nodes: std.ArrayListUnmanaged(GraphNode),
    name_to_index: std.StringHashMap(usize),
    thread_count: usize,
    dry_run: bool,
    verbose: bool,
    cache: cache_mod.Cache,
    owns_cache: bool, // When false, caller is responsible for saving/merging
    color: color_mod.Color,
    theme: color_mod.Theme,
    ctx: Context,

    // Synchronization primitives
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    output_mutex: std.Thread.Mutex,
    cache_mutex: std.Thread.Mutex,
    prompt_mutex: std.Thread.Mutex,

    // Execution state
    ready_queue: std.ArrayListUnmanaged(usize),
    completed_count: usize,
    failed: bool,
    first_error: ?ExecuteError,
    is_tty: bool, // Whether stderr is a TTY (for animated output)
    tasks_run: usize, // Successfully completed tasks
    tasks_failed: usize, // Failed tasks
    exec_start_time: i128, // Start time for summary

    pub fn init(allocator: std.mem.Allocator, jakefile: *const Jakefile, thread_count: usize) !ParallelExecutor {
        const owned_index = try allocator.create(JakefileIndex);
        owned_index.* = JakefileIndex.build(allocator, jakefile) catch |err| {
            allocator.destroy(owned_index);
            return err;
        };
        var exec = initInternal(allocator, jakefile, owned_index, thread_count, null);
        exec.owned_index = owned_index;
        exec.index = owned_index;
        return exec;
    }

    pub fn initWithIndex(allocator: std.mem.Allocator, jakefile: *const Jakefile, index: *const JakefileIndex, thread_count: usize) ParallelExecutor {
        return initInternal(allocator, jakefile, index, thread_count, null);
    }

    pub fn initWithIndexAndContext(
        allocator: std.mem.Allocator,
        jakefile: *const Jakefile,
        index: *const JakefileIndex,
        ctx: *const Context,
        thread_count: usize,
    ) ParallelExecutor {
        return initInternal(allocator, jakefile, index, thread_count, ctx);
    }

    fn initInternal(
        allocator: std.mem.Allocator,
        jakefile: *const Jakefile,
        index: *const JakefileIndex,
        thread_count: usize,
        ctx: ?*const Context,
    ) ParallelExecutor {
        var cache = cache_mod.Cache.init(allocator);
        cache.load() catch |err| {
            printParallelWarning("failed to load cache", err);
        };

        return .{
            .allocator = allocator,
            .jakefile = jakefile,
            .index = index,
            .nodes = .empty,
            .name_to_index = std.StringHashMap(usize).init(allocator),
            .thread_count = if (thread_count == 0) getDefaultThreadCount() else thread_count,
            .dry_run = false,
            .verbose = false,
            .cache = cache,
            .owns_cache = ctx == null, // When created with context, caller manages cache
            .color = color_mod.init(),
            .theme = color_mod.Theme.init(),
            .ctx = if (ctx) |context| context.* else .{
                .color = color_mod.Color{ .enabled = false },
            },
            .mutex = .{},
            .condition = .{},
            .output_mutex = .{},
            .cache_mutex = .{},
            .prompt_mutex = .{},
            .ready_queue = .empty,
            .completed_count = 0,
            .failed = false,
            .first_error = null,
            .is_tty = compat.getStdErr().isTty(),
            .tasks_run = 0,
            .tasks_failed = 0,
            .exec_start_time = 0,
        };
    }

    pub fn deinit(self: *ParallelExecutor) void {
        for (self.nodes.items) |*node| {
            node.dependencies.deinit(self.allocator);
            node.dependents.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
        self.name_to_index.deinit();
        self.ready_queue.deinit(self.allocator);
        if (self.owns_cache) {
            self.cache.save() catch {};
        }
        self.cache.deinit();

        if (self.owned_index) |owned| {
            owned.deinit();
            self.allocator.destroy(owned);
            self.owned_index = null;
        }
    }

    /// Get the default number of threads (CPU count)
    fn getDefaultThreadCount() usize {
        return std.Thread.getCpuCount() catch 4;
    }

    /// Build the dependency graph for a target recipe and all its dependencies
    pub fn buildGraph(self: *ParallelExecutor, target: []const u8) !void {
        try self.addRecipeToGraph(target, null);
        try self.calculateInDegrees();
        try self.initializeReadyQueue();
    }

    fn appendUniqueIndex(
        self: *ParallelExecutor,
        list: *std.ArrayListUnmanaged(usize),
        idx: usize,
    ) ExecuteError!void {
        for (list.items) |existing| {
            if (existing == idx) return;
        }
        list.append(self.allocator, idx) catch return ExecuteError.OutOfMemory;
    }

    fn findRecipeByOutput(self: *ParallelExecutor, output: []const u8) ?*const Recipe {
        for (self.jakefile.recipes) |*recipe| {
            if (recipe.output) |recipe_output| {
                if (std.mem.eql(u8, recipe_output, output)) {
                    return recipe;
                }
            }
        }
        return null;
    }

    /// Recursively add a recipe and its dependencies to the graph
    fn addRecipeToGraph(self: *ParallelExecutor, name: []const u8, dependent_idx: ?usize) ExecuteError!void {
        // Check if already in graph
        if (self.name_to_index.get(name)) |existing_idx| {
            // Add edge from existing to dependent
            if (dependent_idx) |dep_idx| {
                try self.appendUniqueIndex(&self.nodes.items[existing_idx].dependents, dep_idx);
            }
            return;
        }

        // Find the recipe
        const recipe = self.index.getRecipe(name) orelse {
            return ExecuteError.RecipeNotFound;
        };

        // Create node
        const node_idx = self.nodes.items.len;
        self.nodes.append(self.allocator, .{
            .recipe = recipe,
            .dependencies = .empty,
            .dependents = .empty,
            .in_degree = 0,
            .state = .pending,
        }) catch return ExecuteError.OutOfMemory;

        self.name_to_index.put(name, node_idx) catch return ExecuteError.OutOfMemory;

        // Add edge to dependent
        if (dependent_idx) |dep_idx| {
            try self.appendUniqueIndex(&self.nodes.items[node_idx].dependents, dep_idx);
        }

        // Recursively add dependencies
        for (recipe.dependencies) |dep_name| {
            try self.addRecipeToGraph(dep_name, node_idx);
            // Add the dependency index to our dependencies list
            if (self.name_to_index.get(dep_name)) |dep_node_idx| {
                try self.appendUniqueIndex(&self.nodes.items[node_idx].dependencies, dep_node_idx);
            }
        }

        // File targets also depend on any recipes that produce their file dependencies.
        if (recipe.kind == .file) {
            for (recipe.file_deps) |file_dep| {
                if (self.findRecipeByOutput(file_dep)) |producing_recipe| {
                    try self.addRecipeToGraph(producing_recipe.name, node_idx);
                    if (self.name_to_index.get(producing_recipe.name)) |dep_node_idx| {
                        try self.appendUniqueIndex(&self.nodes.items[node_idx].dependencies, dep_node_idx);
                    }
                }
            }
        }
    }

    /// Calculate in-degrees for all nodes (number of dependencies)
    fn calculateInDegrees(self: *ParallelExecutor) !void {
        for (self.nodes.items) |*node| {
            node.in_degree = node.dependencies.items.len;
        }
    }

    /// Initialize the ready queue with nodes that have no dependencies
    fn initializeReadyQueue(self: *ParallelExecutor) !void {
        for (self.nodes.items, 0..) |*node, idx| {
            if (node.in_degree == 0) {
                node.state = .ready;
                try self.ready_queue.append(self.allocator, idx);
            }
        }
    }

    /// Check if there's a cyclic dependency
    pub fn detectCycle(self: *ParallelExecutor) bool {
        // Use DFS coloring: white (0) = unvisited, gray (1) = in-progress, black (2) = done
        const colors = self.allocator.alloc(u8, self.nodes.items.len) catch return false;
        defer self.allocator.free(colors);
        @memset(colors, 0);

        for (0..self.nodes.items.len) |i| {
            if (colors[i] == 0) {
                if (self.dfsDetectCycle(i, colors)) {
                    return true;
                }
            }
        }
        return false;
    }

    fn dfsDetectCycle(self: *ParallelExecutor, node_idx: usize, colors: []u8) bool {
        colors[node_idx] = 1; // Mark as in-progress

        for (self.nodes.items[node_idx].dependencies.items) |dep_idx| {
            if (colors[dep_idx] == 1) {
                return true; // Back edge found, cycle exists
            }
            if (colors[dep_idx] == 0) {
                if (self.dfsDetectCycle(dep_idx, colors)) {
                    return true;
                }
            }
        }

        colors[node_idx] = 2; // Mark as done
        return false;
    }

    /// Execute all recipes in the graph with parallel execution
    pub fn execute(self: *ParallelExecutor) ExecuteError!void {
        if (self.nodes.items.len == 0) {
            return;
        }

        // Check for cycles
        if (self.detectCycle()) {
            return ExecuteError.CyclicDependency;
        }

        // Reset state
        self.exec_start_time = std.time.nanoTimestamp();
        self.completed_count = 0;
        self.tasks_run = 0;
        self.tasks_failed = 0;
        self.failed = false;
        self.first_error = null;

        // Determine actual thread count (don't spawn more threads than ready tasks)
        const max_threads = @min(self.thread_count, self.nodes.items.len);

        if (max_threads <= 1 or self.dry_run) {
            // Single-threaded execution for simplicity in dry-run or single thread
            self.executeSequential() catch |err| {
                self.printExecutionSummary();
                return err;
            };
            self.printExecutionSummary();
            return;
        }

        // Spawn worker threads
        var threads: std.ArrayListUnmanaged(std.Thread) = .empty;
        defer threads.deinit(self.allocator);

        for (0..max_threads) |_| {
            const thread = std.Thread.spawn(.{}, workerThread, .{self}) catch {
                // If we can't spawn a thread, continue with fewer
                break;
            };
            threads.append(self.allocator, thread) catch break;
        }

        // Wait for all threads to complete
        for (threads.items) |thread| {
            thread.join();
        }

        // Print summary
        self.printExecutionSummary();

        // Check if any recipe failed
        if (self.failed) {
            if (self.first_error) |err| {
                return err;
            }
            return ExecuteError.CommandFailed;
        }
    }

    /// Worker thread function
    fn workerThread(self: *ParallelExecutor) void {
        while (true) {
            // Get next ready task
            const task_idx = self.getNextTask() orelse {
                // No more tasks
                break;
            };

            // Execute the task
            const success = self.executeNode(task_idx);

            // Mark as complete and update dependents
            self.completeTask(task_idx, success);
        }
    }

    /// Get the next ready task (thread-safe)
    fn getNextTask(self: *ParallelExecutor) ?usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (true) {
            // Check if we're done
            if (self.completed_count >= self.nodes.items.len or self.failed) {
                return null;
            }

            // Check if there's a ready task
            if (self.ready_queue.items.len > 0) {
                const idx = self.ready_queue.pop().?;
                self.nodes.items[idx].state = .running;
                return idx;
            }

            // Wait for a task to become ready
            self.condition.wait(&self.mutex);
        }
    }

    /// Execute a single node
    fn executeNode(self: *ParallelExecutor, node_idx: usize) bool {
        const node = &self.nodes.items[node_idx];
        const recipe = node.recipe;
        const task_start_time_ms = std.time.milliTimestamp();

        self.ctx.emitEvent(.{ .task_start = .{
            .name = recipe.name,
            .deps = recipe.dependencies,
        } });

        // Check OS constraints - skip recipe if not for current OS
        if (shouldSkipForOs(recipe)) {
            const current_os = getCurrentOsString();
            self.printSynchronized("jake: skipping '{s}' (not for {s})\n", .{ recipe.name, current_os });
            const duration_ms: u64 = @intCast(@max(0, std.time.milliTimestamp() - task_start_time_ms));
            self.ctx.emitEvent(.{ .task_complete = .{
                .name = recipe.name,
                .success = true,
                .duration_ms = duration_ms,
            } });
            return true; // Success (skipped)
        }

        // Check recipe-level @needs requirements before running any commands
        if (recipe.needs.len > 0) {
            if (!self.checkRecipeLevelNeeds(recipe)) {
                const duration_ms: u64 = @intCast(@max(0, std.time.milliTimestamp() - task_start_time_ms));
                self.ctx.emitEvent(.{ .task_complete = .{
                    .name = recipe.name,
                    .success = false,
                    .duration_ms = duration_ms,
                } });
                return false;
            }
        }

        // Check recipe-level @require environment variables
        if (recipe.requires.len > 0 and !self.dry_run) {
            if (!self.checkRecipeRequires(recipe)) {
                const duration_ms: u64 = @intCast(@max(0, std.time.milliTimestamp() - task_start_time_ms));
                self.ctx.emitEvent(.{ .task_complete = .{
                    .name = recipe.name,
                    .success = false,
                    .duration_ms = duration_ms,
                } });
                return false;
            }
        }

        // Check if file target needs rebuilding
        if (recipe.kind == .file) {
            const needs_run = self.checkFileTarget(recipe) catch true;
            if (!needs_run) {
                if (self.verbose) {
                    self.printSynchronized("{s}jake: '{s}' is up to date{s}\n", .{ self.color.muted(), recipe.name, self.color.reset() });
                }
                const duration_ms: u64 = @intCast(@max(0, std.time.milliTimestamp() - task_start_time_ms));
                self.ctx.emitEvent(.{ .task_complete = .{
                    .name = recipe.name,
                    .success = true,
                    .duration_ms = duration_ms,
                } });
                return true;
            }
        }

        // Print recipe header and capture start time
        const start_time = std.time.nanoTimestamp();
        if (self.dry_run) {
            // v4 format: use ○ for dry-run (no completion line)
            self.printSynchronized("   {s} {f}\n", .{ self.theme.pendingSymbol(), self.theme.recipeHeader(recipe.name) });
        } else {
            self.printSynchronized("{s} {f}\n", .{ self.theme.arrowSymbol(), self.theme.recipeHeader(recipe.name) });
        }

        if (!self.executeRecipeWithWorker(recipe)) {
            if (!self.dry_run) {
                self.printCompletionStatus(recipe.name, false, start_time);
            }
            self.incrementTasksFailed();
            const duration_ms: u64 = @intCast(@max(0, std.time.milliTimestamp() - task_start_time_ms));
            self.ctx.emitEvent(.{ .task_complete = .{
                .name = recipe.name,
                .success = false,
                .duration_ms = duration_ms,
            } });
            return false;
        }

        // Update cache for file targets (thread-safe). Record both the output
        // and every dependency, mirroring the sequential path — otherwise deps
        // are never cached and file targets always rebuild (jake#17).
        if (recipe.kind == .file) {
            self.cache_mutex.lock();
            defer self.cache_mutex.unlock();
            if (recipe.output) |output| {
                self.cache.update(output) catch {};
            }
            for (recipe.file_deps) |dep| {
                self.cache.updatePattern(dep) catch {};
            }
        }

        if (!self.dry_run) {
            self.printCompletionStatus(recipe.name, true, start_time);
        }
        self.incrementTasksRun();
        const duration_ms: u64 = @intCast(@max(0, std.time.milliTimestamp() - task_start_time_ms));
        self.ctx.emitEvent(.{ .task_complete = .{
            .name = recipe.name,
            .success = true,
            .duration_ms = duration_ms,
        } });
        return true;
    }

    const OutputCallbackContext = struct {
        executor: *ParallelExecutor,
    };

    fn outputCallback(ctx: *anyopaque, line: []const u8, is_stderr: bool) void {
        const cb: *OutputCallbackContext = @ptrCast(@alignCast(ctx));
        cb.executor.output_mutex.lock();
        defer cb.executor.output_mutex.unlock();

        const output = if (is_stderr) compat.getStdErr() else compat.getStdOut();
        output.writeAll(line) catch {};
        output.writeAll("\n") catch {};
    }

    fn executeRecipeWithWorker(self: *ParallelExecutor, recipe: *const Recipe) bool {
        var worker_ctx = self.ctx;
        worker_ctx.jobs = 0;
        worker_ctx.watch_mode = false;
        worker_ctx.output_callback = outputCallback;

        var output_ctx = OutputCallbackContext{ .executor = self };
        worker_ctx.output_callback_ctx = &output_ctx;

        var worker = Executor.initWithIndex(self.allocator, self.jakefile, self.index) catch |err| {
            self.rememberError(switch (err) {
                error.OutOfMemory => ExecuteError.OutOfMemory,
                else => ExecuteError.CommandFailed,
            });
            return false;
        };
        worker.ctx = &worker_ctx;
        worker.color = self.color;
        worker.theme = self.theme;
        worker.hook_runner.color = self.color;
        worker.hook_runner.theme = self.theme;

        // Clone the shared cache into an isolated snapshot so the worker can read/write
        // without holding cache_mutex during the entire recipe execution. Changes are
        // merged back under the lock after execution completes.
        const cache_snapshot = blk: {
            self.cache_mutex.lock();
            defer self.cache_mutex.unlock();
            break :blk self.cache.clone(self.allocator);
        };
        const snapshot = cache_snapshot catch {
            self.rememberError(ExecuteError.OutOfMemory);
            worker.deinitWithoutSavingCache();
            return false;
        };

        worker.cache.deinit();
        worker.cache.* = snapshot;
        defer worker.deinitWithoutSavingCache();

        const needs_prompt = !worker_ctx.dry_run and !worker_ctx.auto_yes and recipeUsesDirective(recipe, .confirm);
        if (needs_prompt) {
            self.prompt_mutex.lock();
            defer self.prompt_mutex.unlock();
        }

        worker.executeRecipeBody(recipe.name, recipe) catch |err| {
            self.rememberError(err);
            return false;
        };

        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        self.cache.mergeFrom(worker.cache) catch {
            self.rememberError(ExecuteError.OutOfMemory);
            return false;
        };

        return true;
    }

    /// Thread-safe increment of tasks_run counter
    fn incrementTasksRun(self: *ParallelExecutor) void {
        self.output_mutex.lock();
        defer self.output_mutex.unlock();
        self.tasks_run += 1;
    }

    /// Thread-safe increment of tasks_failed counter
    fn incrementTasksFailed(self: *ParallelExecutor) void {
        self.output_mutex.lock();
        defer self.output_mutex.unlock();
        self.tasks_failed += 1;
    }

    fn rememberError(self: *ParallelExecutor, err: ExecuteError) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.first_error == null) {
            self.first_error = err;
        }
    }

    /// Check if a command exists in PATH
    fn commandExists(cmd: []const u8) bool {
        return system.commandExists(cmd);
    }

    /// Check recipe-level @needs requirements before running any commands
    fn checkRecipeLevelNeeds(self: *ParallelExecutor, recipe: *const Recipe) bool {
        for (recipe.needs) |req| {
            if (!commandExists(req.command)) {
                self.printSynchronized("{s}recipe '{s}' requires '{s}' but it's not installed\n", .{ self.color.errPrefix(), recipe.name, req.command });

                // Show hint if provided
                if (req.hint) |hint| {
                    self.printSynchronized("  hint: {s}\n", .{hint});
                }

                // Show install task suggestion if provided
                if (req.install_task) |task| {
                    self.printSynchronized("  run: jake {s}\n", .{task});
                }

                return false;
            }
        }
        return true;
    }

    /// Validate a recipe's @require environment variables (parallel analogue of
    /// Executor.checkRecipeRequires). Uses the process environment, which is
    /// where @dotenv/@export vars are visible to spawned recipes.
    fn checkRecipeRequires(self: *ParallelExecutor, recipe: *const Recipe) bool {
        for (recipe.requires) |var_name| {
            if (std.process.getEnvVarOwned(self.allocator, var_name)) |value| {
                self.allocator.free(value);
            } else |_| {
                self.printSynchronized("{s}Required environment variable '{s}' is not set\n", .{ self.color.errPrefix(), var_name });
                self.printSynchronized("  hint: recipe '{s}' needs it — set it in your shell or add it to .env\n", .{recipe.name});
                return false;
            }
        }
        return true;
    }

    fn checkFileTarget(self: *ParallelExecutor, recipe: *const Recipe) !bool {
        const output = recipe.output orelse return true;

        std.fs.cwd().access(output, .{}) catch {
            return true; // Output doesn't exist
        };

        // Thread-safe cache access
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();

        for (recipe.file_deps) |dep| {
            if (try self.cache.isGlobStale(dep)) {
                return true;
            }
        }

        return false;
    }

    /// Mark a task as complete and update dependents (thread-safe)
    fn completeTask(self: *ParallelExecutor, node_idx: usize, success: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (success) {
            self.nodes.items[node_idx].state = .completed;
        } else {
            self.nodes.items[node_idx].state = .failed;
            self.failed = true;
            if (self.first_error == null) {
                self.first_error = ExecuteError.CommandFailed;
            }
        }

        self.completed_count += 1;

        // Update dependents
        if (success) {
            for (self.nodes.items[node_idx].dependents.items) |dependent_idx| {
                const dependent = &self.nodes.items[dependent_idx];
                dependent.in_degree -= 1;
                if (dependent.in_degree == 0 and dependent.state == .pending) {
                    dependent.state = .ready;
                    self.ready_queue.append(self.allocator, dependent_idx) catch {
                        dependent.state = .failed;
                        self.failed = true;
                        if (self.first_error == null) {
                            self.first_error = ExecuteError.OutOfMemory;
                        }
                        self.condition.broadcast();
                        return;
                    };
                }
            }
        }

        // Wake up waiting threads
        self.condition.broadcast();
    }

    /// Print a message with proper synchronization
    fn printSynchronized(self: *ParallelExecutor, comptime fmt: []const u8, args: anytype) void {
        self.output_mutex.lock();
        defer self.output_mutex.unlock();

        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        compat.getStdErr().writeAll(msg) catch {};
    }

    /// Print completion status with timing (v4 format: "   ✓ name     1.82s")
    fn printCompletionStatus(self: *ParallelExecutor, name: []const u8, success: bool, start_time: i128) void {
        const end_time = std.time.nanoTimestamp();
        const duration_ns = end_time - start_time;
        const duration_ms = @divFloor(duration_ns, 1_000_000);
        const duration_s = @as(f64, @floatFromInt(duration_ms)) / 1000.0;

        self.output_mutex.lock();
        defer self.output_mutex.unlock();

        const stderr = compat.getStdErr();
        var buf: [32]u8 = undefined;
        const duration_str = std.fmt.bufPrint(&buf, "{d:.2}s", .{duration_s}) catch "?s";

        if (success) {
            stderr.writeAll("   ") catch {};
            stderr.writeAll(self.color.successGreen()) catch {};
            stderr.writeAll(color_mod.symbols.success) catch {};
            stderr.writeAll(self.color.reset()) catch {};
            stderr.writeAll(" ") catch {};
            stderr.writeAll(name) catch {};
            stderr.writeAll("     ") catch {};
            stderr.writeAll(self.color.muted()) catch {};
            stderr.writeAll(duration_str) catch {};
            stderr.writeAll(self.color.reset()) catch {};
            stderr.writeAll("\n") catch {};
        } else {
            stderr.writeAll("   ") catch {};
            stderr.writeAll(self.color.errorRed()) catch {};
            stderr.writeAll(color_mod.symbols.failure) catch {};
            stderr.writeAll(self.color.reset()) catch {};
            stderr.writeAll(" ") catch {};
            stderr.writeAll(name) catch {};
            stderr.writeAll("     ") catch {};
            stderr.writeAll(self.color.muted()) catch {};
            stderr.writeAll(duration_str) catch {};
            stderr.writeAll(self.color.reset()) catch {};
            stderr.writeAll("\n") catch {};
        }
    }

    /// Print Nx-style execution summary (v4 format)
    fn printExecutionSummary(self: *ParallelExecutor) void {
        const stderr = compat.getStdErr();
        const total_time_ns = std.time.nanoTimestamp() - self.exec_start_time;
        const total_time_ms = @divFloor(total_time_ns, 1_000_000);
        const total_time_s = @as(f64, @floatFromInt(total_time_ms)) / 1000.0;

        // Don't print summary in dry-run mode or if no tasks ran
        if (self.dry_run) {
            // Print dry-run summary
            const total = self.tasks_run + self.tasks_failed;
            if (total > 0) {
                stderr.writeAll("\n") catch {};
                var buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "   {d} task{s} would run\n", .{ total, if (total == 1) "" else "s" }) catch return;
                stderr.writeAll(msg) catch {};
                self.ctx.emitEvent(.{ .execution_summary = .{
                    .tasks_run = total,
                    .tasks_failed = 0,
                    .total_ms = @intCast(total_time_ms),
                } });
            }
            return;
        }

        const total_tasks = self.tasks_run + self.tasks_failed;
        if (total_tasks == 0) return;

        stderr.writeAll("\n") catch {};

        if (self.tasks_failed > 0) {
            // Failure summary
            stderr.writeAll("   ") catch {};
            stderr.writeAll(self.color.errorRed()) catch {};
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Failed to run {d} task{s}", .{ self.tasks_failed, if (self.tasks_failed == 1) "" else "s" }) catch return;
            stderr.writeAll(msg) catch {};
            stderr.writeAll(self.color.reset()) catch {};
            stderr.writeAll("\n") catch {};
        } else {
            // Success summary
            stderr.writeAll("   ") catch {};
            stderr.writeAll(self.color.successGreen()) catch {};
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Successfully ran {d} task{s}", .{ self.tasks_run, if (self.tasks_run == 1) "" else "s" }) catch return;
            stderr.writeAll(msg) catch {};
            stderr.writeAll(self.color.reset()) catch {};
            stderr.writeAll("\n") catch {};
        }

        // Total time
        stderr.writeAll("   ") catch {};
        stderr.writeAll(self.color.muted()) catch {};
        var time_buf: [64]u8 = undefined;
        const time_msg = std.fmt.bufPrint(&time_buf, "Total time: {d:.2}s", .{total_time_s}) catch return;
        stderr.writeAll(time_msg) catch {};
        stderr.writeAll(self.color.reset()) catch {};
        stderr.writeAll("\n") catch {};

        self.ctx.emitEvent(.{ .execution_summary = .{
            .tasks_run = total_tasks,
            .tasks_failed = self.tasks_failed,
            .total_ms = @intCast(total_time_ms),
        } });
    }

    /// Execute sequentially (for single-threaded or dry-run mode)
    fn executeSequential(self: *ParallelExecutor) ExecuteError!void {
        // Topological sort order
        var order: std.ArrayListUnmanaged(usize) = .empty;
        defer order.deinit(self.allocator);

        var in_degrees = self.allocator.alloc(usize, self.nodes.items.len) catch return ExecuteError.OutOfMemory;
        defer self.allocator.free(in_degrees);

        for (self.nodes.items, 0..) |node, i| {
            in_degrees[i] = node.in_degree;
        }

        // Kahn's algorithm
        var queue: std.ArrayListUnmanaged(usize) = .empty;
        defer queue.deinit(self.allocator);

        for (0..self.nodes.items.len) |i| {
            if (in_degrees[i] == 0) {
                queue.append(self.allocator, i) catch return ExecuteError.OutOfMemory;
            }
        }

        while (queue.items.len > 0) {
            const idx = queue.orderedRemove(0);
            order.append(self.allocator, idx) catch return ExecuteError.OutOfMemory;

            for (self.nodes.items[idx].dependents.items) |dep_idx| {
                in_degrees[dep_idx] -= 1;
                if (in_degrees[dep_idx] == 0) {
                    queue.append(self.allocator, dep_idx) catch return ExecuteError.OutOfMemory;
                }
            }
        }

        // Check for cycle (if order is incomplete)
        if (order.items.len != self.nodes.items.len) {
            return ExecuteError.CyclicDependency;
        }

        // Execute in order
        for (order.items) |idx| {
            if (!self.executeNode(idx)) {
                return ExecuteError.CommandFailed;
            }
        }
    }

    /// Get statistics about parallel execution potential
    pub fn getParallelismStats(self: *ParallelExecutor) struct {
        total_recipes: usize,
        max_parallel: usize,
        critical_path_length: usize,
    } {
        var max_parallel: usize = 0;
        var levels = self.allocator.alloc(usize, self.nodes.items.len) catch return .{
            .total_recipes = self.nodes.items.len,
            .max_parallel = 1,
            .critical_path_length = self.nodes.items.len,
        };
        defer self.allocator.free(levels);
        @memset(levels, 0);

        // Calculate level for each node (max dependency level + 1)
        var changed = true;
        while (changed) {
            changed = false;
            for (self.nodes.items, 0..) |node, i| {
                for (node.dependencies.items) |dep_idx| {
                    if (levels[i] <= levels[dep_idx]) {
                        levels[i] = levels[dep_idx] + 1;
                        changed = true;
                    }
                }
            }
        }

        // Count nodes at each level
        var max_level: usize = 0;
        for (levels) |level| {
            max_level = @max(max_level, level);
        }

        var level_counts = self.allocator.alloc(usize, max_level + 1) catch return .{
            .total_recipes = self.nodes.items.len,
            .max_parallel = 1,
            .critical_path_length = max_level + 1,
        };
        defer self.allocator.free(level_counts);
        @memset(level_counts, 0);

        for (levels) |level| {
            level_counts[level] += 1;
        }

        for (level_counts) |count| {
            max_parallel = @max(max_parallel, count);
        }

        return .{
            .total_recipes = self.nodes.items.len,
            .max_parallel = max_parallel,
            .critical_path_length = max_level + 1,
        };
    }
};

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

fn recipeUsesDirective(recipe: *const Recipe, directive: Recipe.CommandDirective) bool {
    for (recipe.commands) |cmd| {
        if (cmd.directive == directive) {
            return true;
        }
    }
    return false;
}

// Tests
test "parallel executor basic" {
    const source =
        \\task a:
        \\    echo "a"
        \\task b:
        \\    echo "b"
        \\task c: [a, b]
        \\    echo "c"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
    defer exec.deinit();

    try exec.buildGraph("c");

    try std.testing.expectEqual(@as(usize, 3), exec.nodes.items.len);
}

test "cycle detection" {
    const source =
        \\task a: [b]
        \\    echo "a"
        \\task b: [c]
        \\    echo "b"
        \\task c: [a]
        \\    echo "c"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
    defer exec.deinit();

    try exec.buildGraph("a");

    try std.testing.expect(exec.detectCycle());
}

test "parallelism stats" {
    const source =
        \\task a:
        \\    echo "a"
        \\task b:
        \\    echo "b"
        \\task c:
        \\    echo "c"
        \\task d: [a, b, c]
        \\    echo "d"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
    defer exec.deinit();

    try exec.buildGraph("d");

    const stats = exec.getParallelismStats();
    try std.testing.expectEqual(@as(usize, 4), stats.total_recipes);
    try std.testing.expectEqual(@as(usize, 3), stats.max_parallel); // a, b, c can run in parallel
    try std.testing.expectEqual(@as(usize, 2), stats.critical_path_length); // level 0: a,b,c; level 1: d
}

test "parallel dry-run does not leak expansions" {
    const source =
        \\name = "World"
        \\task hello:
        \\    echo "Hello, {{name}}!"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
    defer exec.deinit();

    exec.dry_run = true;

    try exec.buildGraph("hello");
    try exec.execute();
}

// ============================================================================
// TDD Tests for Parallel Executor Directive Handling
// These tests verify that the parallel executor correctly handles @if, @each,
// @ignore, and other directives instead of passing them to the shell.
// ============================================================================

test "parallel executor recognizes @if directive" {
    const source =
        \\task test:
        \\    @if true
        \\        echo "should run"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Verify the parser correctly identifies @if as a directive
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqual(@as(usize, 3), recipe.commands.len);

    // First command should be @if directive
    try std.testing.expect(recipe.commands[0].directive != null);
    try std.testing.expectEqual(parser.Recipe.CommandDirective.@"if", recipe.commands[0].directive.?);

    // Last command should be @end directive
    try std.testing.expect(recipe.commands[2].directive != null);
    try std.testing.expectEqual(parser.Recipe.CommandDirective.end, recipe.commands[2].directive.?);
}

test "parallel executor recognizes @each directive" {
    const source =
        \\task test:
        \\    @each foo bar baz
        \\        echo "item: {{item}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqual(@as(usize, 3), recipe.commands.len);

    // First command should be @each directive
    try std.testing.expect(recipe.commands[0].directive != null);
    try std.testing.expectEqual(parser.Recipe.CommandDirective.each, recipe.commands[0].directive.?);
}

test "parallel executor recognizes @ignore directive" {
    const source =
        \\task test:
        \\    @ignore
        \\    false
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqual(@as(usize, 2), recipe.commands.len);

    // First command should be @ignore directive
    try std.testing.expect(recipe.commands[0].directive != null);
    try std.testing.expectEqual(parser.Recipe.CommandDirective.ignore, recipe.commands[0].directive.?);

    // Second command should be a regular command
    try std.testing.expectEqual(@as(?parser.Recipe.CommandDirective, null), recipe.commands[1].directive);
}

test "parallel executor skips directive command when condition is false" {
    // @if false should skip body commands entirely, not pass them to shell
    const source =
        \\task test:
        \\    @if false
        \\        echo "should NOT run"
        \\    @end
        \\    echo "after if"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();
    exec.dry_run = true;

    try exec.buildGraph("test");

    // Should complete without error because directives are handled internally
    try exec.execute();
}

test "parallel executor @if true executes the true branch" {
    const source =
        \\task test:
        \\    @if true
        \\        exit 1
        \\    @end
        \\    echo "after if"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();

    try exec.buildGraph("test");
    try std.testing.expectError(ExecuteError.CommandFailed, exec.execute());
}

test "parallel executor handles @each loop expansion" {
    const source =
        \\task test:
        \\    @each apple banana
        \\        echo "fruit: {{item}}"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();
    exec.dry_run = true;

    try exec.buildGraph("test");

    // Should iterate over items and expand {{item}}
    try exec.execute();
}

test "parallel executor command-level @needs fails for missing command" {
    const source =
        \\task test:
        \\    @needs definitely_missing_parallel_needs_test_command
        \\    echo "should not run"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();

    try exec.buildGraph("test");
    try std.testing.expectError(ExecuteError.CommandFailed, exec.execute());
}

test "parallel executor graph includes producing file dependencies" {
    const source =
        \\file mid.txt: src.txt
        \\    echo mid > mid.txt
        \\
        \\file final.txt: mid.txt
        \\    echo final > final.txt
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 2);
    defer exec.deinit();

    try exec.buildGraph("final.txt");
    try std.testing.expectEqual(@as(usize, 2), exec.nodes.items.len);
    try std.testing.expect(exec.name_to_index.get("mid.txt") != null);
    try std.testing.expect(exec.name_to_index.get("final.txt") != null);
}

test "parallel executor @ignore allows command failure" {
    // @ignore allows the following command to fail without stopping the recipe
    const source =
        \\task test:
        \\    @ignore
        \\    exit 1
        \\    echo "after ignore"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();
    // NOT dry_run - actually execute commands

    try exec.buildGraph("test");

    // @ignore is now implemented - this should succeed despite exit 1
    try exec.execute();
}

test "parallel executor @if true executes body" {
    const source =
        \\task test:
        \\    @if true
        \\        echo "success"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();

    try exec.buildGraph("test");
    try exec.execute();
}

test "parallel executor @if false skips body" {
    const source =
        \\task test:
        \\    @if false
        \\        exit 1
        \\    @end
        \\    echo "done"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();

    try exec.buildGraph("test");
    // Should succeed because exit 1 is skipped when condition is false
    try exec.execute();
}

test "parallel executor @each expands items" {
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

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();

    try exec.buildGraph("test");
    // Should run echo 3 times with {{item}} expanded
    try exec.execute();
}

test "parallel executor nested @if in @each" {
    const source =
        \\task test:
        \\    @each a b
        \\        @if true
        \\            echo "item: {{item}}"
        \\        @end
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();

    try exec.buildGraph("test");
    try exec.execute();
}

test "parallel executor @elif branch" {
    const source =
        \\task test:
        \\    @if false
        \\        exit 1
        \\    @elif true
        \\        echo "elif branch"
        \\    @else
        \\        exit 1
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();
    exec.dry_run = true;

    try exec.buildGraph("test");
    // Should succeed - only elif branch executes
    try exec.execute();
}

test "parallel executor @else branch" {
    const source =
        \\task test:
        \\    @if false
        \\        exit 1
        \\    @else
        \\        echo "else branch"
        \\    @end
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();
    exec.dry_run = true;

    try exec.buildGraph("test");
    // Should succeed - else branch executes
    try exec.execute();
}

// Recipe-level @needs tests for parallel executor

fn testParallelNeedsCommand() []const u8 {
    return if (builtin.os.tag == .windows) "cmd" else "sh";
}

test "parallel executor recipe-level @needs succeeds when command exists" {
    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\@needs {s}
        \\task test:
        \\    echo "ok"
    , .{testParallelNeedsCommand()});
    defer std.testing.allocator.free(source);
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();
    exec.dry_run = true;

    try exec.buildGraph("test");
    // Should succeed - platform command exists
    try exec.execute();
}

test "parallel executor recipe-level @needs fails when command missing" {
    const source =
        \\@needs jake_nonexistent_xyz123
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();

    try exec.buildGraph("test");
    // Should fail - command doesn't exist
    const result = exec.execute();
    try std.testing.expectError(executor_mod.ExecuteError.CommandFailed, result);
}

test "parallel executor recipe-level @needs with hint and task reference" {
    const source =
        \\@needs jake_nonexistent_xyz123 "Install it" -> install-cmd
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();

    try exec.buildGraph("test");
    // Should fail with hint and task suggestion in output
    const result = exec.execute();
    try std.testing.expectError(executor_mod.ExecuteError.CommandFailed, result);
}

test "parallel executor handles empty dependency graph" {
    const source =
        \\task standalone:
        \\    echo "no deps"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
    defer exec.deinit();

    try exec.buildGraph("standalone");

    // Single node, no deps - should work fine
    const stats = exec.getParallelismStats();
    try std.testing.expectEqual(@as(usize, 1), stats.total_recipes);
}

test "parallel executor handles large thread count gracefully" {
    const source =
        \\task a:
        \\    echo "a"
        \\task b:
        \\    echo "b"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Request way more threads than needed
    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 100);
    defer exec.deinit();

    try exec.buildGraph("a");

    // Should not crash with more threads than recipes
    const stats = exec.getParallelismStats();
    try std.testing.expectEqual(@as(usize, 1), stats.total_recipes);
}

test "parallel executor handles zero thread count" {
    const source =
        \\task a:
        \\    echo "a"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Zero threads should use 1 as minimum
    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 0);
    defer exec.deinit();

    try exec.buildGraph("a");

    // Should handle gracefully
    const stats = exec.getParallelismStats();
    try std.testing.expectEqual(@as(usize, 1), stats.total_recipes);
}

test "parallel executor detectCycle returns false for acyclic graph" {
    const source =
        \\task a:
        \\    echo "a"
        \\task b: [a]
        \\    echo "b"
        \\task c: [b]
        \\    echo "c"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = try ParallelExecutor.init(std.testing.allocator, &jakefile, 2);
    defer exec.deinit();

    try exec.buildGraph("c");

    // No cycle in a -> b -> c
    try std.testing.expect(!exec.detectCycle());
}
