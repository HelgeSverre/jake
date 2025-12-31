// context.zig - Shared execution context passed through app lifecycle
// Consolidates CLI flags and runtime configuration into a single struct

const std = @import("std");
const color_mod = @import("color.zig");

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
