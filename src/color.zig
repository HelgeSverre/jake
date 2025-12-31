// color.zig - ANSI color output with NO_COLOR/CLICOLOR support
// Implements: https://no-color.org/ and CLICOLOR standard
// See docs/CLI_DESIGN.md for the full design specification

const std = @import("std");
const compat = @import("compat.zig");

// ============================================================================
// ANSI Escape Codes
// ============================================================================

/// Raw ANSI escape codes - use these for comptime string concatenation
pub const codes = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";

    // Standard 16-color codes (fallback)
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";

    // Bold variants
    pub const bold_red = "\x1b[1;31m";
    pub const bold_green = "\x1b[1;32m";
    pub const bold_yellow = "\x1b[1;33m";
    pub const bold_blue = "\x1b[1;34m";
    pub const bold_magenta = "\x1b[1;35m";
    pub const bold_cyan = "\x1b[1;36m";

    // Dim/muted
    pub const dim_white = "\x1b[2;37m";
    pub const gray = "\x1b[90m";

    // Brand colors (true color / 24-bit) - see docs/CLI_DESIGN.md
    pub const jake_rose = "\x1b[38;2;244;63;94m"; // #f43f5e
    pub const success_green = "\x1b[38;2;34;197;94m"; // #22c55e
    pub const error_red = "\x1b[38;2;239;68;68m"; // #ef4444
    pub const warning_yellow = "\x1b[38;2;234;179;8m"; // #eab308
    pub const info_blue = "\x1b[38;2;96;165;250m"; // #60a5fa
    pub const muted_gray = "\x1b[38;2;113;113;122m"; // #71717a
};

/// Unicode symbols for CLI output
pub const symbols = struct {
    pub const arrow = "→";
    pub const success = "✓";
    pub const failure = "✗";
    pub const warning = "~";
    pub const logo = "{j}";
};

// ============================================================================
// ColoredText - Formattable wrapper for std.fmt
// ============================================================================

/// A text string wrapped with color codes, usable with std.fmt {f}
pub const ColoredText = struct {
    prefix: []const u8,
    text: []const u8,
    suffix: []const u8,

    /// Format implementation for std.fmt {f} - outputs prefix + text + suffix
    /// Note: Zig 0.15+ uses simplified format signature with just writer
    pub fn format(self: ColoredText, writer: anytype) !void {
        try writer.writeAll(self.prefix);
        try writer.writeAll(self.text);
        try writer.writeAll(self.suffix);
    }
};

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

    // Brand colors (24-bit true color) - see docs/CLI_DESIGN.md
    pub fn jakeRose(self: Color) []const u8 {
        return if (self.enabled) codes.jake_rose else "";
    }

    pub fn muted(self: Color) []const u8 {
        return if (self.enabled) codes.muted_gray else "";
    }

    pub fn successGreen(self: Color) []const u8 {
        return if (self.enabled) codes.success_green else "";
    }

    pub fn errorRed(self: Color) []const u8 {
        return if (self.enabled) codes.error_red else "";
    }

    pub fn warningYellow(self: Color) []const u8 {
        return if (self.enabled) codes.warning_yellow else "";
    }

    pub fn infoBlue(self: Color) []const u8 {
        return if (self.enabled) codes.info_blue else "";
    }

    /// Error prefix with color: "error: " in brand red (#ef4444)
    pub fn errPrefix(self: Color) []const u8 {
        return if (self.enabled) codes.error_red ++ "error:" ++ codes.reset ++ " " else "error: ";
    }

    /// Warning prefix with color: "warning: " in brand yellow (#eab308)
    pub fn warnPrefix(self: Color) []const u8 {
        return if (self.enabled) codes.warning_yellow ++ "warning:" ++ codes.reset ++ " " else "warning: ";
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

    // =========================================================================
    // ColoredText methods - return formattable wrappers for std.fmt {}
    // =========================================================================

    /// Wrap text in a color code, returning a ColoredText usable with std.fmt {}
    pub fn styled(self: Color, text: []const u8, comptime color_code: []const u8) ColoredText {
        return .{
            .prefix = if (self.enabled) color_code else "",
            .text = text,
            .suffix = if (self.enabled) codes.reset else "",
        };
    }

    /// Styled text in red (bold) - for errors
    pub fn styledRed(self: Color, text: []const u8) ColoredText {
        return self.styled(text, codes.bold_red);
    }

    /// Styled text in green (bold) - for success
    pub fn styledGreen(self: Color, text: []const u8) ColoredText {
        return self.styled(text, codes.bold_green);
    }

    /// Styled text in yellow (bold) - for warnings
    pub fn styledYellow(self: Color, text: []const u8) ColoredText {
        return self.styled(text, codes.bold_yellow);
    }

    /// Styled text in cyan (bold) - for highlights
    pub fn styledCyan(self: Color, text: []const u8) ColoredText {
        return self.styled(text, codes.bold_cyan);
    }

    /// Styled text in blue (bold) - for info
    pub fn styledBlue(self: Color, text: []const u8) ColoredText {
        return self.styled(text, codes.bold_blue);
    }

    /// Styled text in bold
    pub fn styledBold(self: Color, text: []const u8) ColoredText {
        return self.styled(text, codes.bold);
    }

    /// Styled text in dim/muted
    pub fn styledDim(self: Color, text: []const u8) ColoredText {
        return self.styled(text, codes.dim_white);
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
// Theme - Semantic color layer
// ============================================================================

/// Theme provides semantic color methods for CLI output.
/// Maps UI concepts (error, warning, recipe, hidden) to colors.
/// See docs/CLI_DESIGN.md for the full design specification.
pub const Theme = struct {
    color: Color,

    /// Initialize theme with automatic color detection
    pub fn init() Theme {
        return .{ .color = .{ .enabled = shouldUseColor() } };
    }

    /// Create theme with explicit color settings (for testing)
    pub fn withColor(color: Color) Theme {
        return .{ .color = color };
    }

    // =========================================================================
    // Semantic styles - return ColoredText for std.fmt {}
    // =========================================================================

    /// Error text - for failures and errors (brand: #ef4444)
    pub fn err(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.error_red);
    }

    /// Warning text - for warnings and skipped items (brand: #eab308)
    pub fn warning(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.warning_yellow);
    }

    /// Success text - for completion and checkmarks (brand: #22c55e)
    pub fn success(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.success_green);
    }

    /// Info text - for informational messages (brand: #60a5fa)
    pub fn info(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.info_blue);
    }

    /// Recipe name in headers - for "→ recipe_name" (brand: #f43f5e Jake Rose)
    pub fn recipeHeader(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.jake_rose);
    }

    /// Recipe name in listings - for recipe lists (brand: #f43f5e Jake Rose)
    pub fn recipeName(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.jake_rose);
    }

    /// Section header (bold) - for "Available recipes:"
    pub fn section(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.bold);
    }

    /// Group header - for group names in listings (brand: #f43f5e Jake Rose)
    pub fn group(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.jake_rose);
    }

    /// Hidden marker (dim) - for "(hidden)" labels
    pub fn hidden(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.dim_white);
    }

    /// Muted text - for comments, descriptions, secondary text (brand: #71717a)
    pub fn muted(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.muted_gray);
    }

    /// Directive keyword - for @needs, @confirm, etc. (brand: #eab308)
    pub fn directive(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.warning_yellow);
    }

    /// Hook label - for @pre, @post labels (brand: #22c55e)
    pub fn hook(self: Theme, text: []const u8) ColoredText {
        return self.color.styled(text, codes.success_green);
    }

    // =========================================================================
    // Pre-built prefixes
    // =========================================================================

    /// Error prefix: "error: " in red
    pub fn errPrefix(self: Theme) []const u8 {
        return self.color.errPrefix();
    }

    /// Warning prefix: "warning: " in yellow
    pub fn warnPrefix(self: Theme) []const u8 {
        return self.color.warnPrefix();
    }

    /// Watch mode prefix: "[watch] " (brand: #60a5fa Info Blue)
    pub fn watchPrefix(self: Theme) []const u8 {
        return if (self.color.enabled) codes.info_blue ++ "[watch]" ++ codes.reset ++ " " else "[watch] ";
    }

    /// Dry-run prefix: "[dry-run] " (brand: #60a5fa Info Blue)
    pub fn dryRunPrefix(self: Theme) []const u8 {
        return if (self.color.enabled) codes.info_blue ++ "[dry-run]" ++ codes.reset ++ " " else "[dry-run] ";
    }

    // =========================================================================
    // Symbol helpers
    // =========================================================================

    /// Success symbol with color: "✓" (brand: #22c55e)
    pub fn successSymbol(self: Theme) []const u8 {
        return if (self.color.enabled) codes.success_green ++ symbols.success ++ codes.reset else symbols.success;
    }

    /// Failure symbol with color: "✗" (brand: #ef4444)
    pub fn failureSymbol(self: Theme) []const u8 {
        return if (self.color.enabled) codes.error_red ++ symbols.failure ++ codes.reset else symbols.failure;
    }

    /// Arrow symbol with color: "→" (brand: #60a5fa Info Blue)
    pub fn arrowSymbol(self: Theme) []const u8 {
        return if (self.color.enabled) codes.info_blue ++ symbols.arrow ++ codes.reset else symbols.arrow;
    }
};

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
    // Uses brand error color #ef4444
    try std.testing.expectEqualStrings(codes.error_red ++ "error:" ++ codes.reset ++ " ", color.errPrefix());
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

// ============================================================================
// ColoredText tests
// ============================================================================

test "ColoredText formats with prefix and suffix when enabled" {
    const color = withEnabled(true);
    const ct = color.styledRed("error");

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try ct.format(stream.writer());

    try std.testing.expectEqualStrings("\x1b[1;31merror\x1b[0m", stream.getWritten());
}

test "ColoredText formats plain text when disabled" {
    const color = withEnabled(false);
    const ct = color.styledRed("error");

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try ct.format(stream.writer());

    try std.testing.expectEqualStrings("error", stream.getWritten());
}

test "Color.styled creates ColoredText with custom code" {
    const color = withEnabled(true);
    const ct = color.styled("test", codes.bold_cyan);

    try std.testing.expectEqualStrings(codes.bold_cyan, ct.prefix);
    try std.testing.expectEqualStrings("test", ct.text);
    try std.testing.expectEqualStrings(codes.reset, ct.suffix);
}

// ============================================================================
// Theme tests
// ============================================================================

test "Theme.init creates theme with color detection" {
    const theme = Theme.init();
    // Just verify it doesn't crash - actual color detection depends on environment
    _ = theme.err("test");
}

test "Theme.err returns ColoredText with brand error color" {
    const color = withEnabled(true);
    const theme = Theme.withColor(color);
    const ct = theme.err("error message");

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try ct.format(stream.writer());

    // Brand error red: #ef4444 = rgb(239, 68, 68)
    try std.testing.expectEqualStrings(codes.error_red ++ "error message" ++ codes.reset, stream.getWritten());
}

test "Theme.success returns ColoredText with brand success color" {
    const color = withEnabled(true);
    const theme = Theme.withColor(color);
    const ct = theme.success("done");

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try ct.format(stream.writer());

    // Brand success green: #22c55e = rgb(34, 197, 94)
    try std.testing.expectEqualStrings(codes.success_green ++ "done" ++ codes.reset, stream.getWritten());
}

test "Theme.hidden returns ColoredText with dim styling" {
    const color = withEnabled(true);
    const theme = Theme.withColor(color);
    const ct = theme.hidden("(hidden)");

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try ct.format(stream.writer());

    try std.testing.expectEqualStrings("\x1b[2;37m(hidden)\x1b[0m", stream.getWritten());
}

test "Theme returns plain text when colors disabled" {
    const color = withEnabled(false);
    const theme = Theme.withColor(color);
    const ct = theme.err("error");

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try ct.format(stream.writer());
    try std.testing.expectEqualStrings("error", stream.getWritten());
}

test "Theme.errPrefix returns colored or plain prefix" {
    const enabled_theme = Theme.withColor(withEnabled(true));
    const disabled_theme = Theme.withColor(withEnabled(false));
    // Uses brand error color #ef4444
    try std.testing.expectEqualStrings(codes.error_red ++ "error:" ++ codes.reset ++ " ", enabled_theme.errPrefix());
    try std.testing.expectEqualStrings("error: ", disabled_theme.errPrefix());
}

test "Theme.successSymbol returns colored symbol" {
    const theme = Theme.withColor(withEnabled(true));
    const symbol = theme.successSymbol();
    try std.testing.expect(std.mem.indexOf(u8, symbol, symbols.success) != null);
}

test "codes namespace has all expected values" {
    try std.testing.expect(codes.reset.len > 0);
    try std.testing.expect(codes.bold.len > 0);
    try std.testing.expect(codes.bold_red.len > 0);
    try std.testing.expect(codes.bold_green.len > 0);
    try std.testing.expect(codes.bold_yellow.len > 0);
    try std.testing.expect(codes.bold_cyan.len > 0);
    try std.testing.expect(codes.dim_white.len > 0);
    try std.testing.expect(codes.jake_rose.len > 0);
}

test "symbols namespace has Unicode symbols" {
    try std.testing.expectEqualStrings("→", symbols.arrow);
    try std.testing.expectEqualStrings("✓", symbols.success);
    try std.testing.expectEqualStrings("✗", symbols.failure);
}
