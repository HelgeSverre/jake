// context.zig - Shared execution context passed through app lifecycle
// Consolidates CLI flags and runtime configuration into a single struct

const std = @import("std");
const color_mod = @import("color.zig");
const cache_mod = @import("cache.zig");
const env_mod = @import("env.zig");
const hooks_mod = @import("hooks.zig");
const prompt_mod = @import("prompt.zig");
const parser = @import("parser.zig");
const jakefile_index = @import("jakefile_index.zig");

/// Shared execution context passed through the app lifecycle.
/// Replaces individual dry_run, verbose, etc. fields scattered across modules.
pub const Context = struct {
    // CLI flags
    dry_run: bool = false,
    verbose: bool = false,
    auto_yes: bool = false,
    watch_mode: bool = false,
    jobs: usize = 0, // 0 = sequential, >0 = parallel with N workers

    // Color output configuration
    color: color_mod.Color,

    // Positional arguments for recipe parameters ($1, $2, etc.)
    positional_args: []const []const u8 = &.{},

    /// Initialize with default values and auto-detected color settings
    pub fn init() Context {
        return .{
            .color = color_mod.init(),
        };
    }

    /// Create context for testing with explicit color setting
    pub fn initWithColor(color_enabled: bool) Context {
        return .{
            .color = color_mod.withEnabled(color_enabled),
        };
    }
};

/// Runtime services shared between executors/watchers to avoid duplicated setup.
pub const RuntimeContext = struct {
    allocator: std.mem.Allocator,
    cache: cache_mod.Cache,
    environment: env_mod.Environment,
    hook_runner: hooks_mod.HookRunner,
    prompt: prompt_mod.Prompt,
    color: color_mod.Color,
    theme: color_mod.Theme,
    cache_loaded: bool,

    pub fn init(allocator: std.mem.Allocator) RuntimeContext {
        return .{
            .allocator = allocator,
            .cache = cache_mod.Cache.init(allocator),
            .environment = env_mod.Environment.init(allocator),
            .hook_runner = hooks_mod.HookRunner.init(allocator),
            .prompt = prompt_mod.Prompt.init(),
            .color = color_mod.init(),
            .theme = color_mod.Theme.init(),
            .cache_loaded = false,
        };
    }

    pub fn initWithColor(allocator: std.mem.Allocator, color_enabled: bool) RuntimeContext {
        var ctx = RuntimeContext.init(allocator);
        ctx.color = color_mod.withEnabled(color_enabled);
        ctx.theme = color_mod.Theme.initWithColor(ctx.color);
        return ctx;
    }

    pub fn configure(self: *RuntimeContext, jakefile: *const parser.Jakefile, index: *const jakefile_index.JakefileIndex) void {
        self.loadCacheOnce();
        self.resetEnvironment();
        self.resetHookRunner();
        self.loadDotenvDirectives(index);
        self.applyExportDirectives(index);
        self.loadGlobalHooks(jakefile);
    }

    pub fn deinit(self: *RuntimeContext) void {
        self.cache.save() catch {};
        self.cache.deinit();
        self.environment.deinit();
        self.hook_runner.deinit();
    }

    fn loadCacheOnce(self: *RuntimeContext) void {
        if (self.cache_loaded) return;
        self.cache.load() catch {};
        self.cache_loaded = true;
    }

    fn resetEnvironment(self: *RuntimeContext) void {
        self.environment.deinit();
        self.environment = env_mod.Environment.init(self.allocator);
    }

    fn resetHookRunner(self: *RuntimeContext) void {
        self.hook_runner.deinit();
        self.hook_runner = hooks_mod.HookRunner.init(self.allocator);
        self.hook_runner.color = self.color;
        self.hook_runner.theme = self.theme;
    }

    fn loadDotenvDirectives(self: *RuntimeContext, index: *const jakefile_index.JakefileIndex) void {
        for (index.getDirectives(.dotenv)) |directive_ptr| {
            const directive = directive_ptr.*;
            if (directive.args.len > 0) {
                for (directive.args) |path| {
                    self.environment.loadDotenv(stripQuotes(path)) catch {};
                }
            } else {
                self.environment.loadDotenv(".env") catch {};
            }
        }
    }

    fn applyExportDirectives(self: *RuntimeContext, index: *const jakefile_index.JakefileIndex) void {
        for (index.getDirectives(.@"export")) |directive_ptr| {
            const directive = directive_ptr.*;
            if (directive.args.len == 0) continue;

            const first_arg = directive.args[0];
            if (std.mem.indexOfScalar(u8, first_arg, '=')) |eq_pos| {
                const key = first_arg[0..eq_pos];
                const value = stripQuotes(first_arg[eq_pos + 1 ..]);
                self.environment.set(key, value) catch {};
            } else if (directive.args.len >= 2) {
                self.environment.set(first_arg, stripQuotes(directive.args[1])) catch {};
            } else if (index.getVariable(first_arg)) |value| {
                self.environment.set(first_arg, value) catch {};
            }
        }
    }

    fn loadGlobalHooks(self: *RuntimeContext, jakefile: *const parser.Jakefile) void {
        for (jakefile.global_pre_hooks) |hook| {
            self.hook_runner.addGlobalHook(hook) catch {};
        }
        for (jakefile.global_post_hooks) |hook| {
            self.hook_runner.addGlobalHook(hook) catch {};
        }
        for (jakefile.global_on_error_hooks) |hook| {
            self.hook_runner.addGlobalHook(hook) catch {};
        }
    }
};

fn stripQuotes(value: []const u8) []const u8 {
    return parser.stripQuotes(value);
}

// ============================================================================
// Tests
// ============================================================================

test "Context.init creates default context" {
    const ctx = Context.init();
    try std.testing.expect(!ctx.dry_run);
    try std.testing.expect(!ctx.verbose);
    try std.testing.expect(!ctx.auto_yes);
    try std.testing.expect(!ctx.watch_mode);
    try std.testing.expectEqual(@as(usize, 0), ctx.jobs);
    try std.testing.expectEqual(@as(usize, 0), ctx.positional_args.len);
}

test "Context fields can be set" {
    var ctx = Context.init();
    ctx.dry_run = true;
    ctx.verbose = true;
    ctx.jobs = 4;
    try std.testing.expect(ctx.dry_run);
    try std.testing.expect(ctx.verbose);
    try std.testing.expectEqual(@as(usize, 4), ctx.jobs);
}

test "Context.initWithColor sets color enabled state" {
    const ctx_enabled = Context.initWithColor(true);
    try std.testing.expect(ctx_enabled.color.enabled);

    const ctx_disabled = Context.initWithColor(false);
    try std.testing.expect(!ctx_disabled.color.enabled);
}
