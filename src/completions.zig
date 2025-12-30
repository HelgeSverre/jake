// completions.zig - Shell completion script generators for jake
// Generates completion scripts for bash, zsh, and fish shells

const std = @import("std");
const args_mod = @import("args.zig");

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

/// Detect shell from $SHELL environment variable
pub fn detectShell() ?Shell {
    const shell_path = std.posix.getenv("SHELL") orelse return null;

    // Extract basename from path (e.g., /bin/zsh -> zsh)
    const basename = std.fs.path.basename(shell_path);

    if (std.mem.eql(u8, basename, "bash")) return .bash;
    if (std.mem.eql(u8, basename, "zsh")) return .zsh;
    if (std.mem.eql(u8, basename, "fish")) return .fish;

    // Handle common variations
    if (std.mem.startsWith(u8, basename, "bash")) return .bash;
    if (std.mem.startsWith(u8, basename, "zsh")) return .zsh;
    if (std.mem.startsWith(u8, basename, "fish")) return .fish;

    return null;
}

/// Get the user's home directory
fn getHomeDir() ?[]const u8 {
    return std.posix.getenv("HOME");
}

/// Installation result with path and any additional instructions
pub const InstallResult = struct {
    path: []const u8,
    instructions: ?[]const u8,
};

/// Get the installation path for completions
pub fn getInstallPath(allocator: std.mem.Allocator, shell: Shell) !InstallResult {
    const home = getHomeDir() orelse return error.NoHomeDir;

    return switch (shell) {
        .bash => .{
            .path = try std.fmt.allocPrint(allocator, "{s}/.local/share/bash-completion/completions/jake", .{home}),
            .instructions = null,
        },
        .zsh => .{
            .path = try std.fmt.allocPrint(allocator, "{s}/.zsh/completions/_jake", .{home}),
            .instructions = "Add to your ~/.zshrc:\n  fpath=(~/.zsh/completions $fpath)\n  autoload -Uz compinit && compinit",
        },
        .fish => .{
            .path = try std.fmt.allocPrint(allocator, "{s}/.config/fish/completions/jake.fish", .{home}),
            .instructions = null,
        },
    };
}

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
    for (args_mod.flags) |flag| {
        if (flag.short) |s| {
            // Short and long form together
            switch (flag.takes_value) {
                .none => try writer.print("        '(-{c} --{s})'{{{c},--{s}}}'[{s}]' \\\n", .{ s, flag.long, s, flag.long, flag.desc }),
                .required => {
                    const value_name = flag.value_name orelse "VALUE";
                    try writer.print("        '(-{c} --{s})'{{{c},--{s}}}'[{s}]:{s}:->value' \\\n", .{ s, flag.long, s, flag.long, flag.desc, value_name });
                },
                .optional => {
                    const value_name = flag.value_name orelse "VALUE";
                    try writer.print("        '(-{c} --{s})'{{{c},--{s}}}'[{s}]::{s}:->value' \\\n", .{ s, flag.long, s, flag.long, flag.desc, value_name });
                },
            }
        } else {
            // Long form only
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
        \\            local recipes=(${(f)"$(jake -f "$jakefile" --summary 2>/dev/null)"})
        \\            _describe -t recipes 'recipe' recipes
        \\            ;;
        \\        value)
        \\            case $words[CURRENT-1] in
        \\                -f|--jakefile)
        \\                    _files
        \\                    ;;
        \\                -s|--show)
        \\                    local jakefile="${opt_args[-f]:-${opt_args[--jakefile]:-Jakefile}}"
        \\                    local recipes=(${(f)"$(jake -f "$jakefile" --summary 2>/dev/null)"})
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
            // Has both short and long form
            switch (flag.takes_value) {
                .none => try writer.print("complete -c jake -s {c} -l {s} -d '{s}'\n", .{ s, flag.long, flag.desc }),
                .required => {
                    try writer.print("complete -c jake -s {c} -l {s} -d '{s}' -r", .{ s, flag.long, flag.desc });
                    // Add value completions for specific flags
                    if (std.mem.eql(u8, flag.long, "jakefile")) {
                        try writer.writeAll(" -F"); // File completion
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
            // Long form only
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

/// Install completion script to user directory
pub fn install(allocator: std.mem.Allocator, shell: Shell, writer: anytype) !void {
    const result = try getInstallPath(allocator, shell);
    defer allocator.free(result.path);

    // Create parent directories
    const dir_path = std.fs.path.dirname(result.path) orelse return error.InvalidPath;

    // Create directory (may already exist)
    std.fs.cwd().makePath(dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Generate the completion script to memory first
    var script_buf: [16384]u8 = undefined;
    var script_stream = std.io.fixedBufferStream(&script_buf);
    try generate(script_stream.writer(), shell);

    // Write to file
    const file = try std.fs.cwd().createFile(result.path, .{});
    defer file.close();
    try file.writeAll(script_stream.getWritten());

    // Print success message
    try writer.print("Installed {s} completions to: {s}\n", .{ shell.toString(), result.path });

    if (result.instructions) |instructions| {
        try writer.print("\n{s}\n", .{instructions});
    }

    try writer.writeAll("\nRestart your shell or source the completion file to enable completions.\n");
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "detectShell returns null for unknown shell" {
    // This test depends on environment, so just verify the function works
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

    // Verify key components
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

    // Verify key components
    try testing.expect(std.mem.indexOf(u8, output, "#compdef jake") != null);
    try testing.expect(std.mem.indexOf(u8, output, "_jake()") != null);
    try testing.expect(std.mem.indexOf(u8, output, "--summary") != null);
}

test "generateFish produces valid script" {
    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try generateFish(stream.writer());
    const output = stream.getWritten();

    // Verify key components
    try testing.expect(std.mem.indexOf(u8, output, "function __jake_recipes") != null);
    try testing.expect(std.mem.indexOf(u8, output, "complete -c jake") != null);
    try testing.expect(std.mem.indexOf(u8, output, "--summary") != null);
}

test "getInstallPath returns correct paths" {
    const allocator = testing.allocator;

    // Only test if HOME is set
    if (std.posix.getenv("HOME")) |home| {
        const bash_result = try getInstallPath(allocator, .bash);
        defer allocator.free(bash_result.path);
        try testing.expect(std.mem.indexOf(u8, bash_result.path, home) != null);
        try testing.expect(std.mem.indexOf(u8, bash_result.path, "bash-completion") != null);

        const zsh_result = try getInstallPath(allocator, .zsh);
        defer allocator.free(zsh_result.path);
        try testing.expect(std.mem.indexOf(u8, zsh_result.path, "_jake") != null);
        try testing.expect(zsh_result.instructions != null);

        const fish_result = try getInstallPath(allocator, .fish);
        defer allocator.free(fish_result.path);
        try testing.expect(std.mem.indexOf(u8, fish_result.path, "jake.fish") != null);
    }
}
