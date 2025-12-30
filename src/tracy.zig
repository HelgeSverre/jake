//! Tracy profiler integration wrapper.
//!
//! This module provides a zero-overhead abstraction over Tracy profiling.
//! When Tracy is disabled (default), all operations are no-ops.
//! Enable with: `zig build -Dtracy=true`

const std = @import("std");

// Check if Tracy is enabled via build options
pub const enabled = blk: {
    if (@hasDecl(@import("root"), "tracy_options")) {
        break :blk @import("tracy_options").tracy_enabled;
    }
    break :blk false;
};

// Import Tracy only when enabled
const zig_tracy = if (enabled) @import("zig_tracy") else struct {};

/// A profiling zone that measures execution time.
/// When Tracy is disabled, this is a zero-cost no-op struct.
pub const Zone = if (enabled)
    zig_tracy.ZoneCtx
else
    struct {
        pub inline fn end(self: @This()) void {
            _ = self;
        }

        pub inline fn setName(self: @This(), name: [*:0]const u8) void {
            _ = self;
            _ = name;
        }

        pub inline fn setText(self: @This(), text: []const u8) void {
            _ = self;
            _ = text;
        }

        pub inline fn setColor(self: @This(), color: u32) void {
            _ = self;
            _ = color;
        }

        pub inline fn setValue(self: @This(), value: u64) void {
            _ = self;
            _ = value;
        }
    };

/// Begin a named profiling zone.
/// When Tracy is disabled, returns a no-op zone.
pub inline fn zone(comptime name: [:0]const u8) Zone {
    if (enabled) {
        return zig_tracy.zone(.{ .name = name });
    }
    return .{};
}

/// Begin a profiling zone with source location info.
pub inline fn zoneN(comptime src: std.builtin.SourceLocation) Zone {
    if (enabled) {
        return zig_tracy.zone(.{ .src = src });
    }
    return .{};
}

/// Mark an allocation event.
pub inline fn alloc(ptr: ?*anyopaque, size: usize) void {
    if (enabled) {
        zig_tracy.alloc(ptr, size);
    }
}

/// Mark a deallocation event.
pub inline fn free(ptr: ?*anyopaque) void {
    if (enabled) {
        zig_tracy.free(ptr);
    }
}

/// Send a message to Tracy.
pub inline fn message(text: []const u8) void {
    if (enabled) {
        zig_tracy.message(text);
    }
}

/// Send a colored message to Tracy.
pub inline fn messageColor(text: []const u8, color: u32) void {
    if (enabled) {
        zig_tracy.messageColor(text, color);
    }
}

/// Mark the current frame boundary.
pub inline fn frameMark() void {
    if (enabled) {
        zig_tracy.frameMark(null);
    }
}

/// Mark a named frame boundary.
pub inline fn frameMarkNamed(comptime name: [:0]const u8) void {
    if (enabled) {
        zig_tracy.frameMark(name);
    }
}

// Common color constants for Tracy visualization
pub const Color = struct {
    pub const red: u32 = 0xFF0000;
    pub const green: u32 = 0x00FF00;
    pub const blue: u32 = 0x0000FF;
    pub const yellow: u32 = 0xFFFF00;
    pub const orange: u32 = 0xFFA500;
    pub const purple: u32 = 0x800080;
    pub const cyan: u32 = 0x00FFFF;
    pub const white: u32 = 0xFFFFFF;
    pub const gray: u32 = 0x808080;
};
