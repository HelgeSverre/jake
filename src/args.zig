// args.zig - Simple argument parsing library for jake
// Defines flags once, auto-generates help, catches unknown flags

const std = @import("std");

// ANSI escape codes for colored output
pub const ansi = struct {
    pub const red = "\x1b[1;31m";
    pub const reset = "\x1b[0m";
    pub const err_prefix = red ++ "error:" ++ reset ++ " ";
};

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
    default_display: ?[]const u8 = null, // Shown in help: "(default: X)"
    hidden: bool = false, // Hidden from help output
};

// Jake's flag definitions - single source of truth
// Order doesn't matter - setFlag uses name-based matching
pub const flags = [_]Flag{
    .{ .short = 'h', .long = "help", .desc = "Show this help message" },
    .{ .short = 'V', .long = "version", .desc = "Show version" },
    .{ .short = 'l', .long = "list", .desc = "List available recipes" },
    .{ .short = 'a', .long = "all", .desc = "Show all recipes including hidden (use with -l)" },
    .{ .short = 'n', .long = "dry-run", .desc = "Print commands without executing" },
    .{ .short = 'v', .long = "verbose", .desc = "Show verbose output" },
    .{ .short = 'y', .long = "yes", .desc = "Auto-confirm all @confirm prompts" },
    .{ .short = 'f', .long = "jakefile", .desc = "Use specified Jakefile", .takes_value = .required, .value_name = "FILE", .default_display = "Jakefile" },
    .{ .short = 'w', .long = "watch", .desc = "Watch files and re-run on changes", .takes_value = .optional, .value_name = "PATTERN" },
    .{ .short = 'j', .long = "jobs", .desc = "Run N recipes in parallel", .takes_value = .optional, .value_name = "N", .default_display = "CPU count" },
    .{ .short = null, .long = "short", .desc = "Output one recipe name per line (for scripting)" },
    .{ .short = 's', .long = "show", .desc = "Show detailed recipe information", .takes_value = .required, .value_name = "RECIPE" },
    .{ .short = null, .long = "summary", .desc = "Print recipe names (space-separated, for scripts)" },
    .{ .short = null, .long = "completions", .desc = "Print shell completion script", .takes_value = .optional, .value_name = "SHELL" },
    .{ .short = null, .long = "install", .desc = "Install completions to user directory" },
    .{ .short = null, .long = "uninstall", .desc = "Remove completions and config" },
    .{ .short = null, .long = "fmt", .desc = "Format Jakefile" },
    .{ .short = null, .long = "check", .desc = "Check formatting (exit 1 if changes needed)" },
    .{ .short = null, .long = "dump", .desc = "Output formatted Jakefile to stdout" },
};

pub const Args = struct {
    help: bool = false,
    version: bool = false,
    list: bool = false,
    all: bool = false,
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
    summary: bool = false, // Print recipe names space-separated
    completions: ?[]const u8 = null, // Shell name for completions (bash/zsh/fish)
    completions_enabled: bool = false, // True if --completions was passed
    install_completions: bool = false, // Install completions to user directory
    uninstall_completions: bool = false, // Uninstall completions
    fmt: bool = false, // Format Jakefile
    check: bool = false, // Check formatting without writing
    dump: bool = false, // Output formatted Jakefile to stdout

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

/// Parse command-line arguments into Args struct
/// raw_args should include the program name as first element
pub fn parse(allocator: std.mem.Allocator, raw_args: []const []const u8) ParseError!Args {
    var result = Args{};
    var positional_list: std.ArrayListUnmanaged([]const u8) = .empty;

    // Skip program name (index 0)
    var i: usize = 1;
    while (i < raw_args.len) : (i += 1) {
        const arg = raw_args[i];

        // Double-dash separator: stop flag parsing, treat rest as positional
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < raw_args.len) : (i += 1) {
                if (result.recipe == null) {
                    result.recipe = raw_args[i];
                } else {
                    positional_list.append(allocator, raw_args[i]) catch {};
                }
            }
            break;
        }

        // Once we have a recipe, check if this is a global flag before treating as positional
        if (result.recipe != null) {
            // Allow global flags (boolean or optional without value) after recipe
            if (arg.len > 0 and arg[0] == '-') {
                if (arg.len > 1 and arg[1] == '-') {
                    // Long flag: check if it's a known flag that doesn't require a value
                    const long_name = arg[2..];
                    if (matchLongFlag(long_name)) |flag_idx| {
                        if (flags[flag_idx].takes_value != .required) {
                            try setFlag(&result, flag_idx, null, raw_args, &i);
                            continue;
                        }
                    }
                } else {
                    // Short flag: check if all chars are known flags that don't require values
                    const short_chars = arg[1..];
                    var all_non_required = true;
                    for (short_chars) |c| {
                        if (matchShortFlag(c)) |flag_idx| {
                            if (flags[flag_idx].takes_value == .required) {
                                all_non_required = false;
                                break;
                            }
                        } else {
                            all_non_required = false;
                            break;
                        }
                    }
                    if (all_non_required and short_chars.len > 0) {
                        for (short_chars) |c| {
                            if (matchShortFlag(c)) |flag_idx| {
                                try setFlag(&result, flag_idx, null, raw_args, &i);
                            }
                        }
                        continue;
                    }
                }
            }
            // Not a global flag, treat as positional
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

                // Handle short flag(s) - supports combined like -vn
                for (short_chars) |c| {
                    if (matchShortFlag(c)) |flag_idx| {
                        // Only boolean flags can be combined
                        if (flags[flag_idx].takes_value != .none) {
                            // Value flags can only be last in a combined sequence
                            // For simplicity, reject combining value flags
                            if (short_chars.len > 1) {
                                return error.UnknownFlag;
                            }
                        }
                        try setFlag(&result, flag_idx, null, raw_args, &i);
                    } else {
                        return error.UnknownFlag;
                    }
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
    const name = flag.long;

    switch (flag.takes_value) {
        .none => {
            // Boolean flags - use name comparison instead of fragile indices
            if (std.mem.eql(u8, name, "help")) {
                result.help = true;
            } else if (std.mem.eql(u8, name, "version")) {
                result.version = true;
            } else if (std.mem.eql(u8, name, "list")) {
                result.list = true;
            } else if (std.mem.eql(u8, name, "all")) {
                result.all = true;
            } else if (std.mem.eql(u8, name, "dry-run")) {
                result.dry_run = true;
            } else if (std.mem.eql(u8, name, "verbose")) {
                result.verbose = true;
            } else if (std.mem.eql(u8, name, "yes")) {
                result.yes = true;
            } else if (std.mem.eql(u8, name, "short")) {
                result.short = true;
            } else if (std.mem.eql(u8, name, "summary")) {
                result.summary = true;
            } else if (std.mem.eql(u8, name, "install")) {
                result.install_completions = true;
            } else if (std.mem.eql(u8, name, "uninstall")) {
                result.uninstall_completions = true;
            } else if (std.mem.eql(u8, name, "fmt")) {
                result.fmt = true;
            } else if (std.mem.eql(u8, name, "check")) {
                result.check = true;
            } else if (std.mem.eql(u8, name, "dump")) {
                result.dump = true;
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

            if (std.mem.eql(u8, name, "jakefile")) {
                result.jakefile = value;
            } else if (std.mem.eql(u8, name, "show")) {
                result.show = value;
            }
        },
        .optional => {
            // May have a value
            if (std.mem.eql(u8, name, "watch")) {
                result.watch_enabled = true;
                if (inline_value) |v| {
                    result.watch = v;
                } else if (i.* + 1 < raw_args.len) {
                    const next = raw_args[i.* + 1];
                    // Only consume if it doesn't look like a flag or recipe
                    if (next.len > 0 and next[0] != '-' and !isLikelyRecipeName(next)) {
                        // Assume anything with glob chars is a pattern
                        if (std.mem.indexOf(u8, next, "*") != null or
                            std.mem.indexOf(u8, next, "?") != null)
                        {
                            i.* += 1;
                            result.watch = next;
                        }
                    }
                }
            } else if (std.mem.eql(u8, name, "jobs")) {
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
            } else if (std.mem.eql(u8, name, "completions")) {
                result.completions_enabled = true;
                if (inline_value) |v| {
                    result.completions = v;
                } else if (i.* + 1 < raw_args.len) {
                    const next = raw_args[i.* + 1];
                    // Check if next arg is a valid shell name
                    if (isValidShell(next)) {
                        i.* += 1;
                        result.completions = next;
                    }
                    // Otherwise, completions stays null (auto-detect)
                }
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

fn isValidShell(s: []const u8) bool {
    return std.mem.eql(u8, s, "bash") or
        std.mem.eql(u8, s, "zsh") or
        std.mem.eql(u8, s, "fish");
}

/// Print help text to writer, auto-generated from flags array
pub fn printHelp(writer: anytype) void {
    writer.writeAll(
        \\jake - A modern command runner with dependency tracking
        \\
        \\USAGE:
        \\    jake [OPTIONS] [RECIPE] [ARGS...]
        \\    jake upgrade [--check] [--no-verify]
        \\
        \\COMMANDS:
        \\    upgrade             Update jake to the latest version
        \\
        \\OPTIONS:
        \\
    ) catch {};

    // Auto-generate options from flags array
    for (flags) |flag| {
        // Skip hidden flags
        if (flag.hidden) continue;

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

        // Description with optional default value
        writer.print("{s}", .{flag.desc}) catch {};
        if (flag.default_display) |default| {
            writer.print(" (default: {s})", .{default}) catch {};
        }
        writer.writeAll("\n") catch {};
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
        \\    jake --completions bash Print bash completion script
        \\    jake --completions --install  Install completions for current shell
        \\
    ) catch {};
}

/// Print error message for parse failure
pub fn printError(writer: anytype, err: ParseError, arg: []const u8) void {
    switch (err) {
        error.UnknownFlag => {
            writer.print(ansi.err_prefix ++ "Unknown option: {s}\n", .{arg}) catch {};
            writer.writeAll("Run 'jake --help' for usage.\n") catch {};
        },
        error.MissingValue => {
            writer.print(ansi.err_prefix ++ "Option '{s}' requires a value\n", .{arg}) catch {};
        },
        error.InvalidValue => {
            writer.print(ansi.err_prefix ++ "Invalid value for option: {s}\n", .{arg}) catch {};
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

test "boolean flags after recipe still work" {
    var args = try parse(testing.allocator, &.{ "jake", "build", "-v", "--yes" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("build", args.recipe.?);
    try expect(args.verbose); // -v is processed as flag
    try expect(args.yes); // --yes is processed as flag
    try expectEqual(@as(usize, 0), args.positional.len);
}

test "unknown flags after recipe are positional" {
    var args = try parse(testing.allocator, &.{ "jake", "build", "--unknown-flag" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("build", args.recipe.?);
    try expectEqual(@as(usize, 1), args.positional.len);
    try expectEqualStrings("--unknown-flag", args.positional[0]);
}

test "value flags after recipe are positional" {
    // -f takes a value, so it should be treated as positional after recipe
    var args = try parse(testing.allocator, &.{ "jake", "build", "-f", "file.jake" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("build", args.recipe.?);
    try expectEqual(@as(usize, 2), args.positional.len);
    try expectEqualStrings("-f", args.positional[0]);
    try expectEqualStrings("file.jake", args.positional[1]);
}

test "all boolean flags" {
    const args = try parse(testing.allocator, &.{ "jake", "-h", "-V", "-l", "-a", "-n", "-v", "-y" });
    try expect(args.help);
    try expect(args.version);
    try expect(args.list);
    try expect(args.all);
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

test "combined short flags -vn" {
    const args = try parse(testing.allocator, &.{ "jake", "-vn", "build" });
    try expect(args.verbose);
    try expect(args.dry_run);
    try expectEqualStrings("build", args.recipe.?);
}

test "combined short flags -lvy" {
    const args = try parse(testing.allocator, &.{ "jake", "-lvy" });
    try expect(args.list);
    try expect(args.verbose);
    try expect(args.yes);
}

test "combined flags with value flag errors" {
    // -vf should fail because -f takes a value and can't be combined
    const result = parse(testing.allocator, &.{ "jake", "-vf" });
    try expectError(error.UnknownFlag, result);
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

test "parse --all flag" {
    const args = try parse(testing.allocator, &.{ "jake", "--all" });
    try expect(args.all == true);
}

test "parse -a flag" {
    const args = try parse(testing.allocator, &.{ "jake", "-a" });
    try expect(args.all == true);
}

test "parse --list --all combination" {
    const args = try parse(testing.allocator, &.{ "jake", "--list", "--all" });
    try expect(args.list == true);
    try expect(args.all == true);
}

test "parse -la combined flags" {
    const args = try parse(testing.allocator, &.{ "jake", "-la" });
    try expect(args.list == true);
    try expect(args.all == true);
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

test "parse --summary flag" {
    const args = try parse(testing.allocator, &.{ "jake", "--summary" });
    try expect(args.summary == true);
}

test "parse --completions bash" {
    const args = try parse(testing.allocator, &.{ "jake", "--completions", "bash" });
    try expect(args.completions_enabled);
    try expectEqualStrings("bash", args.completions.?);
}

test "parse --completions zsh" {
    const args = try parse(testing.allocator, &.{ "jake", "--completions", "zsh" });
    try expect(args.completions_enabled);
    try expectEqualStrings("zsh", args.completions.?);
}

test "parse --completions fish" {
    const args = try parse(testing.allocator, &.{ "jake", "--completions", "fish" });
    try expect(args.completions_enabled);
    try expectEqualStrings("fish", args.completions.?);
}

test "parse --completions=bash inline format" {
    const args = try parse(testing.allocator, &.{ "jake", "--completions=bash" });
    try expect(args.completions_enabled);
    try expectEqualStrings("bash", args.completions.?);
}

test "parse --completions without shell auto-detects" {
    const args = try parse(testing.allocator, &.{ "jake", "--completions" });
    try expect(args.completions_enabled);
    try expect(args.completions == null); // Will auto-detect from $SHELL
}

test "parse --completions --install" {
    const args = try parse(testing.allocator, &.{ "jake", "--completions", "--install" });
    try expect(args.completions_enabled);
    try expect(args.install_completions);
    try expect(args.completions == null); // Auto-detect
}

test "parse --completions bash --install" {
    const args = try parse(testing.allocator, &.{ "jake", "--completions", "bash", "--install" });
    try expect(args.completions_enabled);
    try expect(args.install_completions);
    try expectEqualStrings("bash", args.completions.?);
}

test "parse --install alone" {
    const args = try parse(testing.allocator, &.{ "jake", "--install" });
    try expect(args.install_completions);
    try expect(!args.completions_enabled);
}

// ============================================================================
// Flag Ordering Tests (flags after recipe)
// ============================================================================

test "all global boolean flags work after recipe" {
    var args = try parse(testing.allocator, &.{
        "jake", "build",
        "-h", "-V", "-l", "-a", "-n", "-v", "-y", "--short", "--summary", "--install", "--uninstall",
    });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("build", args.recipe.?);
    try expect(args.help);
    try expect(args.version);
    try expect(args.list);
    try expect(args.all);
    try expect(args.dry_run);
    try expect(args.verbose);
    try expect(args.yes);
    try expect(args.short);
    try expect(args.summary);
    try expect(args.install_completions);
    try expect(args.uninstall_completions);
    try expectEqual(@as(usize, 0), args.positional.len);
}

test "mixed boolean flags before and after recipe" {
    var args = try parse(testing.allocator, &.{ "jake", "-v", "build", "-n", "--yes" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("build", args.recipe.?);
    try expect(args.verbose);
    try expect(args.dry_run);
    try expect(args.yes);
    try expectEqual(@as(usize, 0), args.positional.len);
}

test "combined short flags after recipe" {
    var args = try parse(testing.allocator, &.{ "jake", "deploy", "-vny" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("deploy", args.recipe.?);
    try expect(args.verbose);
    try expect(args.dry_run);
    try expect(args.yes);
    try expectEqual(@as(usize, 0), args.positional.len);
}

test "real positional args with flags after recipe" {
    var args = try parse(testing.allocator, &.{ "jake", "deploy", "prod", "fast", "--yes" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("deploy", args.recipe.?);
    try expect(args.yes);
    try expectEqual(@as(usize, 2), args.positional.len);
    try expectEqualStrings("prod", args.positional[0]);
    try expectEqualStrings("fast", args.positional[1]);
}

test "inline value format --jakefile=custom.jake" {
    const args = try parse(testing.allocator, &.{ "jake", "--jakefile=custom.jake", "build" });
    try expectEqualStrings("custom.jake", args.jakefile);
    try expectEqualStrings("build", args.recipe.?);
}

test "inline value format --show=recipe" {
    const args = try parse(testing.allocator, &.{ "jake", "--show=build" });
    try expectEqualStrings("build", args.show.?);
}

test "inline value format --jobs=8" {
    const args = try parse(testing.allocator, &.{ "jake", "--jobs=8", "build" });
    try expectEqual(@as(usize, 8), args.jobs.?);
    try expectEqualStrings("build", args.recipe.?);
}

test "inline value format --watch=pattern" {
    const args = try parse(testing.allocator, &.{ "jake", "--watch=src/*.zig", "build" });
    try expect(args.watch_enabled);
    try expectEqualStrings("src/*.zig", args.watch.?);
    try expectEqualStrings("build", args.recipe.?);
}

test "--uninstall flag parses correctly" {
    const args = try parse(testing.allocator, &.{ "jake", "--uninstall" });
    try expect(args.uninstall_completions);
}

test "flags after recipe with equals sign in positional" {
    var args = try parse(testing.allocator, &.{ "jake", "test", "name=value", "--verbose" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("test", args.recipe.?);
    try expect(args.verbose);
    try expectEqual(@as(usize, 1), args.positional.len);
    try expectEqualStrings("name=value", args.positional[0]);
}

test "long flag with value after recipe is positional" {
    // --jakefile takes a value, so it's treated as positional after recipe
    var args = try parse(testing.allocator, &.{ "jake", "build", "--jakefile", "other.jake" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("build", args.recipe.?);
    try expectEqual(@as(usize, 2), args.positional.len);
    try expectEqualStrings("--jakefile", args.positional[0]);
    try expectEqualStrings("other.jake", args.positional[1]);
}

test "inline value flag after recipe is positional" {
    // Even --jakefile=value is positional after recipe since it takes a value
    var args = try parse(testing.allocator, &.{ "jake", "build", "--jakefile=other.jake" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("build", args.recipe.?);
    try expectEqual(@as(usize, 1), args.positional.len);
    try expectEqualStrings("--jakefile=other.jake", args.positional[0]);
}

test "empty args after program name" {
    const args = try parse(testing.allocator, &.{"jake"});
    try expect(args.recipe == null);
    try expect(!args.help);
    try expect(!args.list);
}

test "recipe that looks like a flag" {
    // A recipe named literally "-v" would be strange but should work
    // Actually no - first check is if it starts with -, so this would be parsed as flag
    const args = try parse(testing.allocator, &.{ "jake", "some-recipe" });
    try expectEqualStrings("some-recipe", args.recipe.?);
}

test "double-dash separator stops flag parsing" {
    // -- stops flag parsing, everything after becomes positional
    var args = try parse(testing.allocator, &.{ "jake", "build", "--", "--verbose", "-n" });
    defer args.deinit(testing.allocator);
    try expectEqualStrings("build", args.recipe.?);
    // --verbose and -n become positional, not parsed as flags
    try expectEqual(@as(usize, 2), args.positional.len);
    try expectEqualStrings("--verbose", args.positional[0]);
    try expectEqualStrings("-n", args.positional[1]);
    try expect(!args.verbose); // Not parsed as flag
    try expect(!args.dry_run); // Not parsed as flag
}

test "double-dash before recipe sets recipe from rest" {
    var args = try parse(testing.allocator, &.{ "jake", "--", "--help" });
    defer args.deinit(testing.allocator);
    // --help becomes recipe name, not parsed as help flag
    try expectEqualStrings("--help", args.recipe.?);
    try expect(!args.help);
}

test "double-dash with recipe and positional" {
    var args = try parse(testing.allocator, &.{ "jake", "-v", "--", "build", "arg1", "arg2" });
    defer args.deinit(testing.allocator);
    try expect(args.verbose); // -v before -- is parsed
    try expectEqualStrings("build", args.recipe.?);
    try expectEqual(@as(usize, 2), args.positional.len);
    try expectEqualStrings("arg1", args.positional[0]);
    try expectEqualStrings("arg2", args.positional[1]);
}

// ============================================================================
// Hidden Flag and Default Display Tests
// ============================================================================

test "printHelp includes default values" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    printHelp(stream.writer());
    const output = stream.getWritten();
    // Check that default values are shown
    try expect(std.mem.indexOf(u8, output, "(default: Jakefile)") != null);
    try expect(std.mem.indexOf(u8, output, "(default: CPU count)") != null);
}

test "printHelp excludes hidden flags" {
    // Verify that hidden flags are not in help output
    // Currently no flags are hidden, but the mechanism is in place
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    printHelp(stream.writer());
    const output = stream.getWritten();
    // All current flags should be visible (none are hidden)
    try expect(std.mem.indexOf(u8, output, "--help") != null);
    try expect(std.mem.indexOf(u8, output, "--version") != null);
    try expect(std.mem.indexOf(u8, output, "--jakefile") != null);
}

test "Flag struct has hidden and default_display fields" {
    // Verify the Flag struct has the new fields with correct defaults
    const test_flag = Flag{
        .short = 't',
        .long = "test",
        .desc = "Test flag",
    };
    try expect(!test_flag.hidden);
    try expect(test_flag.default_display == null);

    const hidden_flag = Flag{
        .short = null,
        .long = "secret",
        .desc = "Secret flag",
        .hidden = true,
    };
    try expect(hidden_flag.hidden);

    const flag_with_default = Flag{
        .short = 'd',
        .long = "default",
        .desc = "Flag with default",
        .default_display = "some-value",
    };
    try expectEqualStrings("some-value", flag_with_default.default_display.?);
}
