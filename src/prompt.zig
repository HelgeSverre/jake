const std = @import("std");

/// Result from a confirmation prompt
pub const ConfirmResult = enum {
    yes,
    no,
};

/// A confirmation prompt handler
pub const Prompt = struct {
    auto_yes: bool = false,
    dry_run: bool = false,

    pub fn init() Prompt {
        return .{};
    }

    /// Ask for confirmation with a message
    /// Returns .yes if user confirms, .no if user denies
    pub fn confirm(self: *Prompt, message: []const u8) !ConfirmResult {
        const stdout = std.fs.File.stdout();
        const stdin = std.fs.File.stdin();

        // In dry-run mode, show message but don't prompt
        if (self.dry_run) {
            var buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "  [dry-run] Would prompt: {s} [y/N] \n", .{message}) catch return .yes;
            stdout.writeAll(msg) catch {};
            return .yes; // Continue execution in dry-run
        }

        // Auto-yes mode: skip prompt and return yes
        if (self.auto_yes) {
            var buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{s} [y/N] (auto-confirmed with --yes)\n", .{message}) catch return .yes;
            stdout.writeAll(msg) catch {};
            return .yes;
        }

        // Actually prompt the user
        {
            var buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{s} [y/N] ", .{message}) catch return .no;
            stdout.writeAll(msg) catch {};
        }

        // Read from stdin (simple approach - read until newline)
        var line_buf: [256]u8 = undefined;
        var total_read: usize = 0;
        while (total_read < line_buf.len) {
            const bytes_read = stdin.read(line_buf[total_read..]) catch return .no;
            if (bytes_read == 0) {
                // End of stream
                break;
            }
            total_read += bytes_read;
            // Check if we hit a newline
            if (std.mem.indexOfScalar(u8, line_buf[0..total_read], '\n')) |idx| {
                return parseResponse(line_buf[0..idx]);
            }
        }
        return parseResponse(line_buf[0..total_read]);
    }

    /// Parse user response string into ConfirmResult
    pub fn parseResponse(response: []const u8) ConfirmResult {
        const trimmed = std.mem.trim(u8, response, " \t\r\n");

        // Empty response = no
        if (trimmed.len == 0) {
            return .no;
        }

        // Check for yes responses (case-insensitive)
        const lower = blk: {
            var buf: [32]u8 = undefined;
            const len = @min(trimmed.len, buf.len);
            for (trimmed[0..len], 0..) |c, i| {
                buf[i] = std.ascii.toLower(c);
            }
            break :blk buf[0..len];
        };

        if (std.mem.eql(u8, lower, "y") or
            std.mem.eql(u8, lower, "yes"))
        {
            return .yes;
        }

        // Everything else is no
        return .no;
    }
};

// Tests

test "@confirm returns true for 'y' input" {
    const result = Prompt.parseResponse("y");
    try std.testing.expectEqual(ConfirmResult.yes, result);
}

test "@confirm returns true for 'Y' input" {
    const result = Prompt.parseResponse("Y");
    try std.testing.expectEqual(ConfirmResult.yes, result);
}

test "@confirm returns true for 'yes' input" {
    const result = Prompt.parseResponse("yes");
    try std.testing.expectEqual(ConfirmResult.yes, result);
}

test "@confirm returns true for 'YES' input" {
    const result = Prompt.parseResponse("YES");
    try std.testing.expectEqual(ConfirmResult.yes, result);
}

test "@confirm returns false for 'n' input" {
    const result = Prompt.parseResponse("n");
    try std.testing.expectEqual(ConfirmResult.no, result);
}

test "@confirm returns false for 'no' input" {
    const result = Prompt.parseResponse("no");
    try std.testing.expectEqual(ConfirmResult.no, result);
}

test "@confirm returns false for empty input" {
    const result = Prompt.parseResponse("");
    try std.testing.expectEqual(ConfirmResult.no, result);
}

test "@confirm returns false for whitespace-only input" {
    const result = Prompt.parseResponse("   \t  ");
    try std.testing.expectEqual(ConfirmResult.no, result);
}
