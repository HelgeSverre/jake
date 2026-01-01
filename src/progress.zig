// progress.zig - Animated progress indicators for CLI output
//
// Provides spinner animations during task execution with TTY-aware fallback.
// Used by executor.zig for sequential execution and parallel.zig for parallel.

const std = @import("std");
const compat = @import("compat.zig");
const color_mod = @import("color.zig");

/// Animated spinner for a single task (sequential execution)
/// Shows "⠋ name" during execution, then "✓ name 1.82s" on completion
pub const Spinner = struct {
    label: []const u8,
    color: color_mod.Color,
    is_tty: bool,

    done: std.atomic.Value(bool),
    thread: ?std.Thread,

    pub fn init(label: []const u8, color: color_mod.Color) Spinner {
        return .{
            .label = label,
            .color = color,
            .is_tty = compat.getStdErr().isTty(),
            .done = std.atomic.Value(bool).init(false),
            .thread = null,
        };
    }

    /// Start the spinner animation (non-blocking)
    /// For TTY: spawns a background thread to animate
    /// For non-TTY: prints static header line
    pub fn start(self: *Spinner) void {
        if (!self.is_tty) {
            return;
        }

        self.done.store(false, .seq_cst);
        self.thread = std.Thread.spawn(.{}, Spinner.loop, .{self}) catch null;
    }

    /// Animation loop running in background thread
    fn loop(self: *Spinner) void {
        const stderr = compat.getStdErr();
        var frame_idx: usize = 0;

        while (!self.done.load(.seq_cst)) {
            const frames = color_mod.symbols.spinner_frames;
            const frame = frames[frame_idx % frames.len];
            frame_idx +%= 1;

            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "\r   {s}{s}{s} {s}\x1b[K", .{
                self.color.jakeRose(),
                frame,
                self.color.reset(),
                self.label,
            }) catch continue;
            stderr.writeAll(msg) catch {};

            std.Thread.sleep(80 * std.time.ns_per_ms);
        }
    }

    /// Stop the spinner and print final status line
    /// success=true: ✓ name (duration)
    /// success=false: ✗ name (duration)
    pub fn stop(self: *Spinner, success: bool, duration_ns: i128) void {
        if (self.is_tty) {
            if (self.thread) |t| {
                self.done.store(true, .seq_cst);
                t.join();
            }
            const stderr = compat.getStdErr();
            stderr.writeAll("\r\x1b[K") catch {};
        }

        printCompletionLine(self.label, success, duration_ns, self.color);
    }
};

/// Print a completion line: "   ✓ name     1.82s" or "   ✗ name     1.82s"
pub fn printCompletionLine(name: []const u8, success: bool, duration_ns: i128, color: color_mod.Color) void {
    const stderr = compat.getStdErr();
    const duration_ms = @divFloor(duration_ns, 1_000_000);
    const duration_s = @as(f64, @floatFromInt(duration_ms)) / 1000.0;

    const symbol = if (success) color_mod.symbols.success else color_mod.symbols.failure;
    const sym_color = if (success) color.successGreen() else color.errorRed();

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "   {s}{s}{s} {s}     {s}{d:.2}s{s}\n", .{
        sym_color,
        symbol,
        color.reset(),
        name,
        color.muted(),
        duration_s,
        color.reset(),
    }) catch return;
    stderr.writeAll(msg) catch {};
}

/// Check if stderr is a TTY (for animation support)
pub fn isTty() bool {
    return compat.getStdErr().isTty();
}

// ============================================================================
// Tests
// ============================================================================

test "Spinner.init creates spinner with label" {
    const color = color_mod.withEnabled(false);
    const spinner = Spinner.init("test", color);
    try std.testing.expectEqualStrings("test", spinner.label);
    try std.testing.expect(!spinner.done.load(.seq_cst));
}

test "printCompletionLine formats success correctly" {
    const color = color_mod.withEnabled(false);
    printCompletionLine("build", true, 1_820_000_000, color);
}

test "printCompletionLine formats failure correctly" {
    const color = color_mod.withEnabled(false);
    printCompletionLine("test", false, 500_000_000, color);
}
