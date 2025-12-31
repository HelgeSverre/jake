// color.zig - ANSI color output with NO_COLOR/CLICOLOR support
// Implements: https://no-color.org/ and CLICOLOR standard

const std = @import("std");
const compat = @import("compat.zig");

/// Color configuration - provides ANSI codes or empty strings based on settings
pub const Color = struct {
    enabled: bool,

    // Bold colors (for emphasis)
    pub fn red(self: Color) []const u8 {
        return if (self.enabled) "\x1b[1;31m" else "";
    }

    pub fn yellow(self: Color) []const u8 {
        return if (self.enabled) "\x1b[1;33m" else "";
    }

    pub fn cyan(self: Color) []const u8 {
        return if (self.enabled) "\x1b[1;36m" else "";
    }

    pub fn blue(self: Color) []const u8 {
        return if (self.enabled) "\x1b[1;34m" else "";
    }

    pub fn green(self: Color) []const u8 {
        return if (self.enabled) "\x1b[1;32m" else "";
    }

    pub fn bold(self: Color) []const u8 {
        return if (self.enabled) "\x1b[1m" else "";
    }

    // Regular colors (non-bold)
    pub fn cyanRegular(self: Color) []const u8 {
        return if (self.enabled) "\x1b[36m" else "";
    }

    pub fn yellowRegular(self: Color) []const u8 {
        return if (self.enabled) "\x1b[33m" else "";
    }

    pub fn greenRegular(self: Color) []const u8 {
        return if (self.enabled) "\x1b[32m" else "";
    }

    pub fn dim(self: Color) []const u8 {
        return if (self.enabled) "\x1b[90m" else "";
    }

    pub fn reset(self: Color) []const u8 {
        return if (self.enabled) "\x1b[0m" else "";
    }

    /// Error prefix with color: "error: " in red
    pub fn errPrefix(self: Color) []const u8 {
        return if (self.enabled) "\x1b[1;31merror:\x1b[0m " else "error: ";
    }

    /// Warning prefix with color: "warning: " in yellow
    pub fn warnPrefix(self: Color) []const u8 {
        return if (self.enabled) "\x1b[1;33mwarning:\x1b[0m " else "warning: ";
    }

    // =========================================================================
    // Writer methods - write styled text directly to a writer
    // =========================================================================

    /// Write styled text: color + text + reset
    pub fn writeStyled(self: Color, writer: anytype, text: []const u8, comptime style: Style) !void {
        try writer.writeAll(self.get(style));
        try writer.writeAll(text);
        try writer.writeAll(self.reset());
    }

    /// Get color code for a style
    pub fn get(self: Color, comptime style: Style) []const u8 {
        return switch (style) {
            .bold => self.bold(),
            .red => self.red(),
            .yellow => self.yellow(),
            .green => self.green(),
            .cyan => self.cyan(),
            .blue => self.blue(),
            .dim => self.dim(),
        };
    }

    // Convenience methods for common styles
    pub fn writeBold(self: Color, writer: anytype, text: []const u8) !void {
        return self.writeStyled(writer, text, .bold);
    }

    pub fn writeRed(self: Color, writer: anytype, text: []const u8) !void {
        return self.writeStyled(writer, text, .red);
    }

    pub fn writeCyan(self: Color, writer: anytype, text: []const u8) !void {
        return self.writeStyled(writer, text, .cyan);
    }

    pub fn writeGreen(self: Color, writer: anytype, text: []const u8) !void {
        return self.writeStyled(writer, text, .green);
    }

    pub fn writeYellow(self: Color, writer: anytype, text: []const u8) !void {
        return self.writeStyled(writer, text, .yellow);
    }
};

/// Available color styles
pub const Style = enum {
    bold,
    red,
    yellow,
    green,
    cyan,
    blue,
    dim,
};

/// Initialize Color based on environment variables and TTY detection
pub fn init() Color {
    return .{ .enabled = shouldUseColor() };
}

/// Create a Color with explicit enabled state (for testing)
pub fn withEnabled(enabled: bool) Color {
    return .{ .enabled = enabled };
}

/// Determine if color output should be enabled
/// Priority: NO_COLOR > CLICOLOR_FORCE > CLICOLOR > TTY detection
pub fn shouldUseColor() bool {
    // NO_COLOR takes precedence - any value (including empty) disables color
    // per https://no-color.org/
    if (std.posix.getenv("NO_COLOR")) |_| return false;

    // CLICOLOR_FORCE enables color even without TTY
    if (std.posix.getenv("CLICOLOR_FORCE")) |v| {
        if (v.len > 0 and v[0] != '0') return true;
    }

    // CLICOLOR=0 disables color
    if (std.posix.getenv("CLICOLOR")) |v| {
        if (v.len > 0 and v[0] == '0') return false;
    }

    // Default: enable if stderr is TTY
    return compat.getStdErr().isTty();
}

// ============================================================================
// Tests
// ============================================================================

test "Color.red returns ANSI code when enabled" {
    const color = withEnabled(true);
    try std.testing.expectEqualStrings("\x1b[1;31m", color.red());
}

test "Color.red returns empty string when disabled" {
    const color = withEnabled(false);
    try std.testing.expectEqualStrings("", color.red());
}

test "Color.reset returns ANSI code when enabled" {
    const color = withEnabled(true);
    try std.testing.expectEqualStrings("\x1b[0m", color.reset());
}

test "Color.reset returns empty string when disabled" {
    const color = withEnabled(false);
    try std.testing.expectEqualStrings("", color.reset());
}

test "Color.errPrefix returns colored prefix when enabled" {
    const color = withEnabled(true);
    try std.testing.expectEqualStrings("\x1b[1;31merror:\x1b[0m ", color.errPrefix());
}

test "Color.errPrefix returns plain prefix when disabled" {
    const color = withEnabled(false);
    try std.testing.expectEqualStrings("error: ", color.errPrefix());
}

test "all color methods return empty strings when disabled" {
    const color = withEnabled(false);
    try std.testing.expectEqualStrings("", color.red());
    try std.testing.expectEqualStrings("", color.yellow());
    try std.testing.expectEqualStrings("", color.cyan());
    try std.testing.expectEqualStrings("", color.blue());
    try std.testing.expectEqualStrings("", color.green());
    try std.testing.expectEqualStrings("", color.bold());
    try std.testing.expectEqualStrings("", color.dim());
    try std.testing.expectEqualStrings("", color.reset());
}

test "all color methods return ANSI codes when enabled" {
    const color = withEnabled(true);
    try std.testing.expect(color.red().len > 0);
    try std.testing.expect(color.yellow().len > 0);
    try std.testing.expect(color.cyan().len > 0);
    try std.testing.expect(color.blue().len > 0);
    try std.testing.expect(color.green().len > 0);
    try std.testing.expect(color.bold().len > 0);
    try std.testing.expect(color.dim().len > 0);
    try std.testing.expect(color.reset().len > 0);
}

test "writeBold writes styled text when enabled" {
    const color = withEnabled(true);
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try color.writeBold(stream.writer(), "Hello");
    try std.testing.expectEqualStrings("\x1b[1mHello\x1b[0m", stream.getWritten());
}

test "writeBold writes plain text when disabled" {
    const color = withEnabled(false);
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try color.writeBold(stream.writer(), "Hello");
    try std.testing.expectEqualStrings("Hello", stream.getWritten());
}

test "writeStyled works with different styles" {
    const color = withEnabled(true);
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try color.writeStyled(stream.writer(), "Test", .red);
    try std.testing.expectEqualStrings("\x1b[1;31mTest\x1b[0m", stream.getWritten());
}

test "Color.get returns correct code for each style" {
    const color = withEnabled(true);
    try std.testing.expectEqualStrings(color.bold(), color.get(.bold));
    try std.testing.expectEqualStrings(color.red(), color.get(.red));
    try std.testing.expectEqualStrings(color.yellow(), color.get(.yellow));
    try std.testing.expectEqualStrings(color.green(), color.get(.green));
    try std.testing.expectEqualStrings(color.cyan(), color.get(.cyan));
    try std.testing.expectEqualStrings(color.blue(), color.get(.blue));
    try std.testing.expectEqualStrings(color.dim(), color.get(.dim));
}
