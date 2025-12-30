// Jake Hooks - Pre/Post execution hooks for recipes
//
// Hooks provide a way to run commands before and after recipe execution.
// There are two types of hooks:
// 1. Global hooks - run before/after any recipe execution
// 2. Recipe-specific hooks - run only for a specific recipe

const std = @import("std");
const compat = @import("compat.zig");

/// Represents a single hook (pre, post, or on_error execution)
pub const Hook = struct {
    /// The command to execute
    command: []const u8,
    /// Whether this is a pre, post, or on_error hook
    kind: Kind,
    /// Optional: Only run for specific recipe (null = global)
    recipe_name: ?[]const u8,

    pub const Kind = enum {
        pre,
        post,
        on_error, // Runs only when a recipe fails
    };
};

/// Context passed to hooks during execution
pub const HookContext = struct {
    /// Name of the recipe being executed
    recipe_name: []const u8,
    /// Whether the recipe succeeded (only valid for post hooks)
    success: bool,
    /// Error message if the recipe failed (only valid for post hooks)
    error_message: ?[]const u8,
    /// Variables available for substitution
    variables: *const std.StringHashMap([]const u8),

    /// Get a variable value by name
    pub fn getVariable(self: *const HookContext, name: []const u8) ?[]const u8 {
        return self.variables.get(name);
    }
};

/// Runs hooks with proper error handling and context
pub const HookRunner = struct {
    allocator: std.mem.Allocator,
    global_pre_hooks: std.ArrayListUnmanaged(Hook),
    global_post_hooks: std.ArrayListUnmanaged(Hook),
    global_on_error_hooks: std.ArrayListUnmanaged(Hook),
    dry_run: bool,
    verbose: bool,

    pub fn init(allocator: std.mem.Allocator) HookRunner {
        return .{
            .allocator = allocator,
            .global_pre_hooks = .empty,
            .global_post_hooks = .empty,
            .global_on_error_hooks = .empty,
            .dry_run = false,
            .verbose = false,
        };
    }

    pub fn deinit(self: *HookRunner) void {
        self.global_pre_hooks.deinit(self.allocator);
        self.global_post_hooks.deinit(self.allocator);
        self.global_on_error_hooks.deinit(self.allocator);
    }

    /// Add a global hook
    pub fn addGlobalHook(self: *HookRunner, hook: Hook) !void {
        switch (hook.kind) {
            .pre => try self.global_pre_hooks.append(self.allocator, hook),
            .post => try self.global_post_hooks.append(self.allocator, hook),
            .on_error => try self.global_on_error_hooks.append(self.allocator, hook),
        }
    }

    /// Check if a hook should run for the given recipe
    fn shouldRunHook(hook: Hook, recipe_name: []const u8) bool {
        if (hook.recipe_name) |target_recipe| {
            // Targeted hook: only run if recipe name matches
            return std.mem.eql(u8, target_recipe, recipe_name);
        }
        // Global hook: always run
        return true;
    }

    /// Run all pre-hooks for a recipe
    /// Order: 1. Global @pre, 2. Targeted @before, 3. Recipe @pre
    pub fn runPreHooks(
        self: *HookRunner,
        recipe_pre_hooks: []const Hook,
        context: *const HookContext,
    ) HookError!void {
        // 1. Run truly global pre-hooks first (no recipe_name specified)
        for (self.global_pre_hooks.items) |hook| {
            if (hook.recipe_name == null) {
                try self.executeHook(hook, context);
            }
        }

        // 2. Run targeted @before hooks (recipe_name matches current recipe)
        for (self.global_pre_hooks.items) |hook| {
            if (hook.recipe_name) |target| {
                if (std.mem.eql(u8, target, context.recipe_name)) {
                    try self.executeHook(hook, context);
                }
            }
        }

        // 3. Run recipe-specific pre-hooks (inside recipe body)
        for (recipe_pre_hooks) |hook| {
            try self.executeHook(hook, context);
        }
    }

    /// Run all post-hooks for a recipe (runs even on failure for cleanup)
    /// Order: 1. Recipe @post, 2. Targeted @after, 3. Global @post
    pub fn runPostHooks(
        self: *HookRunner,
        recipe_post_hooks: []const Hook,
        context: *const HookContext,
    ) HookError!void {
        var first_error: ?HookError = null;

        // 1. Run recipe-specific post-hooks first (inside recipe body)
        for (recipe_post_hooks) |hook| {
            self.executeHook(hook, context) catch |err| {
                if (first_error == null) first_error = err;
            };
        }

        // 2. Run targeted @after hooks (recipe_name matches current recipe)
        for (self.global_post_hooks.items) |hook| {
            if (hook.recipe_name) |target| {
                if (std.mem.eql(u8, target, context.recipe_name)) {
                    self.executeHook(hook, context) catch |err| {
                        if (first_error == null) first_error = err;
                    };
                }
            }
        }

        // 3. Run truly global post-hooks last (no recipe_name specified)
        for (self.global_post_hooks.items) |hook| {
            if (hook.recipe_name == null) {
                self.executeHook(hook, context) catch |err| {
                    if (first_error == null) first_error = err;
                };
            }
        }

        // Return the first error if any occurred
        if (first_error) |err| return err;
    }

    /// Run all on_error hooks for a recipe (only runs when recipe fails)
    pub fn runOnErrorHooks(
        self: *HookRunner,
        context: *const HookContext,
    ) void {
        // Only run if the recipe failed
        if (context.success) return;

        // Run global on_error hooks (only if they match the current recipe)
        for (self.global_on_error_hooks.items) |hook| {
            if (shouldRunHook(hook, context.recipe_name)) {
                self.executeHook(hook, context) catch {};
            }
        }
    }

    /// Execute a single hook command
    fn executeHook(self: *HookRunner, hook: Hook, context: *const HookContext) HookError!void {
        const expanded_cmd = self.expandHookVariables(hook.command, context) catch hook.command;
        // Track if we allocated memory (expanded_cmd ptr differs from original)
        const needs_free = expanded_cmd.ptr != hook.command.ptr;
        defer if (needs_free) self.allocator.free(expanded_cmd);

        if (self.dry_run) {
            self.printHook("[dry-run @{s}] {s}\n", .{ @tagName(hook.kind), expanded_cmd });
            return;
        }

        if (self.verbose) {
            self.printHook("[@{s}] {s}\n", .{ @tagName(hook.kind), expanded_cmd });
        }

        // Execute via shell
        var child = std.process.Child.init(
            &[_][]const u8{ "/bin/sh", "-c", expanded_cmd },
            self.allocator,
        );
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;

        _ = child.spawn() catch |err| {
            self.printHook("\x1b[1;31merror:\x1b[0m hook spawn failed: {s}\n", .{@errorName(err)});
            return HookError.SpawnFailed;
        };

        const result = child.wait() catch |err| {
            self.printHook("\x1b[1;31merror:\x1b[0m hook wait failed: {s}\n", .{@errorName(err)});
            return HookError.WaitFailed;
        };

        if (result.Exited != 0) {
            self.printHook("\x1b[1;31merror:\x1b[0m @{s} hook exited with code {d}\n", .{ @tagName(hook.kind), result.Exited });
            return HookError.HookFailed;
        }
    }

    /// Expand variables in hook command
    /// Supports: {{name}}, {{status}}, {{error}}, and user-defined variables
    fn expandHookVariables(
        self: *HookRunner,
        command: []const u8,
        context: *const HookContext,
    ) ![]const u8 {
        var result: std.ArrayListUnmanaged(u8) = .empty;
        errdefer result.deinit(self.allocator);

        var i: usize = 0;
        while (i < command.len) {
            // Check for {{var}} pattern
            if (i + 1 < command.len and command[i] == '{' and command[i + 1] == '{') {
                const start = i + 2;
                var end = start;
                while (end + 1 < command.len and !(command[end] == '}' and command[end + 1] == '}')) {
                    end += 1;
                }
                if (end + 1 < command.len) {
                    const var_name = command[start..end];

                    // Check for built-in hook variables
                    const value = if (std.mem.eql(u8, var_name, "name"))
                        context.recipe_name
                    else if (std.mem.eql(u8, var_name, "status"))
                        if (context.success) "success" else "failed"
                    else if (std.mem.eql(u8, var_name, "error"))
                        context.error_message orelse ""
                    else
                        context.getVariable(var_name);

                    if (value) |v| {
                        try result.appendSlice(self.allocator, v);
                    } else {
                        // Keep original if not found
                        try result.appendSlice(self.allocator, command[i .. end + 2]);
                    }
                    i = end + 2;
                    continue;
                }
            }
            try result.append(self.allocator, command[i]);
            i += 1;
        }

        return result.toOwnedSlice(self.allocator);
    }

    fn printHook(self: *HookRunner, comptime fmt: []const u8, args: anytype) void {
        _ = self;
        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        compat.getStdErr().writeAll(msg) catch {};
    }
};

pub const HookError = error{
    SpawnFailed,
    WaitFailed,
    HookFailed,
    OutOfMemory,
};

test "hook context basic" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();
    try variables.put("version", "1.0.0");

    const context = HookContext{
        .recipe_name = "build",
        .success = true,
        .error_message = null,
        .variables = &variables,
    };

    try std.testing.expectEqualStrings("build", context.recipe_name);
    try std.testing.expectEqual(true, context.success);
    try std.testing.expectEqualStrings("1.0.0", context.getVariable("version").?);
}

test "hook runner init" {
    var runner = HookRunner.init(std.testing.allocator);
    defer runner.deinit();

    try runner.addGlobalHook(.{
        .command = "echo 'pre'",
        .kind = .pre,
        .recipe_name = null,
    });

    try std.testing.expectEqual(@as(usize, 1), runner.global_pre_hooks.items.len);
    try std.testing.expectEqual(@as(usize, 0), runner.global_post_hooks.items.len);
}

test "hook variable expansion" {
    var runner = HookRunner.init(std.testing.allocator);
    defer runner.deinit();

    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();
    try variables.put("version", "2.0");

    const context = HookContext{
        .recipe_name = "deploy",
        .success = true,
        .error_message = null,
        .variables = &variables,
    };

    const expanded = try runner.expandHookVariables("Building {{name}} v{{version}}", &context);
    defer std.testing.allocator.free(expanded);

    try std.testing.expectEqualStrings("Building deploy v2.0", expanded);
}

test "hook runner adds on_error hooks" {
    var runner = HookRunner.init(std.testing.allocator);
    defer runner.deinit();

    try runner.addGlobalHook(.{
        .command = "echo 'error'",
        .kind = .on_error,
        .recipe_name = null,
    });

    try std.testing.expectEqual(@as(usize, 0), runner.global_pre_hooks.items.len);
    try std.testing.expectEqual(@as(usize, 0), runner.global_post_hooks.items.len);
    try std.testing.expectEqual(@as(usize, 1), runner.global_on_error_hooks.items.len);
}

test "shouldRunHook returns true for global hook" {
    const hook = Hook{
        .command = "echo test",
        .kind = .pre,
        .recipe_name = null, // Global hook
    };

    try std.testing.expect(HookRunner.shouldRunHook(hook, "build"));
    try std.testing.expect(HookRunner.shouldRunHook(hook, "test"));
    try std.testing.expect(HookRunner.shouldRunHook(hook, "deploy"));
}

test "shouldRunHook returns true only for targeted recipe" {
    const hook = Hook{
        .command = "echo test",
        .kind = .pre,
        .recipe_name = "build", // Targeted hook
    };

    try std.testing.expect(HookRunner.shouldRunHook(hook, "build"));
    try std.testing.expect(!HookRunner.shouldRunHook(hook, "test"));
    try std.testing.expect(!HookRunner.shouldRunHook(hook, "deploy"));
}

test "on_error hook kind exists" {
    const hook = Hook{
        .command = "echo error",
        .kind = .on_error,
        .recipe_name = null,
    };

    try std.testing.expectEqual(Hook.Kind.on_error, hook.kind);
}

test "hook context with error message" {
    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const context = HookContext{
        .recipe_name = "build",
        .success = false,
        .error_message = "CommandFailed",
        .variables = &variables,
    };

    try std.testing.expect(!context.success);
    try std.testing.expectEqualStrings("CommandFailed", context.error_message.?);
}

test "hook runner handles empty hook list" {
    var runner = HookRunner.init(std.testing.allocator);
    defer runner.deinit();

    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    const context = HookContext{
        .recipe_name = "build",
        .success = true,
        .error_message = null,
        .variables = &variables,
    };

    // Running with empty hooks should not crash
    runner.runPreHooks(&.{}, &context) catch {};
}

test "hook runner handles null recipe name in context" {
    var runner = HookRunner.init(std.testing.allocator);
    defer runner.deinit();

    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    // Context with null recipe name
    const context = HookContext{
        .recipe_name = "",
        .success = true,
        .error_message = null,
        .variables = &variables,
    };

    // Should not crash with empty recipe name
    runner.runPreHooks(&.{}, &context) catch {};
}

test "shouldRunHook handles empty recipe name" {
    const global_hook = Hook{
        .command = "echo global",
        .kind = .pre,
        .recipe_name = null, // Global hook
    };

    const targeted_hook = Hook{
        .command = "echo targeted",
        .kind = .pre,
        .recipe_name = "specific",
    };

    // Global hook should run for empty recipe name
    try std.testing.expect(HookRunner.shouldRunHook(global_hook, ""));

    // Targeted hook should not run for empty recipe name
    try std.testing.expect(!HookRunner.shouldRunHook(targeted_hook, ""));
}

test "hook variable expansion with special characters" {
    var runner = HookRunner.init(std.testing.allocator);
    defer runner.deinit();

    var variables = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer variables.deinit();

    try variables.put("path", "/some/path with spaces");
    try variables.put("msg", "hello \"world\"");

    const context = HookContext{
        .recipe_name = "test",
        .success = true,
        .error_message = null,
        .variables = &variables,
    };

    const command = "echo {{path}} {{msg}}";
    const expanded = try runner.expandHookVariables(command, &context);
    defer std.testing.allocator.free(expanded);

    try std.testing.expectEqualStrings("echo /some/path with spaces hello \"world\"", expanded);
}
