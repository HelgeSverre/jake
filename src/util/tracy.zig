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

// Import ztracy only when enabled
const ztracy = if (enabled) @import("ztracy") else undefined;

/// A profiling zone that measures execution time.
/// When Tracy is disabled, this is a zero-cost no-op struct.
pub const Zone = if (enabled)
    ztracy.ZoneCtx
else
    struct {
        pub inline fn End(self: @This()) void {
            _ = self;
        }

        pub inline fn Name(self: @This(), name: [*:0]const u8) void {
            _ = self;
            _ = name;
        }

        pub inline fn Text(self: @This(), text: []const u8) void {
            _ = self;
            _ = text;
        }

        pub inline fn Color(self: @This(), color: u32) void {
            _ = self;
            _ = color;
        }

        pub inline fn Value(self: @This(), value: u64) void {
            _ = self;
            _ = value;
        }
    };

/// Begin a named profiling zone with default color (green).
/// When Tracy is disabled, returns a no-op zone.
pub inline fn zone(comptime name: [:0]const u8) Zone {
    if (enabled) {
        return ztracy.ZoneNC(@src(), name, Color.green);
    }
    return .{};
}

/// Begin a named profiling zone with custom color.
pub inline fn zoneC(comptime name: [:0]const u8, color: u32) Zone {
    if (enabled) {
        return ztracy.ZoneNC(@src(), name, color);
    }
    return .{};
}

/// Begin a profiling zone with source location info.
pub inline fn zoneN(comptime src: std.builtin.SourceLocation) Zone {
    if (enabled) {
        return ztracy.Zone(src);
    }
    return .{};
}

/// Mark an allocation event.
pub inline fn alloc(ptr: ?*anyopaque, size: usize) void {
    if (enabled) {
        ztracy.Alloc(ptr, size);
    }
}

/// Mark a deallocation event.
pub inline fn free(ptr: ?*anyopaque, size: usize) void {
    if (enabled) {
        ztracy.Free(ptr, size);
    }
}

/// Send a message to Tracy.
pub inline fn message(text: []const u8) void {
    if (enabled) {
        ztracy.Message(text);
    }
}

/// Send a colored message to Tracy.
pub inline fn messageColor(text: []const u8, color: u32) void {
    if (enabled) {
        ztracy.MessageC(text, color);
    }
}

/// Mark the current frame boundary.
pub inline fn frameMark() void {
    if (enabled) {
        ztracy.FrameMark(null);
    }
}

/// Mark a named frame boundary.
pub inline fn frameMarkNamed(comptime name: [:0]const u8) void {
    if (enabled) {
        ztracy.FrameMark(name);
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
