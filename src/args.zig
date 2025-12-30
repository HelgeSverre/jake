// args.zig - Simple argument parsing library for jake
// Defines flags once, auto-generates help, catches unknown flags

const std = @import("std");

pub const ValueMode = enum {
    none, // Boolean flag, no value
    required, // Must have a value
    optional, // Value is optional
};

pub const Flag = struct {
    short: ?u8, // Single character, e.g., 'h'
    long: []const u8, // Long name, e.g., "help"
    desc: []const u8, // Description for help text
    takes_value: ValueMode = .none,
    value_name: ?[]const u8 = null, // e.g., "FILE", "N"
};

// Jake's flag definitions - single source of truth
pub const flags = [_]Flag{
    .{ .short = 'h', .long = "help", .desc = "Show this help message" },
    .{ .short = 'V', .long = "version", .desc = "Show version" },
    .{ .short = 'l', .long = "list", .desc = "List available recipes" },
    .{ .short = 'n', .long = "dry-run", .desc = "Print commands without executing" },
    .{ .short = 'v', .long = "verbose", .desc = "Show verbose output" },
    .{ .short = 'y', .long = "yes", .desc = "Auto-confirm all @confirm prompts" },
    .{ .short = 'f', .long = "jakefile", .desc = "Use specified Jakefile", .takes_value = .required, .value_name = "FILE" },
    .{ .short = 'w', .long = "watch", .desc = "Watch files and re-run on changes", .takes_value = .optional, .value_name = "PATTERN" },
    .{ .short = 'j', .long = "jobs", .desc = "Run N recipes in parallel (default: CPU count)", .takes_value = .optional, .value_name = "N" },
    .{ .short = null, .long = "short", .desc = "Output one recipe name per line (for scripting)" },
    .{ .short = 's', .long = "show", .desc = "Show detailed recipe information", .takes_value = .required, .value_name = "RECIPE" },
};

pub const Args = struct {
    help: bool = false,
    version: bool = false,
    list: bool = false,
    dry_run: bool = false,
    verbose: bool = false,
    yes: bool = false,
    short: bool = false,
    show: ?[]const u8 = null,
    jakefile: []const u8 = "Jakefile",
    watch: ?[]const u8 = null, // Pattern if provided
    watch_enabled: bool = false, // True if -w was passed
    jobs: ?usize = null, // null = sequential
    recipe: ?[]const u8 = null,
    positional: []const []const u8 = &.{},

    /// Free allocated memory (positional args slice)
    pub fn deinit(self: *Args, allocator: std.mem.Allocator) void {
        if (self.positional.len > 0) {
            allocator.free(self.positional);
        }
        self.positional = &.{};
    }
};

pub const ParseError = error{
    UnknownFlag,
    MissingValue,
    InvalidValue,
};

pub const ParseResult = struct {
    args: Args,
    err_arg: ?[]const u8 = null, // The argument that caused an error
};

/// Parse command-line arguments into Args struct
/// raw_args should include the program name as first element
pub fn parse(allocator: std.mem.Allocator, raw_args: []const []const u8) ParseError!Args {
    var result = Args{};
    var positional_list: std.ArrayListUnmanaged([]const u8) = .empty;

    // Skip program name (index 0)
    var i: usize = 1;
    while (i < raw_args.len) : (i += 1) {
        const arg = raw_args[i];

        // Once we have a recipe, everything else is positional
        if (result.recipe != null) {
            positional_list.append(allocator, arg) catch {};
            continue;
        }

        // Check if it's a flag
        if (arg.len > 0 and arg[0] == '-') {
            // Long flag
            if (arg.len > 1 and arg[1] == '-') {
                const long_name = arg[2..];

                // Handle --flag=value format
                var flag_name = long_name;
                var inline_value: ?[]const u8 = null;
                if (std.mem.indexOf(u8, long_name, "=")) |eq_pos| {
                    flag_name = long_name[0..eq_pos];
                    inline_value = long_name[eq_pos + 1 ..];
                }

                if (matchLongFlag(flag_name)) |flag_idx| {
                    try setFlag(&result, flag_idx, inline_value, raw_args, &i);
                } else {
                    return error.UnknownFlag;
                }
            } else {
                // Short flag(s)
                const short_chars = arg[1..];

                // Special case: -jN format (e.g., -j4)
                if (short_chars.len > 1 and short_chars[0] == 'j') {
                    const num_str = short_chars[1..];
                    const jobs_val = std.fmt.parseInt(usize, num_str, 10) catch {
                        return error.InvalidValue;
                    };
                    result.jobs = jobs_val;
                    continue;
                }

                // Handle single short flag
                if (short_chars.len == 1) {
                    if (matchShortFlag(short_chars[0])) |flag_idx| {
                        try setFlag(&result, flag_idx, null, raw_args, &i);
                    } else {
                        return error.UnknownFlag;
                    }
                } else {
                    // Multiple short flags like -vn (not supported yet, treat as unknown)
                    return error.UnknownFlag;
                }
            }
        } else {
            // Positional argument - first one is recipe
            result.recipe = arg;
        }
    }

    result.positional = positional_list.toOwnedSlice(allocator) catch &.{};
    return result;
}

fn matchLongFlag(name: []const u8) ?usize {
    for (flags, 0..) |flag, idx| {
        if (std.mem.eql(u8, flag.long, name)) {
            return idx;
        }
    }
    return null;
}

fn matchShortFlag(char: u8) ?usize {
    for (flags, 0..) |flag, idx| {
        if (flag.short) |s| {
            if (s == char) return idx;
        }
    }
    return null;
}

fn setFlag(result: *Args, flag_idx: usize, inline_value: ?[]const u8, raw_args: []const []const u8, i: *usize) ParseError!void {
    const flag = flags[flag_idx];

    switch (flag.takes_value) {
        .none => {
            // Boolean flag
            switch (flag_idx) {
                0 => result.help = true, // help
                1 => result.version = true, // version
                2 => result.list = true, // list
                3 => result.dry_run = true, // dry-run
                4 => result.verbose = true, // verbose
                5 => result.yes = true, // yes
                9 => result.short = true, // short
                else => {},
            }
        },
        .required => {
            // Must have a value
            const value = inline_value orelse blk: {
                if (i.* + 1 >= raw_args.len) {
                    return error.MissingValue;
                }
                i.* += 1;
                break :blk raw_args[i.*];
            };

            switch (flag_idx) {
                6 => result.jakefile = value, // jakefile
                10 => result.show = value, // show
                else => {},
            }
        },
        .optional => {
            // May have a value
            switch (flag_idx) {
                7 => { // watch
                    result.watch_enabled = true;
                    if (inline_value) |v| {
                        result.watch = v;
                    } else if (i.* + 1 < raw_args.len) {
                        const next = raw_args[i.* + 1];
                        // Only consume if it doesn't look like a flag or recipe
                        if (next.len > 0 and next[0] != '-' and !isLikelyRecipeName(next)) {
                            // This is tricky - we need to peek ahead to see if it's a pattern
                            // For now, assume anything with glob chars is a pattern
                            if (std.mem.indexOf(u8, next, "*") != null or
                                std.mem.indexOf(u8, next, "?") != null)
                            {
                                i.* += 1;
                                result.watch = next;
                            }
                        }
                    }
                },
                8 => { // jobs
                    if (inline_value) |v| {
                        result.jobs = std.fmt.parseInt(usize, v, 10) catch {
                            return error.InvalidValue;
                        };
                    } else if (i.* + 1 < raw_args.len) {
                        const next = raw_args[i.* + 1];
                        // Try to parse as number
                        if (std.fmt.parseInt(usize, next, 10)) |n| {
                            i.* += 1;
                            result.jobs = n;
                        } else |_| {
                            // Not a number, use CPU count default
                            result.jobs = std.Thread.getCpuCount() catch 4;
                        }
                    } else {
                        // No next arg, use CPU count
                        result.jobs = std.Thread.getCpuCount() catch 4;
                    }
                },
                else => {},
            }
        },
    }
}

fn isLikelyRecipeName(s: []const u8) bool {
    // Heuristic: recipe names are typically alphanumeric with hyphens/underscores
    // and don't contain glob characters
    if (s.len == 0) return false;
    for (s) |c| {
        if (c == '*' or c == '?' or c == '[' or c == ']') return false;
    }
    return true;
}

/// Print help text to writer, auto-generated from flags array
pub fn printHelp(writer: anytype) void {
    writer.writeAll(
        \\jake - A modern command runner with dependency tracking
        \\
        \\USAGE:
        \\    jake [OPTIONS] [RECIPE] [ARGS...]
        \\
        \\OPTIONS:
        \\
    ) catch {};

    // Auto-generate options from flags array
    for (flags) |flag| {
        // Format: "    -X, --long-name VALUE  Description"
        writer.writeAll("    ") catch {};

        // Short flag
        if (flag.short) |s| {
            writer.print("-{c}, ", .{s}) catch {};
        } else {
            writer.writeAll("    ") catch {};
        }

        // Long flag
        writer.print("--{s}", .{flag.long}) catch {};

        // Value placeholder
        if (flag.value_name) |name| {
            if (flag.takes_value == .optional) {
                writer.print(" [{s}]", .{name}) catch {};
            } else {
                writer.print(" {s}", .{name}) catch {};
            }
        }

        // Padding to align descriptions (target column ~24)
        const used = 4 + 4 + 2 + flag.long.len + if (flag.value_name) |n| n.len + 3 else 0;
        const pad = if (used < 28) 28 - used else 2;
        for (0..pad) |_| {
            writer.writeAll(" ") catch {};
        }

        // Description
        writer.print("{s}\n", .{flag.desc}) catch {};
    }

    writer.writeAll(
        \\
        \\EXAMPLES:
        \\    jake                    Run default recipe (or list if none)
        \\    jake build              Run the 'build' recipe
        \\    jake -n deploy          Dry-run the 'deploy' recipe
        \\    jake -l                 List all recipes
        \\    jake -l --short         List recipes (one per line, for scripting)
        \\    jake -s build           Show detailed info for 'build' recipe
        \\    jake -w build           Watch and re-run 'build' on changes
        \\    jake -w "src/**" build  Watch src/ and re-run 'build'
        \\    jake -j4 build          Run 'build' with 4 parallel jobs
        \\
    ) catch {};
}

/// Print error message for parse failure
pub fn printError(writer: anytype, err: ParseError, arg: []const u8) void {
    switch (err) {
        error.UnknownFlag => {
            writer.print("\x1b[1;31merror:\x1b[0m Unknown option: {s}\n", .{arg}) catch {};
            writer.writeAll("Run 'jake --help' for usage.\n") catch {};
        },
        error.MissingValue => {
            writer.print("\x1b[1;31merror:\x1b[0m Option '{s}' requires a value\n", .{arg}) catch {};
        },
        error.InvalidValue => {
            writer.print("\x1b[1;31merror:\x1b[0m Invalid value for option: {s}\n", .{arg}) catch {};
        },
    }
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;
const expectError = testing.expectError;

test "parse empty args returns defaults" {
    const args = try parse(testing.allocator, &.{"jake"});
    try expect(args.help == false);
    try expect(args.version == false);
    try expect(args.recipe == null);
}

test "parse --help" {
    const args = try parse(testing.allocator, &.{ "jake", "--help" });
    try expect(args.help == true);
}

test "parse -h" {
    const args = try parse(testing.allocator, &.{ "jake", "-h" });
    try expect(args.help == true);
}

test "parse --version" {
    const args = try parse(testing.allocator, &.{ "jake", "--version" });
    try expect(args.version == true);
}

test "parse -V" {
    const args = try parse(testing.allocator, &.{ "jake", "-V" });
    try expect(args.version == true);
}

test "parse recipe name" {
    const args = try parse(testing.allocator, &.{ "jake", "build" });
    try expectEqualStrings("build", args.recipe.?);
}

test "parse recipe with positional args" {
    var args = try parse(testing.allocator, &.{ "jake", "deploy", "prod", "fast" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("deploy", args.recipe.?);
    try expectEqual(@as(usize, 2), args.positional.len);
    try expectEqualStrings("prod", args.positional[0]);
    try expectEqualStrings("fast", args.positional[1]);
}

test "parse --jakefile value" {
    const args = try parse(testing.allocator, &.{ "jake", "--jakefile", "custom.jake" });
    try expectEqualStrings("custom.jake", args.jakefile);
}

test "parse -f value" {
    const args = try parse(testing.allocator, &.{ "jake", "-f", "custom.jake" });
    try expectEqualStrings("custom.jake", args.jakefile);
}

test "parse -j with numeric value" {
    const args = try parse(testing.allocator, &.{ "jake", "-j", "4" });
    try expectEqual(@as(usize, 4), args.jobs.?);
}

test "parse -j4 combined format" {
    const args = try parse(testing.allocator, &.{ "jake", "-j4" });
    try expectEqual(@as(usize, 4), args.jobs.?);
}

test "parse --jobs with value" {
    const args = try parse(testing.allocator, &.{ "jake", "--jobs", "8" });
    try expectEqual(@as(usize, 8), args.jobs.?);
}

test "parse -j without value uses CPU count" {
    const args = try parse(testing.allocator, &.{ "jake", "-j", "build" });
    try expect(args.jobs != null); // Should be CPU count
    try expectEqualStrings("build", args.recipe.?);
}

test "parse -w with pattern" {
    const args = try parse(testing.allocator, &.{ "jake", "-w", "src/**", "build" });
    try expect(args.watch_enabled);
    try expectEqualStrings("src/**", args.watch.?);
    try expectEqualStrings("build", args.recipe.?);
}

test "parse -w without pattern" {
    const args = try parse(testing.allocator, &.{ "jake", "-w", "build" });
    try expect(args.watch_enabled);
    try expect(args.watch == null);
    try expectEqualStrings("build", args.recipe.?);
}

test "parse --watch with pattern" {
    const args = try parse(testing.allocator, &.{ "jake", "--watch", "*.zig", "test" });
    try expect(args.watch_enabled);
    try expectEqualStrings("*.zig", args.watch.?);
    try expectEqualStrings("test", args.recipe.?);
}

test "unknown long flag errors" {
    const result = parse(testing.allocator, &.{ "jake", "--unknown" });
    try expectError(error.UnknownFlag, result);
}

test "unknown short flag errors" {
    const result = parse(testing.allocator, &.{ "jake", "-x" });
    try expectError(error.UnknownFlag, result);
}

test "missing required value for --jakefile" {
    const result = parse(testing.allocator, &.{ "jake", "--jakefile" });
    try expectError(error.MissingValue, result);
}

test "missing required value for -f" {
    const result = parse(testing.allocator, &.{ "jake", "-f" });
    try expectError(error.MissingValue, result);
}

test "multiple boolean flags" {
    const args = try parse(testing.allocator, &.{ "jake", "-v", "-n", "build" });
    try expect(args.verbose);
    try expect(args.dry_run);
    try expectEqualStrings("build", args.recipe.?);
}

test "flags after recipe are positional" {
    var args = try parse(testing.allocator, &.{ "jake", "build", "-v" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("build", args.recipe.?);
    try expectEqual(@as(usize, 1), args.positional.len);
    try expectEqualStrings("-v", args.positional[0]);
}

test "all boolean flags" {
    const args = try parse(testing.allocator, &.{ "jake", "-h", "-V", "-l", "-n", "-v", "-y" });
    try expect(args.help);
    try expect(args.version);
    try expect(args.list);
    try expect(args.dry_run);
    try expect(args.verbose);
    try expect(args.yes);
}

test "-j with non-numeric value uses default and treats as recipe" {
    // When -j is followed by non-number, use CPU default and treat next arg as recipe
    const args = try parse(testing.allocator, &.{ "jake", "-j", "abc" });
    try expect(args.jobs != null); // CPU count
    try expectEqualStrings("abc", args.recipe.?);
}

test "invalid -jN format" {
    // -jabc should fail because it's not -j followed by a number
    const result = parse(testing.allocator, &.{ "jake", "-jabc" });
    try expectError(error.InvalidValue, result);
}

test "printHelp generates correct output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    printHelp(stream.writer());
    const output = stream.getWritten();
    try expect(std.mem.indexOf(u8, output, "-h, --help") != null);
    try expect(std.mem.indexOf(u8, output, "-f, --jakefile") != null);
    try expect(std.mem.indexOf(u8, output, "FILE") != null);
}

test "parse --short flag" {
    const args = try parse(testing.allocator, &.{ "jake", "--short" });
    try expect(args.short == true);
}

test "parse --list --short combination" {
    const args = try parse(testing.allocator, &.{ "jake", "--list", "--short" });
    try expect(args.list == true);
    try expect(args.short == true);
}

test "parse -s (show) with recipe name" {
    const args = try parse(testing.allocator, &.{ "jake", "-s", "build" });
    try expectEqualStrings("build", args.show.?);
}

test "parse --show with recipe name" {
    const args = try parse(testing.allocator, &.{ "jake", "--show", "deploy" });
    try expectEqualStrings("deploy", args.show.?);
}

test "parse --show=value format" {
    const args = try parse(testing.allocator, &.{ "jake", "--show=test" });
    try expectEqualStrings("test", args.show.?);
}

test "missing required value for --show" {
    const result = parse(testing.allocator, &.{ "jake", "--show" });
    try expectError(error.MissingValue, result);
}

test "missing required value for -s" {
    const result = parse(testing.allocator, &.{ "jake", "-s" });
    try expectError(error.MissingValue, result);
}
