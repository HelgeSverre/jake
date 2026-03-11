//! Runtime context for recipe execution (working directory, env, etc.).
//! Consolidates CLI flags and runtime configuration into a single struct.

const std = @import("std");
const builtin = @import("builtin");
const color_mod = @import("color.zig");
const cache_mod = @import("cache.zig");
const env_mod = @import("env.zig");
const hooks_mod = @import("hooks.zig");
const prompt_mod = @import("prompt.zig");
const parser = @import("parser.zig");
const jakefile_index = @import("jakefile_index.zig");
const event_emitter_mod = @import("event_emitter.zig");
const compat = @import("compat.zig");

/// Output callback function type for streaming command output (web UI)
pub const OutputCallback = *const fn (ctx: *anyopaque, line: []const u8, is_stderr: bool) void;
/// Command callback for streaming command-start events (web UI)
pub const CommandCallback = *const fn (ctx: *anyopaque, task_name: []const u8, command: []const u8) void;
/// Confirmation callback for non-terminal confirmation transports (web UI)
pub const ConfirmCallback = *const fn (ctx: *anyopaque, task_name: []const u8, message: []const u8) anyerror!prompt_mod.ConfirmResult;

/// Shared execution context passed through the app lifecycle.
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

    // Cancellation support for web UI
    cancellation_flag: ?*std.atomic.Value(bool) = null,

    // Current child process ID for killing (web UI cancellation)
    current_child_pid: ?*std.atomic.Value(i32) = null,

    // Output streaming callback for web UI (captures stdout/stderr)
    output_callback: ?OutputCallback = null,
    output_callback_ctx: ?*anyopaque = null,

    // Command streaming callback for web UI (captures command starts)
    command_callback: ?CommandCallback = null,
    command_callback_ctx: ?*anyopaque = null,

    // Confirmation callback for web UI/browser transports
    confirm_callback: ?ConfirmCallback = null,
    confirm_callback_ctx: ?*anyopaque = null,

    // Lifecycle/output event emitter for Web UI streaming
    event_emitter: ?event_emitter_mod.EventEmitter = null,

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

    /// Check if execution has been cancelled
    pub fn isCancelled(self: *const Context) bool {
        if (self.cancellation_flag) |flag| {
            return !flag.load(.acquire);
        }
        return false;
    }

    /// Kill the current child process (for cancellation)
    pub fn killCurrentChild(self: *const Context) void {
        if (self.current_child_pid) |pid_atomic| {
            const pid = pid_atomic.load(.acquire);
            if (pid > 0) {
                // Negative pid kills the entire process group, ensuring child processes
                // spawned by the command are also terminated.
                std.posix.kill(-pid, std.posix.SIG.KILL) catch {};
                // Also kill the process directly in case it isn't in a process group.
                std.posix.kill(pid, std.posix.SIG.KILL) catch {};
            }
        }
    }

    /// Emit output line via callback (for web UI streaming)
    pub fn emitOutput(self: *const Context, line: []const u8, is_stderr: bool) void {
        if (self.output_callback) |callback| {
            if (self.output_callback_ctx) |ctx| {
                callback(ctx, line, is_stderr);
            }
        }
    }

    /// Check if output should be captured (web UI mode)
    pub fn hasOutputCallback(self: *const Context) bool {
        return self.output_callback != null;
    }

    /// Emit a command-start event via callback (for web UI streaming)
    pub fn emitCommand(self: *const Context, task_name: []const u8, command: []const u8) void {
        if (self.command_callback) |callback| {
            if (self.command_callback_ctx) |ctx| {
                callback(ctx, task_name, command);
            }
        }
    }

    /// Check if command start events should be captured (web UI mode)
    pub fn hasCommandCallback(self: *const Context) bool {
        return self.command_callback != null;
    }

    /// Emit a lifecycle/output event via the configured emitter.
    pub fn emitEvent(self: *const Context, event: event_emitter_mod.Event) void {
        if (self.event_emitter) |emitter| {
            emitter.emit(event);
        }
    }

    /// Check if lifecycle events should be streamed.
    pub fn hasEventEmitter(self: *const Context) bool {
        return self.event_emitter != null;
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

    pub fn configure(self: *RuntimeContext, jakefile: *const parser.Jakefile, index: *const jakefile_index.JakefileIndex) !void {
        try self.loadCacheOnce();
        self.resetEnvironment();
        self.resetHookRunner();
        try self.loadDotenvDirectives(index);
        try self.applyExportDirectives(index);
        try self.loadGlobalHooks(jakefile);
    }

    pub fn deinit(self: *RuntimeContext) void {
        self.cache.save() catch |err| {
            printRuntimeWarning("failed to save cache", err);
        };
        self.cache.deinit();
        self.environment.deinit();
        self.hook_runner.deinit();
    }

    fn loadCacheOnce(self: *RuntimeContext) !void {
        if (self.cache_loaded) return;
        try self.cache.load();
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

    fn loadDotenvDirectives(self: *RuntimeContext, index: *const jakefile_index.JakefileIndex) !void {
        for (index.getDirectives(.dotenv)) |directive_ptr| {
            const directive = directive_ptr.*;
            if (directive.args.len > 0) {
                for (directive.args) |path| {
                    try self.environment.loadDotenv(stripQuotes(path));
                }
            } else {
                try self.environment.loadDotenv(".env");
            }
        }
    }

    fn applyExportDirectives(self: *RuntimeContext, index: *const jakefile_index.JakefileIndex) !void {
        for (index.getDirectives(.@"export")) |directive_ptr| {
            const directive = directive_ptr.*;
            if (directive.args.len == 0) continue;

            const first_arg = directive.args[0];
            if (std.mem.indexOfScalar(u8, first_arg, '=')) |eq_pos| {
                const key = first_arg[0..eq_pos];
                const value = stripQuotes(first_arg[eq_pos + 1 ..]);
                try self.environment.set(key, value);
            } else if (directive.args.len >= 2) {
                try self.environment.set(first_arg, stripQuotes(directive.args[1]));
            } else if (index.getVariable(first_arg)) |value| {
                try self.environment.set(first_arg, value);
            }
        }
    }

    fn loadGlobalHooks(self: *RuntimeContext, jakefile: *const parser.Jakefile) !void {
        for (jakefile.global_pre_hooks) |hook| {
            try self.hook_runner.addGlobalHook(hook);
        }
        for (jakefile.global_post_hooks) |hook| {
            try self.hook_runner.addGlobalHook(hook);
        }
        for (jakefile.global_on_error_hooks) |hook| {
            try self.hook_runner.addGlobalHook(hook);
        }
    }
};

fn stripQuotes(value: []const u8) []const u8 {
    return parser.stripQuotes(value);
}

fn printRuntimeWarning(prefix: []const u8, err: anyerror) void {
    const stderr = compat.getStdErr();
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "warning: {s}: {s}\n", .{ prefix, @errorName(err) }) catch return;
    stderr.writeAll(msg) catch {};
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

test "Context.emitOutput calls callback with correct args" {
    const TestCallback = struct {
        var last_line: ?[]const u8 = null;
        var last_is_stderr: ?bool = null;
        var call_count: usize = 0;

        fn callback(_: *anyopaque, line: []const u8, is_stderr: bool) void {
            last_line = line;
            last_is_stderr = is_stderr;
            call_count += 1;
        }

        fn reset() void {
            last_line = null;
            last_is_stderr = null;
            call_count = 0;
        }
    };

    TestCallback.reset();

    var dummy_ctx: u8 = 0;
    var ctx = Context.init();
    ctx.output_callback = TestCallback.callback;
    ctx.output_callback_ctx = &dummy_ctx;

    ctx.emitOutput("hello", false);
    try std.testing.expectEqualStrings("hello", TestCallback.last_line.?);
    try std.testing.expect(!TestCallback.last_is_stderr.?);
    try std.testing.expectEqual(@as(usize, 1), TestCallback.call_count);

    ctx.emitOutput("error", true);
    try std.testing.expectEqualStrings("error", TestCallback.last_line.?);
    try std.testing.expect(TestCallback.last_is_stderr.?);
    try std.testing.expectEqual(@as(usize, 2), TestCallback.call_count);
}

test "Context.emitOutput does nothing without callback" {
    var ctx = Context.init();
    // Should not crash
    ctx.emitOutput("test", false);
}

test "Context.emitOutput does nothing with callback but no ctx" {
    const TestCallback = struct {
        var called: bool = false;
        fn callback(_: *anyopaque, _: []const u8, _: bool) void {
            called = true;
        }
    };

    TestCallback.called = false;
    var ctx = Context.init();
    ctx.output_callback = TestCallback.callback;
    ctx.output_callback_ctx = null; // No context

    ctx.emitOutput("test", false);
    try std.testing.expect(!TestCallback.called); // Should not be called
}

test "Context.hasOutputCallback returns correct value" {
    var ctx = Context.init();
    try std.testing.expect(!ctx.hasOutputCallback());

    const TestCallback = struct {
        fn callback(_: *anyopaque, _: []const u8, _: bool) void {}
    };
    ctx.output_callback = TestCallback.callback;
    try std.testing.expect(ctx.hasOutputCallback());
}

test "Context.emitCommand calls callback with correct args" {
    const TestCallback = struct {
        var last_task: ?[]const u8 = null;
        var last_command: ?[]const u8 = null;
        var call_count: usize = 0;

        fn callback(_: *anyopaque, task_name: []const u8, command: []const u8) void {
            last_task = task_name;
            last_command = command;
            call_count += 1;
        }

        fn reset() void {
            last_task = null;
            last_command = null;
            call_count = 0;
        }
    };

    TestCallback.reset();

    var dummy_ctx: u8 = 0;
    var ctx = Context.init();
    ctx.command_callback = TestCallback.callback;
    ctx.command_callback_ctx = &dummy_ctx;

    ctx.emitCommand("build", "zig build");
    try std.testing.expectEqualStrings("build", TestCallback.last_task.?);
    try std.testing.expectEqualStrings("zig build", TestCallback.last_command.?);
    try std.testing.expectEqual(@as(usize, 1), TestCallback.call_count);
}

test "Context.hasCommandCallback returns correct value" {
    var ctx = Context.init();
    try std.testing.expect(!ctx.hasCommandCallback());

    const TestCallback = struct {
        fn callback(_: *anyopaque, _: []const u8, _: []const u8) void {}
    };
    ctx.command_callback = TestCallback.callback;
    try std.testing.expect(ctx.hasCommandCallback());
}

test "Context.emitEvent forwards events to emitter" {
    const Receiver = struct {
        count: usize = 0,
        last_name: ?[]const u8 = null,

        pub fn onEvent(self: *@This(), event: event_emitter_mod.Event) void {
            switch (event) {
                .task_start => |task| {
                    self.count += 1;
                    self.last_name = task.name;
                },
                else => {},
            }
        }
    };

    var receiver = Receiver{};
    var ctx = Context.init();
    ctx.event_emitter = event_emitter_mod.EventEmitter.init(&receiver);

    ctx.emitEvent(.{ .task_start = .{ .name = "build", .deps = &.{} } });
    try std.testing.expectEqual(@as(usize, 1), receiver.count);
    try std.testing.expectEqualStrings("build", receiver.last_name.?);
}

test "Context.hasEventEmitter returns correct value" {
    var ctx = Context.init();
    try std.testing.expect(!ctx.hasEventEmitter());

    var receiver = event_emitter_mod.NullEmitter{};
    ctx.event_emitter = event_emitter_mod.EventEmitter.init(&receiver);
    try std.testing.expect(ctx.hasEventEmitter());
}

test "Context.isCancelled returns false by default" {
    const ctx = Context.init();
    try std.testing.expect(!ctx.isCancelled());
}

test "Context.isCancelled reads from cancellation flag" {
    var flag = std.atomic.Value(bool).init(true);
    var ctx = Context.init();
    ctx.cancellation_flag = &flag;

    // flag=true means running, so not cancelled
    try std.testing.expect(!ctx.isCancelled());

    // flag=false means stopped/cancelled
    flag.store(false, .release);
    try std.testing.expect(ctx.isCancelled());
}

test "RuntimeContext.configure propagates dotenv load errors" {
    if (builtin.os.tag == .windows) return;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("envdir");

    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    const source =
        \\@dotenv envdir
        \\task build:
        \\    echo "build"
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var index = try jakefile_index.JakefileIndex.build(std.testing.allocator, &jakefile);
    defer index.deinit();

    var runtime = RuntimeContext.init(std.testing.allocator);
    defer runtime.deinit();

    const result = runtime.configure(&jakefile, &index);
    _ = result catch |err| {
        try std.testing.expect(err == error.IsDir or err == error.AccessDenied);
        return;
    };
    return error.TestExpectedError;
}
