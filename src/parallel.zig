// Jake Parallel Executor - Runs independent recipes concurrently
//
// This module provides parallel execution of recipes by:
// 1. Building a dependency graph from recipes
// 2. Identifying recipes that can run in parallel (no dependencies on each other)
// 3. Using Zig's std.Thread to run them concurrently
// 4. Collecting and merging results with synchronized output

const std = @import("std");
const builtin = @import("builtin");
const parser = @import("parser.zig");
const executor_mod = @import("executor.zig");
const cache_mod = @import("cache.zig");

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

        // Check if file target needs rebuilding
        if (recipe.kind == .file) {
            const needs_run = self.checkFileTarget(recipe) catch true;
            if (!needs_run) {
                if (self.verbose) {
                    self.printSynchronized("\x1b[90mjake: '{s}' is up to date\x1b[0m\n", .{recipe.name});
                }
                return true;
            }
        }

        // Print recipe header
        self.printSynchronized("\x1b[1;36m-> {s}\x1b[0m\n", .{recipe.name});

        // Execute commands
        for (recipe.commands) |cmd| {
            if (!self.runCommand(cmd, recipe)) {
                return false;
            }
        }

        // Update cache for file targets
        if (recipe.kind == .file) {
            if (recipe.output) |output| {
                self.cache.update(output) catch {};
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

    fn runCommand(self: *ParallelExecutor, cmd: Recipe.Command, recipe: *const Recipe) bool {
        _ = recipe;

        const line = self.expandVariables(cmd.line) catch cmd.line;

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
            self.printSynchronized("\x1b[1;31merror:\x1b[0m failed to spawn: {s}\n", .{@errorName(err)});
            return false;
        };

        // Read stdout and stderr
        var stdout_buf: [4096]u8 = undefined;
        var stderr_buf: [4096]u8 = undefined;

        const stdout_len = if (child.stdout) |stdout| stdout.read(&stdout_buf) catch 0 else 0;
        const stderr_len = if (child.stderr) |stderr| stderr.read(&stderr_buf) catch 0 else 0;

        const result = child.wait() catch |err| {
            self.printSynchronized("\x1b[1;31merror:\x1b[0m failed to wait: {s}\n", .{@errorName(err)});
            return false;
        };

        // Print captured output synchronously
        if (stdout_len > 0) {
            self.output_mutex.lock();
            defer self.output_mutex.unlock();
            std.fs.File.stdout().writeAll(stdout_buf[0..stdout_len]) catch {};
        }
        if (stderr_len > 0) {
            self.output_mutex.lock();
            defer self.output_mutex.unlock();
            std.fs.File.stderr().writeAll(stderr_buf[0..stderr_len]) catch {};
        }

        if (result.Exited != 0) {
            self.printSynchronized("\x1b[1;31merror:\x1b[0m command exited with code {d}\n", .{result.Exited});
            return false;
        }

        return true;
    }

    fn expandVariables(self: *ParallelExecutor, line: []const u8) ![]const u8 {
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
        std.fs.File.stderr().writeAll(msg) catch {};
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
    const jakefile = try p.parseJakefile();

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
    const jakefile = try p.parseJakefile();

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
    const jakefile = try p.parseJakefile();

    var exec = ParallelExecutor.init(std.testing.allocator, &jakefile, 4);
    defer exec.deinit();

    try exec.buildGraph("d");

    const stats = exec.getParallelismStats();
    try std.testing.expectEqual(@as(usize, 4), stats.total_recipes);
    try std.testing.expectEqual(@as(usize, 3), stats.max_parallel); // a, b, c can run in parallel
    try std.testing.expectEqual(@as(usize, 2), stats.critical_path_length); // level 0: a,b,c; level 1: d
}
