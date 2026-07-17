// event_emitter.zig - Event types and emitter interface for web UI streaming
// Used to decouple executor from web UI - executor emits events, web server broadcasts them

const std = @import("std");

/// Events emitted during Jake execution lifecycle
pub const Event = union(enum) {
    /// Jakefile has been loaded and parsed
    jakefile_loaded: JakefileLoadedEvent,
    /// A task is about to start executing
    task_start: TaskStartEvent,
    /// A command within a task is starting
    command_start: CommandStartEvent,
    /// Output line from a running command
    command_output: CommandOutputEvent,
    /// A task has completed (success or failure)
    task_complete: TaskCompleteEvent,
    /// Execution summary after all tasks
    execution_summary: ExecutionSummaryEvent,
};

pub const RecipeInfo = struct {
    name: []const u8,
    desc: []const u8,
    group: []const u8,
    deps: []const []const u8,
    params: []const []const u8,
    is_default: bool,
    is_hidden: bool,
};

pub const VariableInfo = struct {
    name: []const u8,
    value: []const u8,
};

pub const JakefileLoadedEvent = struct {
    recipes: []const RecipeInfo,
    variables: []const VariableInfo,
};

pub const TaskStartEvent = struct {
    name: []const u8,
    deps: []const []const u8,
};

pub const CommandStartEvent = struct {
    task: []const u8,
    command: []const u8,
};

pub const CommandOutputEvent = struct {
    task: []const u8,
    line: []const u8,
    is_stderr: bool,
};

pub const TaskCompleteEvent = struct {
    name: []const u8,
    success: bool,
    duration_ms: u64,
};

pub const ExecutionSummaryEvent = struct {
    tasks_run: usize,
    tasks_failed: usize,
    total_ms: u64,
};

/// Interface for event emission - allows different implementations (web, logging, etc.)
pub const EventEmitter = struct {
    ptr: *anyopaque,
    emitFn: *const fn (*anyopaque, Event) void,

    pub fn emit(self: EventEmitter, event: Event) void {
        self.emitFn(self.ptr, event);
    }

    /// Create an EventEmitter from any type that has an `onEvent` method
    pub fn init(ptr: anytype) EventEmitter {
        const Ptr = @TypeOf(ptr);
        const ptr_info = @typeInfo(Ptr);

        if (ptr_info != .pointer) @compileError("ptr must be a pointer");
        if (ptr_info.pointer.size != .one) @compileError("ptr must be a single-item pointer");

        const gen = struct {
            fn emitFn(pointer: *anyopaque, event: Event) void {
                const self: Ptr = @ptrCast(@alignCast(pointer));
                self.onEvent(event);
            }
        };

        return .{
            .ptr = ptr,
            .emitFn = gen.emitFn,
        };
    }
};

/// No-op emitter for when no event handling is needed
pub const NullEmitter = struct {
    pub fn onEvent(_: *NullEmitter, _: Event) void {}
};

// ============================================================================
// Tests
// ============================================================================

test "EventEmitter can emit events" {
    const TestReceiver = struct {
        received_count: usize = 0,

        pub fn onEvent(self: *@This(), _: Event) void {
            self.received_count += 1;
        }
    };

    var receiver = TestReceiver{};
    const emitter = EventEmitter.init(&receiver);

    emitter.emit(.{ .task_start = .{ .name = "build", .deps = &.{} } });
    emitter.emit(.{ .task_complete = .{ .name = "build", .success = true, .duration_ms = 100 } });

    try std.testing.expectEqual(@as(usize, 2), receiver.received_count);
}

test "NullEmitter does nothing" {
    var null_emitter = NullEmitter{};
    const emitter = EventEmitter.init(&null_emitter);

    // Should not crash
    emitter.emit(.{ .task_start = .{ .name = "test", .deps = &.{} } });
}

test "Event union can hold different event types" {
    const events = [_]Event{
        .{ .task_start = .{ .name = "build", .deps = &.{} } },
        .{ .command_start = .{ .task = "build", .command = "zig build" } },
        .{ .command_output = .{ .task = "build", .line = "Compiling...", .is_stderr = false } },
        .{ .task_complete = .{ .name = "build", .success = true, .duration_ms = 1500 } },
        .{ .execution_summary = .{ .tasks_run = 1, .tasks_failed = 0, .total_ms = 1500 } },
    };

    for (events) |event| {
        switch (event) {
            .jakefile_loaded => {},
            .task_start => |e| try std.testing.expect(e.name.len > 0),
            .command_start => |e| try std.testing.expect(e.command.len > 0),
            .command_output => |e| try std.testing.expect(e.line.len > 0),
            .task_complete => |e| try std.testing.expect(e.name.len > 0),
            .execution_summary => |e| try std.testing.expect(e.tasks_run >= e.tasks_failed),
        }
    }
}

test "EventEmitter captures specific event data" {
    const TestReceiver = struct {
        last_task_name: ?[]const u8 = null,
        last_success: ?bool = null,
        last_duration: ?u64 = null,

        pub fn onEvent(self: *@This(), event: Event) void {
            switch (event) {
                .task_complete => |e| {
                    self.last_task_name = e.name;
                    self.last_success = e.success;
                    self.last_duration = e.duration_ms;
                },
                else => {},
            }
        }
    };

    var receiver = TestReceiver{};
    const emitter = EventEmitter.init(&receiver);

    emitter.emit(.{ .task_complete = .{ .name = "test-task", .success = true, .duration_ms = 250 } });

    try std.testing.expectEqualStrings("test-task", receiver.last_task_name.?);
    try std.testing.expect(receiver.last_success.?);
    try std.testing.expectEqual(@as(u64, 250), receiver.last_duration.?);
}

test "EventEmitter handles failure events" {
    const TestReceiver = struct {
        failure_count: usize = 0,

        pub fn onEvent(self: *@This(), event: Event) void {
            switch (event) {
                .task_complete => |e| {
                    if (!e.success) self.failure_count += 1;
                },
                else => {},
            }
        }
    };

    var receiver = TestReceiver{};
    const emitter = EventEmitter.init(&receiver);

    emitter.emit(.{ .task_complete = .{ .name = "pass", .success = true, .duration_ms = 100 } });
    emitter.emit(.{ .task_complete = .{ .name = "fail1", .success = false, .duration_ms = 50 } });
    emitter.emit(.{ .task_complete = .{ .name = "fail2", .success = false, .duration_ms = 75 } });

    try std.testing.expectEqual(@as(usize, 2), receiver.failure_count);
}

test "command_output distinguishes stderr" {
    const TestReceiver = struct {
        stderr_count: usize = 0,
        stdout_count: usize = 0,

        pub fn onEvent(self: *@This(), event: Event) void {
            switch (event) {
                .command_output => |e| {
                    if (e.is_stderr) {
                        self.stderr_count += 1;
                    } else {
                        self.stdout_count += 1;
                    }
                },
                else => {},
            }
        }
    };

    var receiver = TestReceiver{};
    const emitter = EventEmitter.init(&receiver);

    emitter.emit(.{ .command_output = .{ .task = "test", .line = "info", .is_stderr = false } });
    emitter.emit(.{ .command_output = .{ .task = "test", .line = "warning", .is_stderr = true } });
    emitter.emit(.{ .command_output = .{ .task = "test", .line = "error", .is_stderr = true } });
    emitter.emit(.{ .command_output = .{ .task = "test", .line = "done", .is_stderr = false } });

    try std.testing.expectEqual(@as(usize, 2), receiver.stdout_count);
    try std.testing.expectEqual(@as(usize, 2), receiver.stderr_count);
}

test "execution_summary tracks totals" {
    const summary = ExecutionSummaryEvent{
        .tasks_run = 10,
        .tasks_failed = 2,
        .total_ms = 5000,
    };

    try std.testing.expectEqual(@as(usize, 10), summary.tasks_run);
    try std.testing.expectEqual(@as(usize, 2), summary.tasks_failed);
    try std.testing.expectEqual(@as(u64, 5000), summary.total_ms);
    // Calculate success count
    try std.testing.expectEqual(@as(usize, 8), summary.tasks_run - summary.tasks_failed);
}

test "jakefile_loaded event contains recipe info" {
    const recipe_info = RecipeInfo{
        .name = "build",
        .desc = "Build the project",
        .group = "dev",
        .deps = &.{ "clean", "prepare" },
        .params = &.{"mode"},
        .is_default = true,
        .is_hidden = false,
    };

    try std.testing.expectEqualStrings("build", recipe_info.name);
    try std.testing.expectEqualStrings("Build the project", recipe_info.desc);
    try std.testing.expect(recipe_info.is_default);
    try std.testing.expect(!recipe_info.is_hidden);
    try std.testing.expectEqual(@as(usize, 2), recipe_info.deps.len);
    try std.testing.expectEqual(@as(usize, 1), recipe_info.params.len);
}
