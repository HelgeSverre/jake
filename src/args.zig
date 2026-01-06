// args.zig - Simple argument parsing library for jake
// Defines flags once, auto-generates help, catches unknown flags

const std = @import("std");
const suggest = @import("suggest.zig");
const compat = @import("compat.zig");

// ANSI escape codes for colored output (matches brand.astro)
pub const ansi = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const jake_rose = "\x1b[38;2;244;63;94m"; // #f43f5e brand color
    pub const muted = "\x1b[38;2;113;113;122m"; // #71717a - tagline, placeholders
    pub const secondary = "\x1b[90m"; // gray - section headers
    pub const error_red = "\x1b[38;2;239;68;68m"; // #ef4444 - brand error color
    pub const yellow = "\x1b[38;2;234;179;8m"; // #eab308 - warning color
    pub const err_prefix = error_red ++ "error:" ++ reset ++ " ";
    pub const warn_prefix = yellow ++ "warning:" ++ reset ++ " ";
    pub const logo = "{j}";
};

pub const ValueMode = enum {
    none, // Boolean flag, no value
    required, // Must have a value
    optional, // Value is optional
};

/// Built-in value validators for common use cases
pub const Validator = enum {
    none, // No validation
    positive_integer, // Must be a positive integer (> 0)
    non_negative_integer, // Must be >= 0
    file_path, // Must look like a file path (non-empty, no control chars)
    shell_name, // Must be bash, zsh, or fish
};

pub const Flag = struct {
    short: ?u8, // Single character, e.g., 'h'
    long: []const u8, // Long name, e.g., "help"
    desc: []const u8, // Description for help text
    takes_value: ValueMode = .none,
    value_name: ?[]const u8 = null, // e.g., "FILE", "N"
    default_display: ?[]const u8 = null, // Shown in help: "(default: X)"
    hidden: bool = false, // Hidden from help output
    category: ?[]const u8 = null, // Category for grouping in help (e.g., "General", "Execution")
    deprecated: ?[]const u8 = null, // Deprecation message (e.g., "Use --new-flag instead")
    countable: bool = false, // If true, flag can be repeated (-vvv counts occurrences)
    negatable: bool = false, // If true, --no-X form is accepted
    env: ?[]const u8 = null, // Environment variable fallback (e.g., "JAKEFILE")
    aliases: ?[]const []const u8 = null, // Alternative long flag names (e.g., &.{"dryrun", "simulate"})
    choices: ?[]const []const u8 = null, // Valid values (e.g., &.{"json", "yaml", "toml"})
    mutually_exclusive: ?[]const u8 = null, // Flag that cannot be used with this one (e.g., "show")
    requires: ?[]const u8 = null, // Flag that must also be specified (e.g., "password")
    validator: Validator = .none, // Value validator type
};

// Category names for help output grouping
pub const categories = [_][]const u8{ "General", "Output", "Execution", "File", "Shell" };

// Jake's flag definitions - single source of truth
// Order doesn't matter - setFlag uses name-based matching
pub const flags = [_]Flag{
    // General
    .{ .short = 'h', .long = "help", .desc = "Show this help message", .category = "General" },
    .{ .short = 'V', .long = "version", .desc = "Show version", .category = "General" },
    // Output
    .{ .short = 'l', .long = "list", .desc = "List available recipes", .category = "Output", .mutually_exclusive = "show" },
    .{ .short = 'a', .long = "all", .desc = "Show all recipes including hidden (use with -l)", .category = "Output" },
    .{ .short = null, .long = "short", .desc = "Output one recipe name per line (for scripting)", .category = "Output" },
    .{ .short = 's', .long = "show", .desc = "Show detailed recipe information", .takes_value = .required, .value_name = "RECIPE", .category = "Output", .mutually_exclusive = "list" },
    .{ .short = null, .long = "summary", .desc = "Print recipe names (space-separated, for scripts)", .category = "Output" },
    // Execution
    .{ .short = 'n', .long = "dry-run", .desc = "Print commands without executing", .category = "Execution", .env = "JAKE_DRY_RUN", .aliases = &.{"dryrun"} },
    .{ .short = 'v', .long = "verbose", .desc = "Show verbose output (use -vv or -vvv for more)", .category = "Execution", .countable = true, .negatable = true, .env = "JAKE_VERBOSE" },
    .{ .short = 'y', .long = "yes", .desc = "Auto-confirm all @confirm prompts", .category = "Execution", .negatable = true, .env = "JAKE_YES" },
    .{ .short = 'w', .long = "watch", .desc = "Watch files and re-run on changes", .takes_value = .optional, .value_name = "PATTERN", .category = "Execution" },
    .{ .short = 'j', .long = "jobs", .desc = "Run N recipes in parallel", .takes_value = .optional, .value_name = "N", .default_display = "CPU count", .category = "Execution", .env = "JAKE_JOBS", .validator = .positive_integer },
    // File
    .{ .short = 'f', .long = "jakefile", .desc = "Use specified Jakefile", .takes_value = .required, .value_name = "FILE", .default_display = "Jakefile", .category = "File", .env = "JAKEFILE", .validator = .file_path },
    .{ .short = null, .long = "fmt", .desc = "Format Jakefile", .category = "File" },
    .{ .short = null, .long = "check", .desc = "Check formatting (exit 1 if changes needed)", .category = "File", .requires = "fmt" },
    .{ .short = null, .long = "dump", .desc = "Output formatted Jakefile to stdout", .category = "File", .requires = "fmt" },
    // Shell
    .{ .short = null, .long = "completions", .desc = "Print shell completion script", .takes_value = .optional, .value_name = "SHELL", .category = "Shell", .choices = &.{ "bash", "zsh", "fish" } },
    .{ .short = null, .long = "install", .desc = "Install completions to user directory", .category = "Shell" },
    .{ .short = null, .long = "uninstall", .desc = "Remove completions and config", .category = "Shell" },
};

// ============================================================================
// Compile-time Validation
// ============================================================================

/// Compile-time validation: ensure no duplicate short flags
fn validateNoDuplicateShortFlags() void {
    comptime {
        for (flags, 0..) |flag1, i| {
            if (flag1.short) |s1| {
                for (flags[i + 1 ..]) |flag2| {
                    if (flag2.short) |s2| {
                        if (s1 == s2) {
                            @compileError("Duplicate short flag: -" ++ [_]u8{s1});
                        }
                    }
                }
            }
        }
    }
}

/// Compile-time validation: ensure no duplicate long flags
fn validateNoDuplicateLongFlags() void {
    comptime {
        for (flags, 0..) |flag1, i| {
            for (flags[i + 1 ..]) |flag2| {
                if (std.mem.eql(u8, flag1.long, flag2.long)) {
                    @compileError("Duplicate long flag: --" ++ flag1.long);
                }
            }
        }
    }
}

/// Compile-time validation: ensure aliases don't conflict with primary names
fn validateAliasesUnique() void {
    comptime {
        for (flags) |flag| {
            if (flag.aliases) |aliases| {
                for (aliases) |alias| {
                    // Check alias doesn't match any primary long flag
                    for (flags) |other| {
                        if (std.mem.eql(u8, alias, other.long)) {
                            @compileError("Alias '" ++ alias ++ "' conflicts with primary flag --" ++ other.long);
                        }
                    }
                }
            }
        }
    }
}

/// Compile-time validation: ensure categories are valid
fn validateCategories() void {
    comptime {
        for (flags) |flag| {
            if (flag.category) |cat| {
                var found = false;
                for (categories) |valid_cat| {
                    if (std.mem.eql(u8, cat, valid_cat)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    @compileError("Unknown category '" ++ cat ++ "' for flag --" ++ flag.long);
                }
            }
        }
    }
}

/// Run all compile-time validations
pub fn validateFlags() void {
    validateNoDuplicateShortFlags();
    validateNoDuplicateLongFlags();
    validateAliasesUnique();
    validateCategories();
}

// Trigger compile-time validation when this module is imported
comptime {
    validateFlags();
}

pub const Args = struct {
    help: bool = false,
    version: bool = false,
    list: bool = false,
    all: bool = false,
    dry_run: bool = false,
    verbose: bool = false,
    verbose_level: u8 = 0, // Counts -v occurrences: -vvv = 3
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
    InvalidChoice,
    MutuallyExclusive,
    RequiredTogether,
};

/// Context for enhanced error messages
pub const ErrorContext = struct {
    flag_name: []const u8 = "",
    provided_value: []const u8 = "",
    expected_type: []const u8 = "",
    choices: ?[]const []const u8 = null,
    conflicting_flag: []const u8 = "",
    required_flag: []const u8 = "",
};

/// Quick action types for early exit decisions
pub const QuickAction = enum {
    none, // Continue with full parsing
    help, // Show help and exit
    version, // Show version and exit
};

/// Quickly scan args for --help or --version without full parsing.
/// Returns the action to take, enabling early exit for these common cases.
/// This is O(n) where n is arg count, but avoids full parse overhead.
pub fn quickScan(raw_args: []const []const u8) QuickAction {
    // Skip program name (first arg)
    const args = if (raw_args.len > 0) raw_args[1..] else raw_args;

    for (args) |arg| {
        // Stop at -- separator
        if (std.mem.eql(u8, arg, "--")) break;

        // Check for help flags
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return .help;
        }

        // Check for version flags
        if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            return .version;
        }
    }

    return .none;
}

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

                // Handle --no-X negatable flags first
                if (std.mem.startsWith(u8, long_name, "no-")) {
                    const negated_name = long_name[3..]; // Remove "no-"
                    if (matchLongFlag(negated_name)) |flag_idx| {
                        const flag = flags[flag_idx];
                        if (flag.negatable) {
                            setFlagNegated(&result, flag_idx);
                            printDeprecationWarning(flag);
                            continue;
                        }
                    }
                    // Not a valid negatable flag, fall through to error
                    return error.UnknownFlag;
                }

                // Handle --flag=value format
                var flag_name = long_name;
                var inline_value: ?[]const u8 = null;
                if (std.mem.indexOf(u8, long_name, "=")) |eq_pos| {
                    flag_name = long_name[0..eq_pos];
                    inline_value = long_name[eq_pos + 1 ..];
                }

                if (matchLongFlag(flag_name)) |flag_idx| {
                    try setFlag(&result, flag_idx, inline_value, raw_args, &i);
                    printDeprecationWarning(flags[flag_idx]);
                } else {
                    return error.UnknownFlag;
                }
            } else {
                // Short flag(s)
                const short_chars = arg[1..];

                // Check if first char is a flag that takes a value with attached value (-fVAL, -j4)
                if (short_chars.len > 1) {
                    if (matchShortFlag(short_chars[0])) |flag_idx| {
                        const flag = flags[flag_idx];
                        if (flag.takes_value != .none) {
                            // This is -xVALUE format (e.g., -j4, -fcustom.jake)
                            const attached_value = short_chars[1..];
                            try setFlag(&result, flag_idx, attached_value, raw_args, &i);
                            printDeprecationWarning(flag);
                            continue;
                        }
                    }
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
                        printDeprecationWarning(flags[flag_idx]);
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

    // Apply environment variable fallbacks for flags not set via CLI
    applyEnvFallbacks(&result);

    // Validate mutual exclusivity and required-together constraints
    if (validateConstraints(&result)) |violation| {
        // Print the constraint error with full context
        const stderr = compat.getStdErr();
        var buf: [256]u8 = undefined;
        const msg = switch (violation.err) {
            error.MutuallyExclusive => std.fmt.bufPrint(&buf, ansi.err_prefix ++ "Options {s} and {s} cannot be used together\n", .{ violation.flag1, violation.flag2 }) catch "error\n",
            error.RequiredTogether => std.fmt.bufPrint(&buf, ansi.err_prefix ++ "Option {s} requires {s} to also be specified\n", .{ violation.flag1, violation.flag2 }) catch "error\n",
            else => "error\n",
        };
        stderr.writeAll(msg) catch {};
        return violation.err;
    }

    return result;
}

/// Constraint violation info for rich error messages
pub const ConstraintViolation = struct {
    err: ParseError,
    flag1: []const u8,
    flag2: []const u8,
};

/// Validate mutual exclusivity and required-together constraints
/// Returns constraint violation info if validation fails
fn validateConstraints(result: *const Args) ?ConstraintViolation {
    // Check --list and --show mutual exclusivity
    if (result.list and result.show != null) {
        return .{ .err = error.MutuallyExclusive, .flag1 = "--list", .flag2 = "--show" };
    }

    // Check required-together constraints
    // --check requires --fmt
    if (result.check and !result.fmt) {
        return .{ .err = error.RequiredTogether, .flag1 = "--check", .flag2 = "--fmt" };
    }
    // --dump requires --fmt
    if (result.dump and !result.fmt) {
        return .{ .err = error.RequiredTogether, .flag1 = "--dump", .flag2 = "--fmt" };
    }

    return null;
}

fn matchLongFlag(name: []const u8) ?usize {
    for (flags, 0..) |flag, idx| {
        // Check primary long name
        if (std.mem.eql(u8, flag.long, name)) {
            return idx;
        }
        // Check aliases
        if (flag.aliases) |aliases| {
            for (aliases) |alias| {
                if (std.mem.eql(u8, alias, name)) {
                    return idx;
                }
            }
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
                // Countable flag: increment level
                if (flag.countable) {
                    result.verbose_level +|= 1; // Saturating add to prevent overflow
                }
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

/// Check if a value is valid for a flag with choices
fn isValidChoice(flag: Flag, value: []const u8) bool {
    if (flag.choices) |choices| {
        for (choices) |choice| {
            if (std.mem.eql(u8, value, choice)) {
                return true;
            }
        }
        return false;
    }
    // No choices defined, any value is valid
    return true;
}

/// Run the validator for a flag's value
pub fn runValidator(validator: Validator, value: []const u8) bool {
    return switch (validator) {
        .none => true,
        .positive_integer => validatePositiveInteger(value),
        .non_negative_integer => validateNonNegativeInteger(value),
        .file_path => validateFilePath(value),
        .shell_name => validateShellName(value),
    };
}

fn validatePositiveInteger(value: []const u8) bool {
    const num = std.fmt.parseInt(usize, value, 10) catch return false;
    return num > 0;
}

fn validateNonNegativeInteger(value: []const u8) bool {
    _ = std.fmt.parseInt(usize, value, 10) catch return false;
    return true;
}

fn validateFilePath(value: []const u8) bool {
    if (value.len == 0) return false;
    // Check for control characters
    for (value) |c| {
        if (c < 32 and c != '\t') return false;
    }
    return true;
}

fn validateShellName(value: []const u8) bool {
    return std.mem.eql(u8, value, "bash") or
        std.mem.eql(u8, value, "zsh") or
        std.mem.eql(u8, value, "fish");
}

/// Get the expected type description for a validator
pub fn getValidatorDescription(validator: Validator) []const u8 {
    return switch (validator) {
        .none => "",
        .positive_integer => "a positive integer",
        .non_negative_integer => "a non-negative integer",
        .file_path => "a file path",
        .shell_name => "bash, zsh, or fish",
    };
}

/// Set a flag to its negated (false) state for --no-X handling
fn setFlagNegated(result: *Args, flag_idx: usize) void {
    const flag = flags[flag_idx];
    const name = flag.long;

    // Only negatable boolean flags can be negated
    if (!flag.negatable or flag.takes_value != .none) return;

    if (std.mem.eql(u8, name, "verbose")) {
        result.verbose = false;
        result.verbose_level = 0;
    } else if (std.mem.eql(u8, name, "yes")) {
        result.yes = false;
    }
    // Add other negatable flags as needed
}

/// Print deprecation warning to stderr
fn printDeprecationWarning(flag: Flag) void {
    if (flag.deprecated) |msg| {
        var buf: [256]u8 = undefined;
        const output = std.fmt.bufPrint(&buf, ansi.warn_prefix ++ "--{s} is deprecated: {s}\n", .{ flag.long, msg }) catch return;
        compat.getStdErr().writeAll(output) catch {};
    }
}

/// Apply environment variable fallbacks for flags not set via CLI
/// Precedence: CLI arg (already set) → env var → default
fn applyEnvFallbacks(result: *Args) void {
    for (flags) |flag| {
        if (flag.env) |env_name| {
            if (std.posix.getenv(env_name)) |env_value| {
                applyEnvValue(result, flag, env_value);
            }
        }
    }
}

/// Apply a single environment variable value to the result
fn applyEnvValue(result: *Args, flag: Flag, env_value: []const u8) void {
    const name = flag.long;

    // For boolean flags, check if env value is truthy
    if (flag.takes_value == .none) {
        const is_truthy = isTruthyEnvValue(env_value);
        if (std.mem.eql(u8, name, "dry-run")) {
            if (!result.dry_run) result.dry_run = is_truthy;
        } else if (std.mem.eql(u8, name, "verbose")) {
            if (!result.verbose and is_truthy) {
                result.verbose = true;
                // Try to parse as number for verbose level
                if (std.fmt.parseInt(u8, env_value, 10)) |level| {
                    if (result.verbose_level == 0) result.verbose_level = level;
                } else |_| {
                    if (result.verbose_level == 0) result.verbose_level = 1;
                }
            }
        } else if (std.mem.eql(u8, name, "yes")) {
            if (!result.yes) result.yes = is_truthy;
        }
    } else {
        // Value flags
        if (std.mem.eql(u8, name, "jakefile")) {
            // Only apply if still at default
            if (std.mem.eql(u8, result.jakefile, "Jakefile")) {
                result.jakefile = env_value;
            }
        } else if (std.mem.eql(u8, name, "jobs")) {
            if (result.jobs == null) {
                if (std.fmt.parseInt(usize, env_value, 10)) |n| {
                    result.jobs = n;
                } else |_| {}
            }
        }
    }
}

/// Check if an environment variable value is truthy
fn isTruthyEnvValue(value: []const u8) bool {
    // Empty or "0" or "false" are falsy
    if (value.len == 0) return false;
    if (std.mem.eql(u8, value, "0")) return false;
    if (std.ascii.eqlIgnoreCase(value, "false")) return false;
    if (std.ascii.eqlIgnoreCase(value, "no")) return false;
    if (std.ascii.eqlIgnoreCase(value, "off")) return false;
    return true;
}

/// Print a single flag entry to the help output
fn printFlagHelp(writer: anytype, flag: Flag) void {
    // Format: "  -X, --long-name VALUE  Description"
    writer.writeAll("  ") catch {};

    // Short flag in Jake Rose (comma not colored)
    if (flag.short) |s| {
        writer.writeAll(ansi.jake_rose) catch {};
        writer.print("-{c}", .{s}) catch {};
        writer.writeAll(ansi.reset ++ ", ") catch {};
    } else {
        writer.writeAll("    ") catch {};
    }

    // Long flag in Jake Rose
    writer.writeAll(ansi.jake_rose ++ "--") catch {};
    writer.writeAll(flag.long) catch {};
    writer.writeAll(ansi.reset) catch {};

    // Value placeholder in muted
    if (flag.value_name) |name| {
        writer.writeAll(" " ++ ansi.muted) catch {};
        if (flag.takes_value == .optional) {
            writer.print("[{s}]", .{name}) catch {};
        } else {
            writer.writeAll(name) catch {};
        }
        writer.writeAll(ansi.reset) catch {};
    }

    // Padding to align descriptions (target column ~24)
    const used = 2 + 4 + 2 + flag.long.len + if (flag.value_name) |n| n.len + 3 else 0;
    const pad = if (used < 26) 26 - used else 2;
    for (0..pad) |_| {
        writer.writeAll(" ") catch {};
    }

    // Description (regular white)
    writer.print("{s}", .{flag.desc}) catch {};
    if (flag.default_display) |default| {
        writer.writeAll(ansi.muted) catch {};
        writer.print(" (default: {s})", .{default}) catch {};
        writer.writeAll(ansi.reset) catch {};
    }
    if (flag.env) |env_name| {
        writer.writeAll(ansi.muted) catch {};
        writer.print(" [env: {s}]", .{env_name}) catch {};
        writer.writeAll(ansi.reset) catch {};
    }
    writer.writeAll("\n") catch {};
}

/// Print help text to writer, auto-generated from flags array
pub fn printHelp(writer: anytype) void {
    // v4 format: {j} jake — modern command runner
    writer.writeAll("\n" ++ ansi.jake_rose ++ ansi.logo ++ ansi.reset) catch {};
    writer.writeAll(" " ++ ansi.bold ++ "jake" ++ ansi.reset) catch {};
    writer.writeAll(ansi.muted ++ " — modern command runner" ++ ansi.reset ++ "\n\n") catch {};

    // Usage: header in bold
    writer.writeAll(ansi.bold ++ "Usage:" ++ ansi.reset ++ " jake [options] [recipe] [args...]\n\n") catch {};

    // Print flags grouped by category
    for (categories) |category| {
        // Print category header
        writer.writeAll(ansi.bold) catch {};
        writer.writeAll(category) catch {};
        writer.writeAll(":" ++ ansi.reset ++ "\n") catch {};

        // Print flags in this category
        for (flags) |flag| {
            if (flag.hidden) continue;
            const flag_category = flag.category orelse "General";
            if (std.mem.eql(u8, flag_category, category)) {
                printFlagHelp(writer, flag);
            }
        }
        writer.writeAll("\n") catch {};
    }

    // Examples: header in bold (v4 format)
    writer.writeAll("\n" ++ ansi.bold ++ "Examples:" ++ ansi.reset ++ "\n") catch {};
    // Commands in default, descriptions in muted
    writer.writeAll("  jake build            ") catch {};
    writer.writeAll(ansi.muted ++ "Run the build recipe" ++ ansi.reset ++ "\n") catch {};
    writer.writeAll("  jake test -v          ") catch {};
    writer.writeAll(ansi.muted ++ "Run tests with verbose output" ++ ansi.reset ++ "\n") catch {};
    writer.writeAll("  jake -w dev           ") catch {};
    writer.writeAll(ansi.muted ++ "Watch and rebuild on changes" ++ ansi.reset ++ "\n") catch {};
    writer.writeAll("  jake release.all -j4  ") catch {};
    writer.writeAll(ansi.muted ++ "Parallel release builds" ++ ansi.reset ++ "\n") catch {};
}

/// Find similar flag names for "Did you mean?" suggestions.
/// Returns the best match if within threshold, null otherwise.
pub fn findSimilarFlag(unknown: []const u8) ?[]const u8 {
    // Strip leading dashes to get the flag name
    const name = if (std.mem.startsWith(u8, unknown, "--"))
        unknown[2..]
    else if (unknown.len > 1 and unknown[0] == '-')
        unknown[1..]
    else
        unknown;

    if (name.len == 0) return null;

    var best_match: ?[]const u8 = null;
    var best_distance: usize = std.math.maxInt(usize);

    // Maximum distance threshold: 2 for short names, 3 for longer names
    const max_distance: usize = if (name.len <= 4) 2 else 3;

    for (flags) |flag| {
        // Skip hidden flags
        if (flag.hidden) continue;

        // Check long flag name
        const dist = suggest.levenshteinDistance(name, flag.long);
        if (dist > 0 and dist <= max_distance and dist < best_distance) {
            best_distance = dist;
            best_match = flag.long;
        }
    }

    return best_match;
}

/// Format a flag suggestion with proper prefix
fn formatFlagSuggestion(buf: []u8, suggestion: []const u8) []const u8 {
    var fbs = std.io.fixedBufferStream(buf);
    const writer = fbs.writer();
    writer.print("Did you mean '--{s}'?\n", .{suggestion}) catch return "";
    return fbs.getWritten();
}

/// Print error message for parse failure (simple version for backward compatibility)
pub fn printError(writer: anytype, err: ParseError, arg: []const u8) void {
    printErrorWithContext(writer, err, arg, .{});
}

/// Print error message with rich context
pub fn printErrorWithContext(writer: anytype, err: ParseError, arg: []const u8, ctx: ErrorContext) void {
    switch (err) {
        error.UnknownFlag => {
            writer.print(ansi.err_prefix ++ "Unknown option: {s}\n", .{arg}) catch {};
            // Try to suggest similar flags
            if (findSimilarFlag(arg)) |similar| {
                var buf: [128]u8 = undefined;
                const suggestion = formatFlagSuggestion(&buf, similar);
                writer.writeAll(suggestion) catch {};
            } else {
                writer.writeAll("Run 'jake --help' for usage.\n") catch {};
            }
        },
        error.MissingValue => {
            writer.print(ansi.err_prefix ++ "Option '{s}' requires a value\n", .{arg}) catch {};
            // Show expected type if available
            if (ctx.expected_type.len > 0) {
                writer.print("       Expected: {s}\n", .{ctx.expected_type}) catch {};
            }
            // Show usage hint
            printUsageHint(writer, arg);
        },
        error.InvalidValue => {
            if (ctx.provided_value.len > 0) {
                writer.print(ansi.err_prefix ++ "Invalid value for {s}: \"{s}\"\n", .{ arg, ctx.provided_value }) catch {};
            } else {
                writer.print(ansi.err_prefix ++ "Invalid value for option: {s}\n", .{arg}) catch {};
            }
            // Show expected type if available
            if (ctx.expected_type.len > 0) {
                writer.print("       Expected: {s}\n", .{ctx.expected_type}) catch {};
            }
            // Show usage hint
            printUsageHint(writer, arg);
        },
        error.InvalidChoice => {
            writer.print(ansi.err_prefix ++ "Invalid value for {s}: \"{s}\"\n", .{ arg, ctx.provided_value }) catch {};
            if (ctx.choices) |choices| {
                writer.writeAll("       Must be one of: ") catch {};
                for (choices, 0..) |choice, i| {
                    if (i > 0) writer.writeAll(", ") catch {};
                    writer.print("{s}", .{choice}) catch {};
                }
                writer.writeAll("\n") catch {};
            }
        },
        error.MutuallyExclusive => {
            writer.print(ansi.err_prefix ++ "Options {s} and {s} cannot be used together\n", .{ arg, ctx.conflicting_flag }) catch {};
        },
        error.RequiredTogether => {
            writer.print(ansi.err_prefix ++ "Option {s} requires {s} to also be specified\n", .{ arg, ctx.required_flag }) catch {};
        },
    }
}

/// Print usage hint for a specific flag
fn printUsageHint(writer: anytype, arg: []const u8) void {
    // Strip leading dashes
    const name = if (std.mem.startsWith(u8, arg, "--"))
        arg[2..]
    else if (arg.len > 1 and arg[0] == '-')
        arg[1..]
    else
        arg;

    // Find the flag and show usage
    for (flags) |flag| {
        if (std.mem.eql(u8, flag.long, name) or (flag.short != null and name.len == 1 and name[0] == flag.short.?)) {
            writer.writeAll("Usage: jake ") catch {};
            if (flag.short) |s| {
                writer.print("-{c}", .{s}) catch {};
            } else {
                writer.print("--{s}", .{flag.long}) catch {};
            }
            if (flag.value_name) |vn| {
                if (flag.takes_value == .optional) {
                    writer.print(" [{s}]", .{vn}) catch {};
                } else {
                    writer.print(" {s}", .{vn}) catch {};
                }
            }
            writer.writeAll(" [RECIPE]\n") catch {};
            return;
        }
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
    // Check key elements are present (with ANSI codes between flags)
    try expect(std.mem.indexOf(u8, output, "-h") != null);
    try expect(std.mem.indexOf(u8, output, "--help") != null);
    try expect(std.mem.indexOf(u8, output, "-f") != null);
    try expect(std.mem.indexOf(u8, output, "--jakefile") != null);
    try expect(std.mem.indexOf(u8, output, "FILE") != null);
    // Check branded elements (v4 format)
    try expect(std.mem.indexOf(u8, output, ansi.logo) != null);
    try expect(std.mem.indexOf(u8, output, "Usage:") != null);
    // Check category headers are present
    try expect(std.mem.indexOf(u8, output, "General:") != null);
    try expect(std.mem.indexOf(u8, output, "Output:") != null);
    try expect(std.mem.indexOf(u8, output, "Execution:") != null);
    try expect(std.mem.indexOf(u8, output, "File:") != null);
    try expect(std.mem.indexOf(u8, output, "Shell:") != null);
    try expect(std.mem.indexOf(u8, output, "Examples:") != null);
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
        "jake",        "build",
        "-h",          "-V",
        "-l",          "-a",
        "-n",          "-v",
        "-y",          "--short",
        "--summary",   "--install",
        "--uninstall",
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

// ============================================================================
// "Did you mean?" suggestion tests
// ============================================================================

test "findSimilarFlag suggests --verbose for --vrsbose" {
    const suggestion = findSimilarFlag("--vrsbose");
    try expect(suggestion != null);
    try expectEqualStrings("verbose", suggestion.?);
}

test "findSimilarFlag suggests --verbose for --verbos" {
    const suggestion = findSimilarFlag("--verbos");
    try expect(suggestion != null);
    try expectEqualStrings("verbose", suggestion.?);
}

test "findSimilarFlag suggests --help for --hlep" {
    const suggestion = findSimilarFlag("--hlep");
    try expect(suggestion != null);
    try expectEqualStrings("help", suggestion.?);
}

test "findSimilarFlag suggests --dry-run for --dryrun" {
    const suggestion = findSimilarFlag("--dryrun");
    try expect(suggestion != null);
    try expectEqualStrings("dry-run", suggestion.?);
}

test "findSimilarFlag suggests --list for --lsit" {
    const suggestion = findSimilarFlag("--lsit");
    try expect(suggestion != null);
    try expectEqualStrings("list", suggestion.?);
}

test "findSimilarFlag suggests --jakefile for --jakeifle" {
    const suggestion = findSimilarFlag("--jakeifle");
    try expect(suggestion != null);
    try expectEqualStrings("jakefile", suggestion.?);
}

test "findSimilarFlag returns null for completely different flag" {
    const suggestion = findSimilarFlag("--xyzabc123");
    try expect(suggestion == null);
}

test "findSimilarFlag returns null for empty flag" {
    const suggestion = findSimilarFlag("--");
    try expect(suggestion == null);
}

test "findSimilarFlag handles single dash prefix" {
    // -verbos should still suggest verbose
    const suggestion = findSimilarFlag("-verbos");
    try expect(suggestion != null);
    try expectEqualStrings("verbose", suggestion.?);
}

test "findSimilarFlag suggests --watch for --wtach" {
    const suggestion = findSimilarFlag("--wtach");
    try expect(suggestion != null);
    try expectEqualStrings("watch", suggestion.?);
}

test "formatFlagSuggestion formats correctly" {
    var buf: [128]u8 = undefined;
    const result = formatFlagSuggestion(&buf, "verbose");
    try expectEqualStrings("Did you mean '--verbose'?\n", result);
}

// ============================================================================
// Countable/Repeatable Flags Tests
// ============================================================================

test "single -v sets verbose_level to 1" {
    const args = try parse(testing.allocator, &.{ "jake", "-v" });
    try expect(args.verbose);
    try expect(args.verbose_level == 1);
}

test "-vv sets verbose_level to 2" {
    const args = try parse(testing.allocator, &.{ "jake", "-vv" });
    try expect(args.verbose);
    try expect(args.verbose_level == 2);
}

test "-vvv sets verbose_level to 3" {
    const args = try parse(testing.allocator, &.{ "jake", "-vvv" });
    try expect(args.verbose);
    try expect(args.verbose_level == 3);
}

test "--verbose sets verbose_level to 1" {
    const args = try parse(testing.allocator, &.{ "jake", "--verbose" });
    try expect(args.verbose);
    try expect(args.verbose_level == 1);
}

test "--verbose --verbose sets verbose_level to 2" {
    const args = try parse(testing.allocator, &.{ "jake", "--verbose", "--verbose" });
    try expect(args.verbose);
    try expect(args.verbose_level == 2);
}

test "mixed -v --verbose accumulates" {
    const args = try parse(testing.allocator, &.{ "jake", "-v", "--verbose", "-v" });
    try expect(args.verbose);
    try expect(args.verbose_level == 3);
}

test "combined -vnv increments verbose_level for each v" {
    const args = try parse(testing.allocator, &.{ "jake", "-vnv" });
    try expect(args.verbose);
    try expect(args.dry_run);
    try expect(args.verbose_level == 2);
}

// ============================================================================
// Negatable Flags Tests
// ============================================================================

test "--no-verbose sets verbose to false" {
    const args = try parse(testing.allocator, &.{ "jake", "--no-verbose" });
    try expect(!args.verbose);
    try expect(args.verbose_level == 0);
}

test "--no-verbose after --verbose overrides to false" {
    const args = try parse(testing.allocator, &.{ "jake", "--verbose", "--no-verbose" });
    try expect(!args.verbose);
    try expect(args.verbose_level == 0);
}

test "--verbose after --no-verbose overrides to true" {
    const args = try parse(testing.allocator, &.{ "jake", "--no-verbose", "--verbose" });
    try expect(args.verbose);
    try expect(args.verbose_level == 1);
}

test "--no-yes sets yes to false" {
    const args = try parse(testing.allocator, &.{ "jake", "--no-yes" });
    try expect(!args.yes);
}

test "--no-help errors (not negatable)" {
    const result = parse(testing.allocator, &.{ "jake", "--no-help" });
    try expectError(error.UnknownFlag, result);
}

test "--no-unknown errors" {
    const result = parse(testing.allocator, &.{ "jake", "--no-unknown" });
    try expectError(error.UnknownFlag, result);
}

test "negatable flag with other flags" {
    const args = try parse(testing.allocator, &.{ "jake", "-n", "--no-verbose", "-l" });
    try expect(args.dry_run);
    try expect(!args.verbose);
    try expect(args.list);
}

// ============================================================================
// Environment Variable Fallback Tests
// ============================================================================

test "isTruthyEnvValue returns true for truthy values" {
    try expect(isTruthyEnvValue("1"));
    try expect(isTruthyEnvValue("true"));
    try expect(isTruthyEnvValue("TRUE"));
    try expect(isTruthyEnvValue("yes"));
    try expect(isTruthyEnvValue("YES"));
    try expect(isTruthyEnvValue("on"));
    try expect(isTruthyEnvValue("ON"));
    try expect(isTruthyEnvValue("anything"));
}

test "isTruthyEnvValue returns false for falsy values" {
    try expect(!isTruthyEnvValue(""));
    try expect(!isTruthyEnvValue("0"));
    try expect(!isTruthyEnvValue("false"));
    try expect(!isTruthyEnvValue("FALSE"));
    try expect(!isTruthyEnvValue("False"));
    try expect(!isTruthyEnvValue("no"));
    try expect(!isTruthyEnvValue("NO"));
    try expect(!isTruthyEnvValue("No"));
    try expect(!isTruthyEnvValue("off"));
    try expect(!isTruthyEnvValue("OFF"));
    try expect(!isTruthyEnvValue("Off"));
}

test "Flag struct has env field" {
    const flag_with_env = Flag{
        .short = 'f',
        .long = "jakefile",
        .desc = "Use specified Jakefile",
        .env = "JAKEFILE",
    };
    try expectEqualStrings("JAKEFILE", flag_with_env.env.?);

    const flag_without_env = Flag{
        .short = 'h',
        .long = "help",
        .desc = "Show help",
    };
    try expect(flag_without_env.env == null);
}

test "printHelp shows env var hints" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    printHelp(stream.writer());
    const output = stream.getWritten();
    // Check that env vars are shown in help
    try expect(std.mem.indexOf(u8, output, "[env: JAKEFILE]") != null);
    try expect(std.mem.indexOf(u8, output, "[env: JAKE_JOBS]") != null);
    try expect(std.mem.indexOf(u8, output, "[env: JAKE_VERBOSE]") != null);
    try expect(std.mem.indexOf(u8, output, "[env: JAKE_YES]") != null);
    try expect(std.mem.indexOf(u8, output, "[env: JAKE_DRY_RUN]") != null);
}

// ============================================================================
// Flag Aliases Tests
// ============================================================================

test "Flag struct has aliases field" {
    const flag_with_aliases = Flag{
        .short = 'n',
        .long = "dry-run",
        .desc = "Print commands without executing",
        .aliases = &.{ "dryrun", "simulate" },
    };
    try expect(flag_with_aliases.aliases != null);
    try expectEqual(@as(usize, 2), flag_with_aliases.aliases.?.len);
    try expectEqualStrings("dryrun", flag_with_aliases.aliases.?[0]);
    try expectEqualStrings("simulate", flag_with_aliases.aliases.?[1]);

    const flag_without_aliases = Flag{
        .short = 'h',
        .long = "help",
        .desc = "Show help",
    };
    try expect(flag_without_aliases.aliases == null);
}

test "--dryrun alias works for --dry-run" {
    const args = try parse(testing.allocator, &.{ "jake", "--dryrun" });
    try expect(args.dry_run);
}

test "alias works with recipe" {
    const args = try parse(testing.allocator, &.{ "jake", "--dryrun", "build" });
    try expect(args.dry_run);
    try expectEqualStrings("build", args.recipe.?);
}

test "matchLongFlag finds aliases" {
    // --dryrun should match the dry-run flag
    const idx = matchLongFlag("dryrun");
    try expect(idx != null);
    try expectEqualStrings("dry-run", flags[idx.?].long);
}

test "matchLongFlag prefers primary name" {
    // --dry-run should still work
    const idx = matchLongFlag("dry-run");
    try expect(idx != null);
    try expectEqualStrings("dry-run", flags[idx.?].long);
}

// ============================================================================
// Short Flag Value Attachment Tests (-xVALUE)
// ============================================================================

test "-fcustom.jake attaches value to jakefile flag" {
    const args = try parse(testing.allocator, &.{ "jake", "-fcustom.jake" });
    try expectEqualStrings("custom.jake", args.jakefile);
}

test "-fpath/to/file.jake works with path" {
    const args = try parse(testing.allocator, &.{ "jake", "-fpath/to/file.jake" });
    try expectEqualStrings("path/to/file.jake", args.jakefile);
}

test "-j4 still works (regression)" {
    const args = try parse(testing.allocator, &.{ "jake", "-j4" });
    try expectEqual(@as(usize, 4), args.jobs.?);
}

test "-j16 works for larger numbers" {
    const args = try parse(testing.allocator, &.{ "jake", "-j16" });
    try expectEqual(@as(usize, 16), args.jobs.?);
}

test "-sbuild attaches value to show flag" {
    const args = try parse(testing.allocator, &.{ "jake", "-sbuild" });
    try expectEqualStrings("build", args.show.?);
}

test "-fcustom.jake with recipe" {
    const args = try parse(testing.allocator, &.{ "jake", "-fcustom.jake", "build" });
    try expectEqualStrings("custom.jake", args.jakefile);
    try expectEqualStrings("build", args.recipe.?);
}

test "-j4 with other flags and recipe" {
    const args = try parse(testing.allocator, &.{ "jake", "-v", "-j4", "build" });
    try expect(args.verbose);
    try expectEqual(@as(usize, 4), args.jobs.?);
    try expectEqualStrings("build", args.recipe.?);
}

// ============================================================================
// Better Error Messages Tests
// ============================================================================

test "printErrorWithContext shows rich error for InvalidValue" {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    printErrorWithContext(stream.writer(), error.InvalidValue, "--jobs", .{
        .provided_value = "abc",
        .expected_type = "a positive integer",
    });
    const output = stream.getWritten();
    try expect(std.mem.indexOf(u8, output, "Invalid value for --jobs") != null);
    try expect(std.mem.indexOf(u8, output, "\"abc\"") != null);
    try expect(std.mem.indexOf(u8, output, "Expected: a positive integer") != null);
}

test "printErrorWithContext shows rich error for MissingValue" {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    printErrorWithContext(stream.writer(), error.MissingValue, "--jakefile", .{
        .expected_type = "a file path",
    });
    const output = stream.getWritten();
    try expect(std.mem.indexOf(u8, output, "requires a value") != null);
    try expect(std.mem.indexOf(u8, output, "Expected: a file path") != null);
}

test "printErrorWithContext shows rich error for InvalidChoice" {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    printErrorWithContext(stream.writer(), error.InvalidChoice, "--format", .{
        .provided_value = "xml",
        .choices = &[_][]const u8{ "json", "yaml", "toml" },
    });
    const output = stream.getWritten();
    try expect(std.mem.indexOf(u8, output, "Invalid value for --format") != null);
    try expect(std.mem.indexOf(u8, output, "\"xml\"") != null);
    try expect(std.mem.indexOf(u8, output, "Must be one of: json, yaml, toml") != null);
}

test "printErrorWithContext shows MutuallyExclusive error" {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    printErrorWithContext(stream.writer(), error.MutuallyExclusive, "--list", .{
        .conflicting_flag = "--show",
    });
    const output = stream.getWritten();
    try expect(std.mem.indexOf(u8, output, "--list") != null);
    try expect(std.mem.indexOf(u8, output, "--show") != null);
    try expect(std.mem.indexOf(u8, output, "cannot be used together") != null);
}

test "printErrorWithContext shows RequiredTogether error" {
    var buf: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    printErrorWithContext(stream.writer(), error.RequiredTogether, "--username", .{
        .required_flag = "--password",
    });
    const output = stream.getWritten();
    try expect(std.mem.indexOf(u8, output, "--username") != null);
    try expect(std.mem.indexOf(u8, output, "requires --password") != null);
}

test "printUsageHint shows correct usage for --jakefile" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    printUsageHint(stream.writer(), "--jakefile");
    const output = stream.getWritten();
    try expect(std.mem.indexOf(u8, output, "Usage: jake -f FILE") != null);
}

// ============================================================================
// Choices/Enum Restriction Tests
// ============================================================================

test "Flag struct has choices field" {
    const flag_with_choices = Flag{
        .short = null,
        .long = "format",
        .desc = "Output format",
        .takes_value = .required,
        .choices = &.{ "json", "yaml", "toml" },
    };
    try expect(flag_with_choices.choices != null);
    try expectEqual(@as(usize, 3), flag_with_choices.choices.?.len);
    try expectEqualStrings("json", flag_with_choices.choices.?[0]);
}

test "isValidChoice returns true for valid choice" {
    const flag = Flag{
        .short = null,
        .long = "format",
        .desc = "Output format",
        .choices = &.{ "json", "yaml", "toml" },
    };
    try expect(isValidChoice(flag, "json"));
    try expect(isValidChoice(flag, "yaml"));
    try expect(isValidChoice(flag, "toml"));
}

test "isValidChoice returns false for invalid choice" {
    const flag = Flag{
        .short = null,
        .long = "format",
        .desc = "Output format",
        .choices = &.{ "json", "yaml", "toml" },
    };
    try expect(!isValidChoice(flag, "xml"));
    try expect(!isValidChoice(flag, "JSON")); // case-sensitive
    try expect(!isValidChoice(flag, ""));
}

test "isValidChoice returns true when no choices defined" {
    const flag = Flag{
        .short = 'f',
        .long = "file",
        .desc = "A file",
    };
    try expect(isValidChoice(flag, "anything"));
    try expect(isValidChoice(flag, "foo.txt"));
}

// ============================================================================
// Mutual Exclusivity Tests
// ============================================================================

test "--list and --show cannot be used together" {
    const result = parse(testing.allocator, &.{ "jake", "--list", "--show", "build" });
    try expectError(error.MutuallyExclusive, result);
}

test "-l and -s cannot be used together" {
    const result = parse(testing.allocator, &.{ "jake", "-l", "-s", "build" });
    try expectError(error.MutuallyExclusive, result);
}

test "--list alone works" {
    const args = try parse(testing.allocator, &.{ "jake", "--list" });
    try expect(args.list);
    try expect(args.show == null);
}

test "--show alone works" {
    const args = try parse(testing.allocator, &.{ "jake", "--show", "build" });
    try expect(!args.list);
    try expectEqualStrings("build", args.show.?);
}

// ============================================================================
// Required-Together Tests
// ============================================================================

test "--check requires --fmt" {
    const result = parse(testing.allocator, &.{ "jake", "--check" });
    try expectError(error.RequiredTogether, result);
}

test "--dump requires --fmt" {
    const result = parse(testing.allocator, &.{ "jake", "--dump" });
    try expectError(error.RequiredTogether, result);
}

test "--fmt --check works together" {
    const args = try parse(testing.allocator, &.{ "jake", "--fmt", "--check" });
    try expect(args.fmt);
    try expect(args.check);
}

test "--fmt --dump works together" {
    const args = try parse(testing.allocator, &.{ "jake", "--fmt", "--dump" });
    try expect(args.fmt);
    try expect(args.dump);
}

test "--fmt alone works" {
    const args = try parse(testing.allocator, &.{ "jake", "--fmt" });
    try expect(args.fmt);
    try expect(!args.check);
    try expect(!args.dump);
}

// ============================================================================
// Value Validator Tests
// ============================================================================

test "validatePositiveInteger accepts positive numbers" {
    try expect(validatePositiveInteger("1"));
    try expect(validatePositiveInteger("42"));
    try expect(validatePositiveInteger("1000"));
}

test "validatePositiveInteger rejects zero and negative" {
    try expect(!validatePositiveInteger("0"));
    try expect(!validatePositiveInteger("-1"));
    try expect(!validatePositiveInteger("abc"));
    try expect(!validatePositiveInteger(""));
}

test "validateNonNegativeInteger accepts zero and positive" {
    try expect(validateNonNegativeInteger("0"));
    try expect(validateNonNegativeInteger("1"));
    try expect(validateNonNegativeInteger("100"));
}

test "validateNonNegativeInteger rejects invalid input" {
    try expect(!validateNonNegativeInteger("-1"));
    try expect(!validateNonNegativeInteger("abc"));
    try expect(!validateNonNegativeInteger(""));
}

test "validateFilePath accepts valid paths" {
    try expect(validateFilePath("Jakefile"));
    try expect(validateFilePath("/path/to/file"));
    try expect(validateFilePath("./relative/path"));
    try expect(validateFilePath("file with spaces.txt"));
}

test "validateFilePath rejects invalid paths" {
    try expect(!validateFilePath(""));
    try expect(!validateFilePath("file\x00name")); // null byte
}

test "validateShellName accepts valid shells" {
    try expect(validateShellName("bash"));
    try expect(validateShellName("zsh"));
    try expect(validateShellName("fish"));
}

test "validateShellName rejects invalid shells" {
    try expect(!validateShellName("sh"));
    try expect(!validateShellName("BASH"));
    try expect(!validateShellName(""));
}

test "runValidator dispatches correctly" {
    try expect(runValidator(.none, "anything"));
    try expect(runValidator(.positive_integer, "42"));
    try expect(!runValidator(.positive_integer, "0"));
    try expect(runValidator(.file_path, "test.txt"));
    try expect(runValidator(.shell_name, "bash"));
}

test "getValidatorDescription returns descriptions" {
    try expectEqualStrings("", getValidatorDescription(.none));
    try expectEqualStrings("a positive integer", getValidatorDescription(.positive_integer));
    try expectEqualStrings("a file path", getValidatorDescription(.file_path));
    try expectEqualStrings("bash, zsh, or fish", getValidatorDescription(.shell_name));
}

// ============================================================================
// Streaming Parser (quickScan) Tests
// ============================================================================

test "quickScan detects --help" {
    try expectEqual(QuickAction.help, quickScan(&.{ "jake", "--help" }));
    try expectEqual(QuickAction.help, quickScan(&.{ "jake", "build", "--help" }));
    try expectEqual(QuickAction.help, quickScan(&.{ "jake", "-v", "--help" }));
}

test "quickScan detects -h" {
    try expectEqual(QuickAction.help, quickScan(&.{ "jake", "-h" }));
    try expectEqual(QuickAction.help, quickScan(&.{ "jake", "build", "-h" }));
}

test "quickScan detects --version" {
    try expectEqual(QuickAction.version, quickScan(&.{ "jake", "--version" }));
    try expectEqual(QuickAction.version, quickScan(&.{ "jake", "build", "--version" }));
}

test "quickScan detects -V" {
    try expectEqual(QuickAction.version, quickScan(&.{ "jake", "-V" }));
    try expectEqual(QuickAction.version, quickScan(&.{ "jake", "-V", "build" }));
}

test "quickScan returns none for normal args" {
    try expectEqual(QuickAction.none, quickScan(&.{ "jake", "build" }));
    try expectEqual(QuickAction.none, quickScan(&.{ "jake", "-v", "test" }));
    try expectEqual(QuickAction.none, quickScan(&.{"jake"}));
}

test "quickScan stops at -- separator" {
    // --help after -- should be ignored
    try expectEqual(QuickAction.none, quickScan(&.{ "jake", "--", "--help" }));
    try expectEqual(QuickAction.none, quickScan(&.{ "jake", "--", "-h" }));
}

test "quickScan handles empty args" {
    try expectEqual(QuickAction.none, quickScan(&.{}));
}

test "quickScan prioritizes first match" {
    // -h appears before --version, should return help
    try expectEqual(QuickAction.help, quickScan(&.{ "jake", "-h", "--version" }));
    // --version appears before -h, should return version
    try expectEqual(QuickAction.version, quickScan(&.{ "jake", "--version", "-h" }));
}

// ============================================================================
// Fuzz Testing
// ============================================================================

test "fuzz argument parsing" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, input: []const u8) !void {
            const allocator = std.testing.allocator;

            // Split fuzzed input by null bytes to create argv-like array
            var args_list: std.ArrayListUnmanaged([]const u8) = .empty;
            defer args_list.deinit(allocator);

            // Add a program name (required by parser)
            args_list.append(allocator, "jake") catch return;

            // Split input by null bytes and newlines to simulate arguments
            var iter = std.mem.splitAny(u8, input, &[_]u8{ 0, '\n', ' ' });
            while (iter.next()) |part| {
                if (part.len > 0 and part.len < 256) {
                    args_list.append(allocator, part) catch return;
                }
            }

            // Try to parse - errors are expected for invalid input
            var result = parse(allocator, args_list.items) catch {
                return;
            };
            defer result.deinit(allocator);
        }
    }.testOne, .{});
}

test "fuzz findSimilarFlag" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, input: []const u8) !void {
            // Should never crash on any input
            _ = findSimilarFlag(input);
        }
    }.testOne, .{});
}
