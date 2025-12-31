// completions.zig - Shell completion script generators for jake
// Generates completion scripts for bash, zsh, and fish shells
// Includes smart installation with environment detection

const std = @import("std");
const builtin = @import("builtin");
const args_mod = @import("args.zig");
const color_mod = @import("color.zig");

/// Shell types supported for completion generation
pub const Shell = enum {
    bash,
    zsh,
    fish,

    pub fn fromString(s: []const u8) ?Shell {
        if (std.mem.eql(u8, s, "bash")) return .bash;
        if (std.mem.eql(u8, s, "zsh")) return .zsh;
        if (std.mem.eql(u8, s, "fish")) return .fish;
        return null;
    }

    pub fn toString(self: Shell) []const u8 {
        return switch (self) {
            .bash => "bash",
            .zsh => "zsh",
            .fish => "fish",
        };
    }
};

/// Zsh environment type for smart installation
pub const ZshEnv = enum {
    oh_my_zsh, // Has Oh-My-Zsh installed
    homebrew, // Has Homebrew zsh site-functions
    vanilla, // Plain zsh, needs .zshrc modification
};

/// Installation result with path and status
pub const InstallResult = struct {
    path: []const u8,
    config_modified: bool,
    needs_instructions: bool,
    instructions: ?[]const u8,
};

/// Markers for config file blocks
const CONFIG_BLOCK_START = "# >>> jake completion >>>";
const CONFIG_BLOCK_END = "# <<< jake completion <<<";

/// Detect shell from $SHELL environment variable
pub fn detectShell() ?Shell {
    // Shell completions are not applicable on Windows
    if (comptime builtin.os.tag == .windows) {
        return null;
    }
    const shell_path = std.posix.getenv("SHELL") orelse return null;
    const basename = std.fs.path.basename(shell_path);

    if (std.mem.eql(u8, basename, "bash")) return .bash;
    if (std.mem.eql(u8, basename, "zsh")) return .zsh;
    if (std.mem.eql(u8, basename, "fish")) return .fish;
    if (std.mem.startsWith(u8, basename, "bash")) return .bash;
    if (std.mem.startsWith(u8, basename, "zsh")) return .zsh;
    if (std.mem.startsWith(u8, basename, "fish")) return .fish;

    return null;
}

/// Get the user's home directory
fn getHomeDir() ?[]const u8 {
    if (comptime builtin.os.tag == .windows) {
        return null;
    }
    return std.posix.getenv("HOME");
}

/// Detect zsh environment type
pub fn detectZshEnv() ZshEnv {
    // Zsh environments are not applicable on Windows
    if (comptime builtin.os.tag == .windows) {
        return .vanilla;
    }
    const home = getHomeDir() orelse return .vanilla;

    // Check for Oh-My-Zsh (most specific first)
    // Look for $ZSH env var or ~/.oh-my-zsh directory
    if (std.posix.getenv("ZSH")) |zsh_dir| {
        // Verify it's actually Oh-My-Zsh by checking for oh-my-zsh.sh
        var path_buf: [512]u8 = undefined;
        const check_path = std.fmt.bufPrint(&path_buf, "{s}/oh-my-zsh.sh", .{zsh_dir}) catch return .vanilla;
        if (std.fs.cwd().access(check_path, .{})) |_| {
            return .oh_my_zsh;
        } else |_| {}
    }

    // Check for ~/.oh-my-zsh directory
    var omz_buf: [512]u8 = undefined;
    const omz_path = std.fmt.bufPrint(&omz_buf, "{s}/.oh-my-zsh/oh-my-zsh.sh", .{home}) catch return .vanilla;
    if (std.fs.cwd().access(omz_path, .{})) |_| {
        return .oh_my_zsh;
    } else |_| {}

    // Check for Homebrew zsh site-functions
    if (std.fs.cwd().access("/opt/homebrew/share/zsh/site-functions", .{})) |_| {
        return .homebrew;
    } else |_| {}

    // Also check Intel Mac Homebrew path
    if (std.fs.cwd().access("/usr/local/share/zsh/site-functions", .{})) |_| {
        return .homebrew;
    } else |_| {}

    return .vanilla;
}

/// Get the best installation path for zsh completions
fn getZshInstallPath(allocator: std.mem.Allocator) !struct { path: []const u8, env: ZshEnv } {
    // Not applicable on Windows
    if (comptime builtin.os.tag == .windows) {
        return error.NoHomeDir;
    }
    const home = getHomeDir() orelse return error.NoHomeDir;
    const env = detectZshEnv();

    const path = switch (env) {
        .oh_my_zsh => blk: {
            // Use $ZSH_CUSTOM if set, otherwise default
            const zsh_custom = std.posix.getenv("ZSH_CUSTOM") orelse {
                const zsh = std.posix.getenv("ZSH") orelse {
                    break :blk try std.fmt.allocPrint(allocator, "{s}/.oh-my-zsh/custom/completions/_jake", .{home});
                };
                break :blk try std.fmt.allocPrint(allocator, "{s}/custom/completions/_jake", .{zsh});
            };
            break :blk try std.fmt.allocPrint(allocator, "{s}/completions/_jake", .{zsh_custom});
        },
        .homebrew => blk: {
            // Try ARM Mac first, then Intel Mac
            if (std.fs.cwd().access("/opt/homebrew/share/zsh/site-functions", .{})) |_| {
                break :blk try allocator.dupe(u8, "/opt/homebrew/share/zsh/site-functions/_jake");
            } else |_| {}
            break :blk try allocator.dupe(u8, "/usr/local/share/zsh/site-functions/_jake");
        },
        .vanilla => try std.fmt.allocPrint(allocator, "{s}/.zsh/completions/_jake", .{home}),
    };

    return .{ .path = path, .env = env };
}

/// Check if a file contains our config block
fn hasConfigBlock(content: []const u8) bool {
    return std.mem.indexOf(u8, content, CONFIG_BLOCK_START) != null;
}

/// Remove existing config block from content
fn removeConfigBlock(allocator: std.mem.Allocator, content: []const u8) ![]const u8 {
    const start_idx = std.mem.indexOf(u8, content, CONFIG_BLOCK_START) orelse return try allocator.dupe(u8, content);
    const end_idx = std.mem.indexOf(u8, content, CONFIG_BLOCK_END) orelse return try allocator.dupe(u8, content);

    // Find the actual end (after the end marker and newline)
    var actual_end = end_idx + CONFIG_BLOCK_END.len;
    if (actual_end < content.len and content[actual_end] == '\n') {
        actual_end += 1;
    }

    // Find the start (including preceding newline if present)
    var actual_start = start_idx;
    if (actual_start > 0 and content[actual_start - 1] == '\n') {
        actual_start -= 1;
    }

    // Concatenate before and after
    const before = content[0..actual_start];
    const after = if (actual_end < content.len) content[actual_end..] else "";

    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ before, after });
}

/// Generate the config block for .zshrc
fn generateZshConfigBlock(allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
        \\
        \\{s}
        \\# This block is managed by jake. Do not edit manually.
        \\fpath=(~/.zsh/completions $fpath)
        \\autoload -Uz compinit && compinit -u
        \\{s}
    , .{ CONFIG_BLOCK_START, CONFIG_BLOCK_END });
}

/// Patch .zshrc with our config block
fn patchZshrc(allocator: std.mem.Allocator, writer: anytype) !bool {
    const home = getHomeDir() orelse return error.NoHomeDir;

    var path_buf: [512]u8 = undefined;
    const zshrc_path = std.fmt.bufPrint(&path_buf, "{s}/.zshrc", .{home}) catch return error.PathTooLong;

    // Read existing content
    const file = std.fs.cwd().openFile(zshrc_path, .{ .mode = .read_write }) catch |err| {
        if (err == error.FileNotFound) {
            // Create new .zshrc with our block
            const new_file = try std.fs.cwd().createFile(zshrc_path, .{});
            defer new_file.close();
            const block = try generateZshConfigBlock(allocator);
            defer allocator.free(block);
            try new_file.writeAll(block);
            return true;
        }
        return err;
    };
    defer file.close();

    // Read content
    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        try writer.print("Warning: Could not read ~/.zshrc: {s}\n", .{@errorName(err)});
        return false;
    };
    defer allocator.free(content);

    // Check if block already exists
    if (hasConfigBlock(content)) {
        // Remove old block first
        const cleaned = try removeConfigBlock(allocator, content);
        defer allocator.free(cleaned);

        // Add new block at end
        const block = try generateZshConfigBlock(allocator);
        defer allocator.free(block);

        const new_content = try std.fmt.allocPrint(allocator, "{s}{s}", .{ cleaned, block });
        defer allocator.free(new_content);

        // Rewrite file
        try file.seekTo(0);
        try file.writeAll(new_content);
        try file.setEndPos(new_content.len);

        return true;
    }

    // Append block to end
    const block = try generateZshConfigBlock(allocator);
    defer allocator.free(block);

    try file.seekFromEnd(0);
    try file.writeAll(block);

    return true;
}

/// Uninstall completion and config block
pub fn uninstall(allocator: std.mem.Allocator, shell: Shell, writer: anytype) !void {
    const home = getHomeDir() orelse return error.NoHomeDir;
    const color = color_mod.init();

    // Remove completion file
    switch (shell) {
        .bash => {
            var path_buf: [512]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "{s}/.local/share/bash-completion/completions/jake", .{home}) catch return;
            std.fs.cwd().deleteFile(path) catch |err| {
                if (err != error.FileNotFound) {
                    try writer.writeAll(color.warningYellow());
                    try writer.writeAll("Warning:");
                    try writer.writeAll(color.reset());
                    try writer.print(" Could not remove {s}: {s}\n", .{ path, @errorName(err) });
                }
            };
            try writer.writeAll(color.successGreen());
            try writer.writeAll(color_mod.symbols.success);
            try writer.writeAll(color.reset());
            try writer.print(" Removed bash completions from: {s}\n", .{path});
        },
        .zsh => {
            // Try all possible zsh locations
            const paths = [_][]const u8{
                "/.oh-my-zsh/custom/completions/_jake",
                "/.zsh/completions/_jake",
            };

            for (paths) |suffix| {
                var path_buf: [512]u8 = undefined;
                const path = std.fmt.bufPrint(&path_buf, "{s}{s}", .{ home, suffix }) catch continue;
                std.fs.cwd().deleteFile(path) catch continue;
                try writer.writeAll(color.successGreen());
                try writer.writeAll(color_mod.symbols.success);
                try writer.writeAll(color.reset());
                try writer.print(" Removed zsh completions from: {s}\n", .{path});
            }

            // Also try Homebrew paths (may fail due to permissions)
            const brew_paths = [_][]const u8{
                "/opt/homebrew/share/zsh/site-functions/_jake",
                "/usr/local/share/zsh/site-functions/_jake",
            };

            for (brew_paths) |path| {
                std.fs.cwd().deleteFile(path) catch continue;
                try writer.writeAll(color.successGreen());
                try writer.writeAll(color_mod.symbols.success);
                try writer.writeAll(color.reset());
                try writer.print(" Removed zsh completions from: {s}\n", .{path});
            }

            // Remove config block from .zshrc
            var zshrc_buf: [512]u8 = undefined;
            const zshrc_path = std.fmt.bufPrint(&zshrc_buf, "{s}/.zshrc", .{home}) catch return;

            const file = std.fs.cwd().openFile(zshrc_path, .{ .mode = .read_write }) catch return;
            defer file.close();

            const content = file.readToEndAlloc(allocator, 1024 * 1024) catch return;
            defer allocator.free(content);

            if (hasConfigBlock(content)) {
                const cleaned = try removeConfigBlock(allocator, content);
                defer allocator.free(cleaned);

                try file.seekTo(0);
                try file.writeAll(cleaned);
                try file.setEndPos(cleaned.len);

                try writer.writeAll(color.successGreen());
                try writer.writeAll(color_mod.symbols.success);
                try writer.writeAll(color.reset());
                try writer.writeAll(" Removed jake config block from ~/.zshrc\n");
            }
        },
        .fish => {
            var path_buf: [512]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "{s}/.config/fish/completions/jake.fish", .{home}) catch return;
            std.fs.cwd().deleteFile(path) catch |err| {
                if (err != error.FileNotFound) {
                    try writer.writeAll(color.warningYellow());
                    try writer.writeAll("Warning:");
                    try writer.writeAll(color.reset());
                    try writer.print(" Could not remove {s}: {s}\n", .{ path, @errorName(err) });
                }
            };
            try writer.writeAll(color.successGreen());
            try writer.writeAll(color_mod.symbols.success);
            try writer.writeAll(color.reset());
            try writer.print(" Removed fish completions from: {s}\n", .{path});
        },
    }

    try writer.writeAll("\n");
    try writer.writeAll(color.muted());
    try writer.writeAll("Uninstallation complete. Restart your shell to apply changes.\n");
    try writer.writeAll(color.reset());
}

/// Install completion script with smart environment detection
pub fn install(allocator: std.mem.Allocator, shell: Shell, writer: anytype) !void {
    const home = getHomeDir() orelse return error.NoHomeDir;
    const color = color_mod.init();

    // Generate the completion script to memory
    var script_buf: [16384]u8 = undefined;
    var script_stream = std.io.fixedBufferStream(&script_buf);
    try generate(script_stream.writer(), shell);
    const script = script_stream.getWritten();

    switch (shell) {
        .bash => {
            var path_buf: [512]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "{s}/.local/share/bash-completion/completions/jake", .{home}) catch return error.PathTooLong;

            // Create directory
            const dir_path = std.fs.path.dirname(path) orelse return error.InvalidPath;
            std.fs.cwd().makePath(dir_path) catch {};

            // Write file
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(script);

            try writer.writeAll(color.successGreen());
            try writer.writeAll(color_mod.symbols.success);
            try writer.writeAll(color.reset());
            try writer.print(" Installed bash completions to: {s}\n", .{path});
            try writer.writeAll("\n");
            try writer.writeAll(color.muted());
            try writer.writeAll("Restart your shell or run: source ");
            try writer.writeAll(path);
            try writer.writeAll("\n");
            try writer.writeAll(color.reset());
        },
        .zsh => {
            const zsh_info = try getZshInstallPath(allocator);
            defer allocator.free(zsh_info.path);

            // Create directory
            const dir_path = std.fs.path.dirname(zsh_info.path) orelse return error.InvalidPath;

            // Try to create directory and write file
            const write_result: ?anyerror = blk: {
                std.fs.cwd().makePath(dir_path) catch |err| {
                    if (err == error.AccessDenied) break :blk error.AccessDenied;
                };

                const file = std.fs.cwd().createFile(zsh_info.path, .{}) catch |err| {
                    break :blk err;
                };
                defer file.close();
                file.writeAll(script) catch |err| break :blk err;
                break :blk null;
            };

            if (write_result) |err| {
                // Failed to write to preferred location
                if (err == error.AccessDenied and zsh_info.env == .homebrew) {
                    // Homebrew path needs sudo, fall back to user directory
                    try writer.writeAll(color.warningYellow());
                    try writer.writeAll("Note:");
                    try writer.writeAll(color.reset());
                    try writer.print(" {s} requires elevated permissions.\n", .{zsh_info.path});
                    try writer.writeAll(color.muted());
                    try writer.writeAll("Falling back to user directory...\n\n");
                    try writer.writeAll(color.reset());

                    // Fall back to ~/.zsh/completions
                    var fallback_buf: [512]u8 = undefined;
                    const fallback_path = std.fmt.bufPrint(&fallback_buf, "{s}/.zsh/completions/_jake", .{home}) catch return error.PathTooLong;

                    const fallback_dir = std.fs.path.dirname(fallback_path) orelse return error.InvalidPath;
                    std.fs.cwd().makePath(fallback_dir) catch {};

                    const file = try std.fs.cwd().createFile(fallback_path, .{});
                    defer file.close();
                    try file.writeAll(script);

                    try writer.writeAll(color.successGreen());
                    try writer.writeAll(color_mod.symbols.success);
                    try writer.writeAll(color.reset());
                    try writer.print(" Installed zsh completions to: {s}\n", .{fallback_path});

                    // Patch .zshrc for vanilla install
                    if (try patchZshrc(allocator, writer)) {
                        try writer.writeAll("\n");
                        try writer.writeAll(color.muted());
                        try writer.writeAll("Modified ~/.zshrc to include completion setup.\n");
                        try writer.writeAll(color.reset());
                    }
                } else {
                    return err;
                }
            } else {
                try writer.writeAll(color.successGreen());
                try writer.writeAll(color_mod.symbols.success);
                try writer.writeAll(color.reset());
                try writer.print(" Installed zsh completions to: {s}\n", .{zsh_info.path});

                switch (zsh_info.env) {
                    .oh_my_zsh => {
                        try writer.writeAll("\n");
                        try writer.writeAll(color.muted());
                        try writer.writeAll("Oh-My-Zsh detected - completions will be loaded automatically.\n");
                        try writer.writeAll(color.reset());
                    },
                    .homebrew => {
                        try writer.writeAll("\n");
                        try writer.writeAll(color.muted());
                        try writer.writeAll("Homebrew zsh detected - completions will be loaded automatically.\n");
                        try writer.writeAll(color.reset());
                    },
                    .vanilla => {
                        // Need to patch .zshrc
                        if (try patchZshrc(allocator, writer)) {
                            try writer.writeAll("\n");
                            try writer.writeAll(color.muted());
                            try writer.writeAll("Modified ~/.zshrc to include completion setup.\n");
                            try writer.writeAll(color.reset());
                        } else {
                            try writer.writeAll("\n");
                            try writer.writeAll(color.muted());
                            try writer.writeAll("Add to your ~/.zshrc:\n");
                            try writer.writeAll("  fpath=(~/.zsh/completions $fpath)\n");
                            try writer.writeAll("  autoload -Uz compinit && compinit\n");
                            try writer.writeAll(color.reset());
                        }
                    },
                }
            }

            try writer.writeAll("\n");
            try writer.writeAll(color.muted());
            try writer.writeAll("Restart your shell to enable completions.\n");
            try writer.writeAll(color.reset());
        },
        .fish => {
            var path_buf: [512]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "{s}/.config/fish/completions/jake.fish", .{home}) catch return error.PathTooLong;

            // Create directory
            const dir_path = std.fs.path.dirname(path) orelse return error.InvalidPath;
            std.fs.cwd().makePath(dir_path) catch {};

            // Write file
            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();
            try file.writeAll(script);

            try writer.writeAll(color.successGreen());
            try writer.writeAll(color_mod.symbols.success);
            try writer.writeAll(color.reset());
            try writer.print(" Installed fish completions to: {s}\n", .{path});
            try writer.writeAll("\n");
            try writer.writeAll(color.muted());
            try writer.writeAll("Fish auto-loads completions - restart your shell to enable.\n");
            try writer.writeAll(color.reset());
        },
    }
}

// ============================================================================
// Completion Script Generators
// ============================================================================

/// Generate bash completion script
pub fn generateBash(writer: anytype) !void {
    try writer.writeAll(
        \\_jake() {
        \\    local cur prev words cword
        \\    COMPREPLY=()
        \\
        \\    # Use bash-completion helper if available
        \\    if type _get_comp_words_by_ref &>/dev/null; then
        \\        _get_comp_words_by_ref -n : cur prev words cword
        \\    else
        \\        cur="${COMP_WORDS[COMP_CWORD]}"
        \\        prev="${COMP_WORDS[COMP_CWORD-1]}"
        \\    fi
        \\
        \\    # Options that take values
        \\    case "${prev}" in
        \\        -f|--jakefile)
        \\            COMPREPLY=($(compgen -f -- "${cur}"))
        \\            return 0
        \\            ;;
        \\        -s|--show)
        \\            local recipes=$(jake --summary 2>/dev/null)
        \\            COMPREPLY=($(compgen -W "${recipes}" -- "${cur}"))
        \\            return 0
        \\            ;;
        \\        --completions)
        \\            COMPREPLY=($(compgen -W "bash zsh fish" -- "${cur}"))
        \\            return 0
        \\            ;;
        \\        -j|--jobs)
        \\            COMPREPLY=($(compgen -W "1 2 4 8 16" -- "${cur}"))
        \\            return 0
        \\            ;;
        \\    esac
        \\
        \\    # Complete flags if word starts with -
        \\    if [[ ${cur} == -* ]]; then
        \\        local opts="
    );

    // Add all flags from args.zig
    for (args_mod.flags) |flag| {
        if (flag.short) |s| {
            try writer.print("-{c} ", .{s});
        }
        try writer.print("--{s} ", .{flag.long});
    }

    try writer.writeAll(
        \\"
        \\        COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
        \\        return 0
        \\    fi
        \\
        \\    # Complete recipe names
        \\    local jakefile="Jakefile"
        \\    for ((i=1; i < ${#words[@]}; i++)); do
        \\        if [[ "${words[i]}" == "-f" || "${words[i]}" == "--jakefile" ]]; then
        \\            jakefile="${words[i+1]}"
        \\            break
        \\        fi
        \\    done
        \\
        \\    local recipes=$(jake -f "${jakefile}" --summary 2>/dev/null)
        \\    if [[ $? -eq 0 ]]; then
        \\        COMPREPLY=($(compgen -W "${recipes}" -- "${cur}"))
        \\    fi
        \\}
        \\
        \\complete -F _jake jake
        \\
    );
}

/// Generate zsh completion script
pub fn generateZsh(writer: anytype) !void {
    try writer.writeAll(
        \\#compdef jake
        \\
        \\# Jake completion script for zsh
        \\
        \\_jake() {
        \\    local curcontext="$curcontext" state line
        \\    typeset -A opt_args
        \\
        \\    _arguments -C \
        \\
    );

    // Add all flags from args.zig with descriptions
    // Zsh _arguments syntax: '(-x --long)'{-x,--long}'[desc]' where the brace
    // expansion is OUTSIDE quotes so zsh expands it to two option specs
    for (args_mod.flags) |flag| {
        if (flag.short) |s| {
            switch (flag.takes_value) {
                .none => try writer.print("        '(-{c} --{s})'{{-{c},--{s}}}'[{s}]' \\\n", .{ s, flag.long, s, flag.long, flag.desc }),
                .required => {
                    const value_name = flag.value_name orelse "VALUE";
                    try writer.print("        '(-{c} --{s})'{{-{c},--{s}}}'[{s}]:{s}:->value' \\\n", .{ s, flag.long, s, flag.long, flag.desc, value_name });
                },
                .optional => {
                    const value_name = flag.value_name orelse "VALUE";
                    try writer.print("        '(-{c} --{s})'{{-{c},--{s}}}'[{s}]::{s}:->value' \\\n", .{ s, flag.long, s, flag.long, flag.desc, value_name });
                },
            }
        } else {
            switch (flag.takes_value) {
                .none => try writer.print("        '--{s}[{s}]' \\\n", .{ flag.long, flag.desc }),
                .required => {
                    const value_name = flag.value_name orelse "VALUE";
                    try writer.print("        '--{s}[{s}]:{s}:->value' \\\n", .{ flag.long, flag.desc, value_name });
                },
                .optional => {
                    const value_name = flag.value_name orelse "VALUE";
                    try writer.print("        '--{s}[{s}]::{s}:->value' \\\n", .{ flag.long, flag.desc, value_name });
                },
            }
        }
    }

    try writer.writeAll(
        \\        '1:recipe:->recipes' \
        \\        '*:args:->args'
        \\
        \\    case $state in
        \\        recipes)
        \\            local jakefile="${opt_args[-f]:-${opt_args[--jakefile]:-Jakefile}}"
        \\            local -a recipes
        \\            recipes=(${=$(jake -f "$jakefile" --summary 2>/dev/null)})
        \\            _describe -t recipes 'recipe' recipes
        \\            ;;
        \\        value)
        \\            case $words[CURRENT-1] in
        \\                -f|--jakefile)
        \\                    _files
        \\                    ;;
        \\                -s|--show)
        \\                    local jakefile="${opt_args[-f]:-${opt_args[--jakefile]:-Jakefile}}"
        \\                    local -a recipes
        \\                    recipes=(${=$(jake -f "$jakefile" --summary 2>/dev/null)})
        \\                    _describe -t recipes 'recipe' recipes
        \\                    ;;
        \\                --completions)
        \\                    _values 'shell' bash zsh fish
        \\                    ;;
        \\            esac
        \\            ;;
        \\    esac
        \\}
        \\
        \\_jake "$@"
        \\
    );
}

/// Generate fish completion script
pub fn generateFish(writer: anytype) !void {
    try writer.writeAll(
        \\# Jake completion script for fish
        \\
        \\# Function to get recipes from jakefile
        \\function __jake_recipes
        \\    # Check for custom jakefile
        \\    set -l jakefile "Jakefile"
        \\    set -l tokens (commandline -opc)
        \\    for i in (seq (count $tokens))
        \\        if test "$tokens[$i]" = "-f" -o "$tokens[$i]" = "--jakefile"
        \\            set jakefile $tokens[(math $i + 1)]
        \\            break
        \\        end
        \\    end
        \\    jake -f "$jakefile" --summary 2>/dev/null | string split ' '
        \\end
        \\
        \\# Disable file completion by default
        \\complete -c jake -f
        \\
        \\# Complete recipes
        \\complete -c jake -a '(__jake_recipes)' -d 'Recipe'
        \\
        \\# Flag completions
        \\
    );

    // Add all flags from args.zig
    for (args_mod.flags) |flag| {
        if (flag.short) |s| {
            switch (flag.takes_value) {
                .none => try writer.print("complete -c jake -s {c} -l {s} -d '{s}'\n", .{ s, flag.long, flag.desc }),
                .required => {
                    try writer.print("complete -c jake -s {c} -l {s} -d '{s}' -r", .{ s, flag.long, flag.desc });
                    if (std.mem.eql(u8, flag.long, "jakefile")) {
                        try writer.writeAll(" -F");
                    } else if (std.mem.eql(u8, flag.long, "show")) {
                        try writer.writeAll(" -a '(__jake_recipes)'");
                    }
                    try writer.writeAll("\n");
                },
                .optional => {
                    try writer.print("complete -c jake -s {c} -l {s} -d '{s}'", .{ s, flag.long, flag.desc });
                    if (std.mem.eql(u8, flag.long, "jobs")) {
                        try writer.writeAll(" -a '1 2 4 8 16'");
                    }
                    try writer.writeAll("\n");
                },
            }
        } else {
            switch (flag.takes_value) {
                .none => try writer.print("complete -c jake -l {s} -d '{s}'\n", .{ flag.long, flag.desc }),
                .required, .optional => {
                    try writer.print("complete -c jake -l {s} -d '{s}'", .{ flag.long, flag.desc });
                    if (std.mem.eql(u8, flag.long, "completions")) {
                        try writer.writeAll(" -a 'bash zsh fish'");
                    }
                    try writer.writeAll("\n");
                },
            }
        }
    }
}

/// Generate completion script for the specified shell
pub fn generate(writer: anytype, shell: Shell) !void {
    switch (shell) {
        .bash => try generateBash(writer),
        .zsh => try generateZsh(writer),
        .fish => try generateFish(writer),
    }
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "detectShell returns null for unknown shell" {
    _ = detectShell();
}

test "Shell.fromString parses valid shells" {
    try testing.expectEqual(Shell.bash, Shell.fromString("bash").?);
    try testing.expectEqual(Shell.zsh, Shell.fromString("zsh").?);
    try testing.expectEqual(Shell.fish, Shell.fromString("fish").?);
    try testing.expect(Shell.fromString("invalid") == null);
}

test "Shell.toString returns correct string" {
    try testing.expectEqualStrings("bash", Shell.bash.toString());
    try testing.expectEqualStrings("zsh", Shell.zsh.toString());
    try testing.expectEqualStrings("fish", Shell.fish.toString());
}

test "generateBash produces valid script" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try generateBash(stream.writer());
    const output = stream.getWritten();

    try testing.expect(std.mem.indexOf(u8, output, "_jake()") != null);
    try testing.expect(std.mem.indexOf(u8, output, "complete -F _jake jake") != null);
    try testing.expect(std.mem.indexOf(u8, output, "--summary") != null);
    try testing.expect(std.mem.indexOf(u8, output, "--help") != null);
}

test "generateZsh produces valid script" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try generateZsh(stream.writer());
    const output = stream.getWritten();

    try testing.expect(std.mem.indexOf(u8, output, "#compdef jake") != null);
    try testing.expect(std.mem.indexOf(u8, output, "_jake()") != null);
    try testing.expect(std.mem.indexOf(u8, output, "--summary") != null);
}

test "generateZsh uses correct brace expansion syntax" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try generateZsh(stream.writer());
    const output = stream.getWritten();

    // Brace expansion must be outside quotes: '(-h --help)'{-h,--help}'[desc]'
    try testing.expect(std.mem.indexOf(u8, output, "'{-h,--help}'") != null);
}

test "generateFish produces valid script" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try generateFish(stream.writer());
    const output = stream.getWritten();

    try testing.expect(std.mem.indexOf(u8, output, "function __jake_recipes") != null);
    try testing.expect(std.mem.indexOf(u8, output, "complete -c jake") != null);
    try testing.expect(std.mem.indexOf(u8, output, "--summary") != null);
}

test "hasConfigBlock detects block" {
    const with_block = "some content\n" ++ CONFIG_BLOCK_START ++ "\nstuff\n" ++ CONFIG_BLOCK_END ++ "\nmore";
    const without_block = "some content\nno block here\n";

    try testing.expect(hasConfigBlock(with_block));
    try testing.expect(!hasConfigBlock(without_block));
}

test "removeConfigBlock removes block" {
    const allocator = testing.allocator;
    const content = "before\n" ++ CONFIG_BLOCK_START ++ "\nmanaged content\n" ++ CONFIG_BLOCK_END ++ "\nafter";

    const result = try removeConfigBlock(allocator, content);
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, CONFIG_BLOCK_START) == null);
    try testing.expect(std.mem.indexOf(u8, result, "before") != null);
    try testing.expect(std.mem.indexOf(u8, result, "after") != null);
}

test "detectZshEnv returns a valid value" {
    const env = detectZshEnv();
    _ = env; // Just verify it doesn't crash
}
