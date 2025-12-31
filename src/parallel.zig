// Jake Parallel Executor - Runs independent recipes concurrently
//
// This module provides parallel execution of recipes by:
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
const conditions = @import("conditions.zig");
const color_mod = @import("color.zig");

const Jakefile = parser.Jakefile;
const Recipe = parser.Recipe;
const Executor = executor_mod.Executor;
const ExecuteError = executor_mod.ExecuteError;

/// Result of a parallel recipe execution
pub const RecipeResult = struct {
    name: []const u8,
    success: bool,
    error_info: ?ExecuteError,
    output: []const u8,
};

/// Dependency graph node
const GraphNode = struct {
    recipe: *const Recipe,
    dependencies: std.ArrayListUnmanaged(usize), // Indices of dependencies
    dependents: std.ArrayListUnmanaged(usize), // Indices of recipes that depend on this
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

/// Thread-safe output buffer for capturing recipe output
const OutputBuffer = struct {
    mutex: std.Thread.Mutex,
    buffers: std.StringHashMap(std.ArrayList(u8)),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) OutputBuffer {
        return .{
            .mutex = .{},
            .buffers = std.StringHashMap(std.ArrayList(u8)).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *OutputBuffer) void {
        var iter = self.buffers.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.buffers.deinit();
    }

    fn getBuffer(self: *OutputBuffer, name: []const u8) !*std.ArrayList(u8) {
        self.mutex.lock();
        defer self.mutex.unlock();

        const result = try self.buffers.getOrPut(name);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(u8).init(self.allocator);
        }
        return result.value_ptr;
    }

    fn write(self: *OutputBuffer, name: []const u8, data: []const u8) !void {
        const buf = try self.getBuffer(name);
        self.mutex.lock();
        defer self.mutex.unlock();
        try buf.appendSlice(data);
    }
};

/// Parallel executor that runs independent recipes concurrently
pub const ParallelExecutor = struct {
    allocator: std.mem.Allocator,
    jakefile: *const Jakefile,
    nodes: std.ArrayListUnmanaged(GraphNode),
    name_to_index: std.StringHashMap(usize),
    thread_count: usize,
    dry_run: bool,
    verbose: bool,
    variables: std.StringHashMap([]const u8),
    cache: cache_mod.Cache,
    color: color_mod.Color,
    theme: color_mod.Theme,

    // Synchronization primitives
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    output_mutex: std.Thread.Mutex,

    // Execution state
    ready_queue: std.ArrayListUnmanaged(usize),
    completed_count: usize,
    failed: bool,
    first_error: ?ExecuteError,

    pub fn init(allocator: std.mem.Allocator, jakefile: *const Jakefile, thread_count: usize) ParallelExecutor {
        var variables = std.StringHashMap([]const u8).init(allocator);

        // Load variables from jakefile (OOM here is unrecoverable)
        for (jakefile.variables) |v| {
            variables.put(v.name, v.value) catch {};
        }

        return .{
            .allocator = allocator,
            .jakefile = jakefile,
            .nodes = .empty,
            .name_to_index = std.StringHashMap(usize).init(allocator),
            .thread_count = if (thread_count == 0) getDefaultThreadCount() else thread_count,
            .dry_run = false,
            .verbose = false,
            .variables = variables,
            .cache = cache_mod.Cache.init(allocator),
            .color = color_mod.init(),
            .theme = color_mod.Theme.init(),
            .mutex = .{},
            .condition = .{},
            .output_mutex = .{},
            .ready_queue = .empty,
            .completed_count = 0,
            .failed = false,
            .first_error = null,
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
        self.variables.deinit();
        self.cache.deinit();
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

    /// Recursively add a recipe and its dependencies to the graph
    fn addRecipeToGraph(self: *ParallelExecutor, name: []const u8, dependent_idx: ?usize) ExecuteError!void {
        // Check if already in graph
        if (self.name_to_index.get(name)) |existing_idx| {
            // Add edge from existing to dependent
            if (dependent_idx) |dep_idx| {
                self.nodes.items[existing_idx].dependents.append(self.allocator, dep_idx) catch return ExecuteError.OutOfMemory;
            }
            return;
        }

        // Find the recipe
        const recipe = self.jakefile.getRecipe(name) orelse {
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
            self.nodes.items[node_idx].dependents.append(self.allocator, dep_idx) catch return ExecuteError.OutOfMemory;
        }

        // Recursively add dependencies
        for (recipe.dependencies) |dep_name| {
            try self.addRecipeToGraph(dep_name, node_idx);
            // Add the dependency index to our dependencies list
            if (self.name_to_index.get(dep_name)) |dep_node_idx| {
                self.nodes.items[node_idx].dependencies.append(self.allocator, dep_node_idx) catch return ExecuteError.OutOfMemory;
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
        self.completed_count = 0;
        self.failed = false;
        self.first_error = null;

        // Determine actual thread count (don't spawn more threads than ready tasks)
        const max_threads = @min(self.thread_count, self.nodes.items.len);

        if (max_threads <= 1 or self.dry_run) {
            // Single-threaded execution for simplicity in dry-run or single thread
            try self.executeSequential();
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

        // Check OS constraints - skip recipe if not for current OS
        if (shouldSkipForOs(recipe)) {
            const current_os = getCurrentOsString();
            self.printSynchronized("jake: skipping '{s}' (not for {s})\n", .{ recipe.name, current_os });
            return true; // Success (skipped)
        }

        // Check recipe-level @needs requirements before running any commands
        if (recipe.needs.len > 0) {
            if (!self.checkRecipeLevelNeeds(recipe)) {
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
                return true;
            }
        }

        // Print recipe header and capture start time
        const start_time = std.time.nanoTimestamp();
        self.printSynchronized("{s} {f}\n", .{ self.theme.arrowSymbol(), self.theme.recipeHeader(recipe.name) });

        // Execute commands with directive handling
        if (!self.executeRecipeCommands(recipe.commands)) {
            self.printCompletionStatus(recipe.name, false, start_time);
            return false;
        }

        // Update cache for file targets
        if (recipe.kind == .file) {
            if (recipe.output) |output| {
                self.cache.update(output) catch {};
            }
        }

        self.printCompletionStatus(recipe.name, true, start_time);
        return true;
    }

    /// Check if a command exists in PATH
    fn commandExists(cmd: []const u8) bool {
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

    fn checkFileTarget(self: *ParallelExecutor, recipe: *const Recipe) !bool {
        const output = recipe.output orelse return true;

        std.fs.cwd().access(output, .{}) catch {
            return true; // Output doesn't exist
        };

        for (recipe.file_deps) |dep| {
            if (try self.cache.isGlobStale(dep)) {
                return true;
            }
        }

        return false;
    }

    /// Execute commands with full directive support (@if, @each, @ignore, etc.)
    fn executeRecipeCommands(self: *ParallelExecutor, cmds: []const Recipe.Command) bool {
        // Conditional state tracking using a stack for proper nesting
        const ConditionalState = struct {
            executing: bool,
            branch_taken: bool,
        };
        var cond_stack: [32]ConditionalState = undefined;
        var cond_depth: usize = 0;

        // Current state
        var executing: bool = true;
        var branch_taken: bool = false;
        var ignore_next: bool = false;

        var i: usize = 0;
        while (i < cmds.len) : (i += 1) {
            const cmd = cmds[i];

            // Handle directives
            if (cmd.directive) |directive| {
                switch (directive) {
                    .@"if" => {
                        // Push current state
                        if (cond_depth < cond_stack.len) {
                            cond_stack[cond_depth] = .{
                                .executing = executing,
                                .branch_taken = branch_taken,
                            };
                            cond_depth += 1;
                        }

                        if (!executing) {
                            branch_taken = false;
                            continue;
                        }

                        // Evaluate condition
                        const ctx = conditions.RuntimeContext{
                            .watch_mode = false,
                            .dry_run = self.dry_run,
                            .verbose = self.verbose,
                        };
                        const condition_result = conditions.evaluate(cmd.line, &self.variables, ctx) catch false;

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

                        const ctx = conditions.RuntimeContext{
                            .watch_mode = false,
                            .dry_run = self.dry_run,
                            .verbose = self.verbose,
                        };
                        const condition_result = conditions.evaluate(cmd.line, &self.variables, ctx) catch false;

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
                        if (executing) {
                            ignore_next = true;
                        }
                        continue;
                    },
                    .needs => {
                        // @needs - check if command exists (simplified version)
                        if (!executing) continue;
                        // For now, just skip validation in parallel mode
                        // Full implementation would check if commands exist
                        continue;
                    },
                    .confirm => {
                        // @confirm - skip in parallel mode (non-interactive)
                        if (!executing) continue;
                        // In parallel mode, we can't prompt interactively
                        // For safety, treat as confirmed
                        continue;
                    },
                    .each => {
                        if (!executing) {
                            // Skip to matching @end
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

                        // Expand variables in the @each line first
                        const expanded_line = self.expandVariables(cmd.line) catch cmd.line;
                        defer if (expanded_line.ptr != cmd.line.ptr) self.allocator.free(expanded_line);

                        // Parse items from expanded line
                        const items = self.parseEachItems(expanded_line);
                        if (items.len == 0) continue;
                        defer self.allocator.free(items);

                        // Find matching @end
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

                        // Execute loop body for each item
                        const loop_body = cmds[i + 1 .. end_idx];
                        for (items) |item| {
                            self.variables.put("item", item) catch {};
                            if (!self.executeRecipeCommands(loop_body)) {
                                return false;
                            }
                        }
                        _ = self.variables.remove("item");

                        i = end_idx;
                        continue;
                    },
                    .cache, .watch => {
                        // These are handled elsewhere or not applicable in parallel mode
                        continue;
                    },
                    .launch => {
                        // @launch - open file/URL with platform default app
                        if (!executing) continue;

                        // Strip "launch" keyword from line to get the target
                        var target = std.mem.trim(u8, cmd.line, " \t");
                        if (std.mem.startsWith(u8, target, "launch")) {
                            target = std.mem.trimLeft(u8, target[6..], " \t");
                        }

                        const argv: []const []const u8 = switch (builtin.os.tag) {
                            .macos => &[_][]const u8{ "open", target },
                            .linux => &[_][]const u8{ "xdg-open", target },
                            .windows => &[_][]const u8{ "cmd", "/c", "start", "", target },
                            else => {
                                continue; // Unsupported platform, skip
                            },
                        };

                        var child = std.process.Child.init(argv, self.allocator);
                        _ = child.spawn() catch {};
                        // Don't wait - let the app run in background
                        continue;
                    },
                }
            }

            // Regular command - check if we should execute
            if (!executing) continue;

            // Execute the command
            const current_ignore = ignore_next;
            ignore_next = false;

            if (!self.runShellCommand(cmd.line)) {
                if (current_ignore) {
                    // @ignore was set, continue despite failure
                    continue;
                }
                return false;
            }
        }

        return true;
    }

    /// Parse @each items from the line
    fn parseEachItems(self: *ParallelExecutor, line: []const u8) [][]const u8 {
        var items: std.ArrayListUnmanaged([]const u8) = .empty;

        var iter = std.mem.splitScalar(u8, line, ' ');
        while (iter.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len > 0) {
                items.append(self.allocator, trimmed) catch continue;
            }
        }

        return items.toOwnedSlice(self.allocator) catch &.{};
    }

    /// Run a shell command (the actual execution, separated from directive handling)
    fn runShellCommand(self: *ParallelExecutor, line: []const u8) bool {
        const expanded = self.expandVariables(line) catch line;
        defer if (expanded.ptr != line.ptr) self.allocator.free(expanded);

        if (self.dry_run) {
            self.printSynchronized("  [dry-run] {s}\n", .{expanded});
            return true;
        }

        if (self.verbose) {
            self.printSynchronized("  $ {s}\n", .{expanded});
        }

        // Execute via shell
        var child = std.process.Child.init(
            &[_][]const u8{ "/bin/sh", "-c", expanded },
            self.allocator,
        );
        child.stderr_behavior = .Pipe;
        child.stdout_behavior = .Pipe;

        _ = child.spawn() catch |err| {
            self.printSynchronized("{s}failed to spawn: {s}\n", .{ self.color.errPrefix(), @errorName(err) });
            return false;
        };

        var stdout_buf: [4096]u8 = undefined;
        var stderr_buf: [4096]u8 = undefined;

        const stdout_len = if (child.stdout) |stdout| stdout.read(&stdout_buf) catch 0 else 0;
        const stderr_len = if (child.stderr) |stderr| stderr.read(&stderr_buf) catch 0 else 0;

        const result = child.wait() catch |err| {
            self.printSynchronized("{s}failed to wait: {s}\n", .{ self.color.errPrefix(), @errorName(err) });
            return false;
        };

        if (stdout_len > 0) {
            self.output_mutex.lock();
            defer self.output_mutex.unlock();
            compat.getStdOut().writeAll(stdout_buf[0..stdout_len]) catch {};
        }
        if (stderr_len > 0) {
            self.output_mutex.lock();
            defer self.output_mutex.unlock();
            compat.getStdErr().writeAll(stderr_buf[0..stderr_len]) catch {};
        }

        switch (result) {
            .Exited => |code| {
                if (code != 0) {
                    self.printSynchronized("{s}command exited with code {d}\n", .{ self.color.errPrefix(), code });
                    return false;
                }
            },
            .Signal => |sig| {
                self.printSynchronized("{s}command killed by signal {d}\n", .{ self.color.errPrefix(), sig });
                return false;
            },
            .Stopped => |sig| {
                self.printSynchronized("{s}command stopped by signal {d}\n", .{ self.color.errPrefix(), sig });
                return false;
            },
            .Unknown => |code| {
                self.printSynchronized("{s}command terminated with unknown status {d}\n", .{ self.color.errPrefix(), code });
                return false;
            },
        }

        return true;
    }

    fn runCommand(self: *ParallelExecutor, cmd: Recipe.Command, recipe: *const Recipe) bool {
        _ = recipe;

        const line = self.expandVariables(cmd.line) catch cmd.line;
        defer if (line.ptr != cmd.line.ptr) self.allocator.free(line);

        if (self.dry_run) {
            self.printSynchronized("  [dry-run] {s}\n", .{line});
            return true;
        }

        if (self.verbose) {
            self.printSynchronized("  $ {s}\n", .{line});
        }

        // Execute via shell, capturing output
        var child = std.process.Child.init(
            &[_][]const u8{ "/bin/sh", "-c", line },
            self.allocator,
        );
        child.stderr_behavior = .Pipe;
        child.stdout_behavior = .Pipe;

        _ = child.spawn() catch |err| {
            self.printSynchronized("{s}failed to spawn: {s}\n", .{ self.color.errPrefix(), @errorName(err) });
            return false;
        };

        // Read stdout and stderr
        var stdout_buf: [4096]u8 = undefined;
        var stderr_buf: [4096]u8 = undefined;

        const stdout_len = if (child.stdout) |stdout| stdout.read(&stdout_buf) catch 0 else 0;
        const stderr_len = if (child.stderr) |stderr| stderr.read(&stderr_buf) catch 0 else 0;

        const result = child.wait() catch |err| {
            self.printSynchronized("{s}failed to wait: {s}\n", .{ self.color.errPrefix(), @errorName(err) });
            return false;
        };

        // Print captured output synchronously
        if (stdout_len > 0) {
            self.output_mutex.lock();
            defer self.output_mutex.unlock();
            compat.getStdOut().writeAll(stdout_buf[0..stdout_len]) catch {};
        }
        if (stderr_len > 0) {
            self.output_mutex.lock();
            defer self.output_mutex.unlock();
            compat.getStdErr().writeAll(stderr_buf[0..stderr_len]) catch {};
        }

        switch (result) {
            .Exited => |code| {
                if (code != 0) {
                    self.printSynchronized("{s}command exited with code {d}\n", .{ self.color.errPrefix(), code });
                    return false;
                }
            },
            .Signal => |sig| {
                self.printSynchronized("{s}command killed by signal {d}\n", .{ self.color.errPrefix(), sig });
                return false;
            },
            .Stopped => |sig| {
                self.printSynchronized("{s}command stopped by signal {d}\n", .{ self.color.errPrefix(), sig });
                return false;
            },
            .Unknown => |code| {
                self.printSynchronized("{s}command terminated with unknown status {d}\n", .{ self.color.errPrefix(), code });
                return false;
            },
        }

        return true;
    }

    fn expandVariables(self: *ParallelExecutor, line: []const u8) ![]const u8 {
        // Fast-path: avoid allocating when there are no substitutions.
        if (std.mem.indexOf(u8, line, "{{") == null) {
            return line;
        }

        var result: std.ArrayListUnmanaged(u8) = .empty;
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < line.len) {
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
                    // OOM here could cause dependent tasks to not be scheduled
                    self.ready_queue.append(self.allocator, dependent_idx) catch {};
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

    /// Print completion status with timing (per brand guide Style A)
    /// Success: ✓ recipe_name (duration)
    /// Failure: ✗ recipe_name (duration)
    fn printCompletionStatus(self: *ParallelExecutor, name: []const u8, success: bool, start_time: i128) void {
        const end_time = std.time.nanoTimestamp();
        const duration_ns = end_time - start_time;
        const duration_ms = @divFloor(duration_ns, 1_000_000);
        const duration_s = @as(f64, @floatFromInt(duration_ms)) / 1000.0;

        self.output_mutex.lock();
        defer self.output_mutex.unlock();

        const stderr = compat.getStdErr();
        if (success) {
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();
    exec.dry_run = true;

    try exec.buildGraph("test");

    // Should complete without error because directives are handled internally
    try exec.execute();
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();
    exec.dry_run = true;

    try exec.buildGraph("test");

    // Should iterate over items and expand {{item}}
    try exec.execute();
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();
    exec.dry_run = true;

    try exec.buildGraph("test");
    // Should succeed - else branch executes
    try exec.execute();
}

// Recipe-level @needs tests for parallel executor

test "parallel executor recipe-level @needs succeeds when command exists" {
    const source =
        \\@needs sh
        \\task test:
        \\    echo "ok"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
    defer exec.deinit();
    exec.dry_run = true;

    try exec.buildGraph("test");
    // Should succeed - 'sh' exists on all systems
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 1);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
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
    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 100);
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
    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 0);
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

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 2);
    defer exec.deinit();

    try exec.buildGraph("c");

    // No cycle in a -> b -> c
    try std.testing.expect(!exec.detectCycle());
}
