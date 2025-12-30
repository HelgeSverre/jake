const std = @import("std");
const jake = @import("jake");
const compat = jake.compat;
const build_options = @import("build_options");
const args_mod = jake.args;
const completions = jake.completions;

const version = "0.3.0";

fn getStdout() std.fs.File {
    return compat.getStdOut();
}

fn getStderr() std.fs.File {
    return compat.getStdErr();
}

/// Writer wrapper compatible with Zig 0.15's File.writer() API change
/// Provides writeAll and print methods for args.zig functions
const FileWriter = struct {
    file: std.fs.File,

    pub fn writeAll(self: FileWriter, bytes: []const u8) !void {
        try self.file.writeAll(bytes);
    }

    pub fn print(self: FileWriter, comptime fmt: []const u8, args: anytype) !void {
        var buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
        try self.file.writeAll(msg);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);

    // Parse arguments using args module
    var args = args_mod.parse(allocator, raw_args) catch |err| {
        const err_arg = if (raw_args.len > 1) raw_args[1] else "";
        const stderr_writer = FileWriter{ .file = getStderr() };
        args_mod.printError(stderr_writer, err, err_arg);
        std.process.exit(1);
    };
    defer args.deinit(allocator);

    if (args.version) {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "jake {s} ({s}{s} {s} {s})\n", .{
            version,
            build_options.git_hash,
            build_options.git_dirty,
            build_options.build_date,
            build_options.optimize_mode,
        }) catch "jake " ++ version ++ "\n";
        try getStdout().writeAll(msg);
        return;
    }

    if (args.help) {
        const stdout_writer = FileWriter{ .file = getStdout() };
        args_mod.printHelp(stdout_writer);
        return;
    }

    // Handle completions (doesn't need Jakefile)
    if (args.completions_enabled or args.install_completions or args.uninstall_completions) {
        const stdout = getStdout();
        const stderr = getStderr();

        // Determine shell: explicit arg > auto-detect
        const shell = blk: {
            if (args.completions) |shell_name| {
                break :blk completions.Shell.fromString(shell_name) orelse {
                    stderr.writeAll(args_mod.ansi.err_prefix ++ "Unknown shell: ") catch {};
                    stderr.writeAll(shell_name) catch {};
                    stderr.writeAll("\nSupported shells: bash, zsh, fish\n") catch {};
                    std.process.exit(1);
                };
            }
            break :blk completions.detectShell() orelse {
                stderr.writeAll(args_mod.ansi.err_prefix ++ "Could not detect shell from $SHELL\n") catch {};
                stderr.writeAll("Specify shell explicitly: --completions bash|zsh|fish\n") catch {};
                std.process.exit(1);
            };
        };

        const stdout_writer = FileWriter{ .file = stdout };

        if (args.uninstall_completions) {
            // Uninstall completions
            completions.uninstall(allocator, shell, stdout_writer) catch |err| {
                var buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Failed to uninstall completions: {s}\n", .{@errorName(err)}) catch "error\n";
                stderr.writeAll(msg) catch {};
                std.process.exit(1);
            };
        } else if (args.install_completions) {
            // Install completions to user directory
            completions.install(allocator, shell, stdout_writer) catch |err| {
                var buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Failed to install completions: {s}\n", .{@errorName(err)}) catch "error\n";
                stderr.writeAll(msg) catch {};
                std.process.exit(1);
            };
        } else {
            // Print completion script to stdout (generate to buffer first, then write)
            var script_buf: [16384]u8 = undefined;
            var script_stream = std.io.fixedBufferStream(&script_buf);
            completions.generate(script_stream.writer(), shell) catch |err| {
                var buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Failed to generate completions: {s}\n", .{@errorName(err)}) catch "error\n";
                stderr.writeAll(msg) catch {};
                std.process.exit(1);
            };
            stdout.writeAll(script_stream.getWritten()) catch {};
        }
        return;
    }

    // Load Jakefile
    var jakefile_data = loadJakefile(allocator, args.jakefile) catch |err| {
        const stderr = getStderr();
        if (err == error.FileNotFound) {
            stderr.writeAll(args_mod.ansi.err_prefix ++ "No Jakefile found\n") catch {};
            stderr.writeAll("Create a file named 'Jakefile' in the current directory.\n") catch {};
        } else {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Failed to load Jakefile: {s}\n", .{@errorName(err)}) catch "error\n";
            stderr.writeAll(msg) catch {};
        }
        std.process.exit(1);
    };
    defer jakefile_data.deinit();

    var executor = jake.Executor.init(allocator, &jakefile_data.jakefile);
    defer executor.deinit();
    executor.dry_run = args.dry_run;
    executor.verbose = args.verbose;
    executor.watch_mode = args.watch_enabled;
    executor.auto_yes = args.yes;
    executor.jobs = args.jobs orelse 0;
    executor.setPositionalArgs(args.positional);

    // Validate required environment variables (@require directives)
    executor.validateRequiredEnv() catch |err| {
        if (err == error.MissingRequiredEnv) {
            std.process.exit(1);
        }
    };

    // List recipes or run default if no recipe specified
    if (args.list or (args.recipe == null and raw_args.len == 1)) {
        executor.listRecipes(args.short);
        return;
    }

    // Summary: space-separated recipe names for scripting/completions
    if (args.summary) {
        executor.printSummary();
        return;
    }

    // Show detailed recipe information
    if (args.show) |recipe_name| {
        if (!executor.showRecipe(recipe_name)) {
            std.process.exit(1);
        }
        return;
    }

    // Get recipe to run
    const target = args.recipe orelse blk: {
        if (jakefile_data.jakefile.getDefaultRecipe()) |r| {
            break :blk r.name;
        }
        getStderr().writeAll(args_mod.ansi.err_prefix ++ "No default recipe and no recipe specified\n") catch {};
        std.process.exit(1);
    };

    // Watch mode
    if (args.watch_enabled) {
        var watcher = jake.Watcher.init(allocator, &jakefile_data.jakefile);
        defer watcher.deinit();
        watcher.dry_run = args.dry_run;
        watcher.verbose = args.verbose;

        // Add explicit watch pattern from CLI if provided
        if (args.watch) |pattern| {
            watcher.addPattern(pattern) catch {};
        } else {
            // If no explicit pattern, watch the Jakefile and recipe dependencies
            watcher.addPattern(args.jakefile) catch {};
            watcher.addRecipeDeps(target) catch {};
        }

        watcher.watch(target) catch |err| {
            const stderr = getStderr();
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Watch failed: {s}\n", .{@errorName(err)}) catch "error\n";
            stderr.writeAll(msg) catch {};
            std.process.exit(1);
        };
        return;
    }

    // Execute
    executor.execute(target) catch |err| {
        const stderr = getStderr();
        var buf: [512]u8 = undefined;

        switch (err) {
            error.RecipeNotFound => {
                // Try to find similar recipe names
                const suggestions = jake.suggest.findSimilarRecipes(
                    allocator,
                    target,
                    jakefile_data.jakefile.recipes,
                    3, // max distance threshold
                ) catch &.{};
                defer if (suggestions.len > 0) allocator.free(suggestions);

                if (suggestions.len > 0) {
                    var suggest_buf: [128]u8 = undefined;
                    const suggest_str = jake.suggest.formatSuggestion(&suggest_buf, suggestions);
                    const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Recipe '{s}' not found\n{s}", .{ target, suggest_str }) catch "error\n";
                    stderr.writeAll(msg) catch {};
                } else {
                    const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Recipe '{s}' not found\nRun 'jake --list' to see available recipes.\n", .{target}) catch "error\n";
                    stderr.writeAll(msg) catch {};
                }
            },
            error.CyclicDependency => {
                const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Cyclic dependency detected in '{s}'\n", .{target}) catch "error\n";
                stderr.writeAll(msg) catch {};
            },
            error.CommandFailed => {
                const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Recipe '{s}' failed\n", .{target}) catch "error\n";
                stderr.writeAll(msg) catch {};
            },
            else => {
                const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "{s}\n", .{@errorName(err)}) catch "error\n";
                stderr.writeAll(msg) catch {};
            },
        }
        std.process.exit(1);
    };
}

const JakefileWithSource = struct {
    jakefile: jake.Jakefile,
    source: []const u8,
    allocator: std.mem.Allocator,
    import_allocations: ?jake.ImportAllocations,

    pub fn deinit(self: *JakefileWithSource) void {
        self.jakefile.deinit(self.allocator);
        self.allocator.free(self.source);
        if (self.import_allocations) |*allocs| {
            var mutable_allocs = allocs.*;
            mutable_allocs.deinit();
        }
    }
};

fn loadJakefile(allocator: std.mem.Allocator, path: []const u8) !JakefileWithSource {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    errdefer allocator.free(source);

    var lex = jake.Lexer.init(source);
    var p = jake.Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();

    // Process imports if any
    var import_allocations: ?jake.ImportAllocations = null;
    if (jakefile.imports.len > 0) {
        import_allocations = jake.resolveImports(allocator, &jakefile, path) catch |err| {
            const stderr = getStderr();
            var buf: [512]u8 = undefined;
            const msg = switch (err) {
                error.CircularImport => "Circular import detected",
                error.FileNotFound => "Imported file not found",
                error.ParseError => "Failed to parse imported file",
                else => @errorName(err),
            };
            const err_msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Import failed: {s}\n", .{msg}) catch "error\n";
            stderr.writeAll(err_msg) catch {};
            return error.ImportFailed;
        };
    }

    return JakefileWithSource{
        .jakefile = jakefile,
        .source = source,
        .allocator = allocator,
        .import_allocations = import_allocations,
    };
}

test "main does not crash" {
    // Just ensure the module compiles
    _ = jake;
}
