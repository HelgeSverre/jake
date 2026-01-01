const std = @import("std");
const jake = @import("jake");
const compat = jake.compat;
const build_options = @import("build_options");
const args_mod = jake.args;
const completions = jake.completions;
const upgrade = jake.upgrade;
const init = jake.init;
const color_mod = jake.color;

const version = build_options.version;

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

    // Check for subcommands before parsing (they don't follow flag patterns)
    if (raw_args.len > 1 and std.mem.eql(u8, raw_args[1], "upgrade")) {
        return handleUpgrade(allocator, raw_args[2..]);
    }
    if (raw_args.len > 1 and std.mem.eql(u8, raw_args[1], "init")) {
        return handleInit(allocator, raw_args[2..]);
    }

    // Parse arguments using args module
    var args = args_mod.parse(allocator, raw_args) catch |err| {
        const err_arg = if (raw_args.len > 1) raw_args[1] else "";
        const stderr_writer = FileWriter{ .file = getStderr() };
        args_mod.printError(stderr_writer, err, err_arg);
        std.process.exit(1);
    };
    defer args.deinit(allocator);

    if (args.version) {
        const stdout = getStdout();
        const color = color_mod.init();
        // v4 format: {j} jake 0.x.x
        // {j} in Jake Rose (#f43f5e), version in muted gray (#71717a)
        stdout.writeAll(if (color.enabled) color_mod.codes.jake_rose else "") catch {};
        stdout.writeAll(color_mod.symbols.logo) catch {};
        stdout.writeAll(if (color.enabled) color_mod.codes.reset else "") catch {};
        stdout.writeAll(" jake ") catch {};
        stdout.writeAll(if (color.enabled) color_mod.codes.muted_gray else "") catch {};
        stdout.writeAll(version) catch {};
        stdout.writeAll(if (color.enabled) color_mod.codes.reset else "") catch {};
        stdout.writeAll("\n") catch {};
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

    // Handle formatter (reads Jakefile directly, doesn't need executor)
    if (args.fmt or args.dump) {
        const formatter = jake.formatter;
        const stderr = getStderr();

        const result = formatter.formatFile(allocator, args.jakefile, args.check or args.dump) catch |err| {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Format failed: {s}\n", .{@errorName(err)}) catch "error\n";
            stderr.writeAll(msg) catch {};
            std.process.exit(1);
        };
        defer allocator.free(result.output);

        const stdout = getStdout();

        if (args.dump) {
            // Output formatted Jakefile to stdout
            stdout.writeAll(result.output) catch {};
        } else if (args.check) {
            // Check mode: exit 1 if changes needed
            if (result.changed) {
                stderr.writeAll(args.jakefile) catch {};
                stderr.writeAll(" needs formatting\n") catch {};
                std.process.exit(1);
            } else {
                stdout.writeAll(args.jakefile) catch {};
                stdout.writeAll(" is correctly formatted\n") catch {};
            }
        } else {
            // Format in-place
            if (result.changed) {
                // Write the formatted output
                std.fs.cwd().writeFile(.{ .sub_path = args.jakefile, .data = result.output }) catch |err| {
                    var buf: [256]u8 = undefined;
                    const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Failed to write: {s}\n", .{@errorName(err)}) catch "error\n";
                    stderr.writeAll(msg) catch {};
                    std.process.exit(1);
                };
                stdout.writeAll("Formatted ") catch {};
                stdout.writeAll(args.jakefile) catch {};
                stdout.writeAll("\n") catch {};
            }
        }
        return;
    }

    // Load Jakefile
    var jakefile_data = loadJakefile(allocator, args.jakefile) catch |err| {
        const stderr = getStderr();
        const color = color_mod.init();
        if (err == error.FileNotFound) {
            // v4 format: {j} error: no Jakefile found (logo only for this error type)
            stderr.writeAll(if (color.enabled) color_mod.codes.jake_rose else "") catch {};
            stderr.writeAll(color_mod.symbols.logo) catch {};
            stderr.writeAll(if (color.enabled) color_mod.codes.reset else "") catch {};
            stderr.writeAll(" " ++ args_mod.ansi.err_prefix ++ "no Jakefile found\n") catch {};
            stderr.writeAll("\n   ") catch {};
            stderr.writeAll(if (color.enabled) color_mod.codes.muted_gray else "") catch {};
            stderr.writeAll("Searched: Jakefile, jakefile, Jakefile.jake") catch {};
            stderr.writeAll(if (color.enabled) color_mod.codes.reset else "") catch {};
            stderr.writeAll("\n   ") catch {};
            stderr.writeAll(if (color.enabled) color_mod.codes.info_blue else "") catch {};
            stderr.writeAll("hint:") catch {};
            stderr.writeAll(if (color.enabled) color_mod.codes.reset else "") catch {};
            stderr.writeAll(" run ") catch {};
            stderr.writeAll(if (color.enabled) color_mod.codes.jake_rose else "") catch {};
            stderr.writeAll("jake init") catch {};
            stderr.writeAll(if (color.enabled) color_mod.codes.reset else "") catch {};
            stderr.writeAll(" to create one\n") catch {};
        } else {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Failed to load Jakefile: {s}\n", .{@errorName(err)}) catch "error\n";
            stderr.writeAll(msg) catch {};
        }
        std.process.exit(1);
    };
    defer jakefile_data.deinit();

    var executor = jake.Executor.initWithIndexAndContext(allocator, &jakefile_data.jakefile, &jakefile_data.index, &jakefile_data.runtime);
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
    // --short implies listing (it's a listing format option)
    if (args.list or args.short or (args.recipe == null and raw_args.len == 1)) {
        executor.listRecipes(args.short, args.all);
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
        if (jakefile_data.index.getDefaultRecipe()) |r| {
            break :blk r.name;
        }
        getStderr().writeAll(args_mod.ansi.err_prefix ++ "No default recipe and no recipe specified\n") catch {};
        std.process.exit(1);
    };

    // Watch mode
    if (args.watch_enabled) {
        var watcher = jake.Watcher.initWithIndexAndContext(allocator, &jakefile_data.jakefile, &jakefile_data.index, &jakefile_data.runtime);
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
                // v4 format: error: recipe 'X' not found
                const color = color_mod.init();
                stderr.writeAll(args_mod.ansi.err_prefix) catch {};
                stderr.writeAll("recipe '") catch {};
                stderr.writeAll(target) catch {};
                stderr.writeAll("' not found\n") catch {};

                // Try to find similar recipe names for "did you mean:" suggestion
                const suggestions = jake.suggest.findSimilarRecipes(
                    allocator,
                    target,
                    jakefile_data.jakefile.recipes,
                    3, // max distance threshold
                ) catch &.{};
                defer if (suggestions.len > 0) allocator.free(suggestions);

                if (suggestions.len > 0) {
                    // v4 format: "   did you mean: build" with recipe in Rose
                    stderr.writeAll("\n   ") catch {};
                    stderr.writeAll(if (color.enabled) color_mod.codes.muted_gray else "") catch {};
                    stderr.writeAll("did you mean:") catch {};
                    stderr.writeAll(if (color.enabled) color_mod.codes.reset else "") catch {};
                    stderr.writeAll(" ") catch {};
                    stderr.writeAll(if (color.enabled) color_mod.codes.jake_rose else "") catch {};
                    stderr.writeAll(suggestions[0]) catch {};
                    stderr.writeAll(if (color.enabled) color_mod.codes.reset else "") catch {};
                    stderr.writeAll("\n") catch {};
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
    index: jake.JakefileIndex,
    runtime: jake.RuntimeContext,
    source: []const u8,
    allocator: std.mem.Allocator,
    import_allocations: ?jake.ImportAllocations,

    pub fn deinit(self: *JakefileWithSource) void {
        self.runtime.deinit();
        self.index.deinit();
        self.jakefile.deinit(self.allocator);
        self.allocator.free(self.source);
        if (self.import_allocations) |*allocs| {
            var mutable_allocs = allocs.*;
            mutable_allocs.deinit();
        }
    }
};

/// Searches for a Jakefile starting from the current directory and traversing up
/// to parent directories. Returns the path to the found Jakefile.
/// Only traverses if the path is the default "Jakefile" - explicit paths are used as-is.
fn findJakefile(allocator: std.mem.Allocator, requested_path: []const u8) !struct { path: []const u8, dir: ?[]const u8 } {
    // If user specified an explicit path (not just "Jakefile"), use it directly
    if (!std.mem.eql(u8, requested_path, "Jakefile")) {
        return .{ .path = requested_path, .dir = null };
    }

    // Try current directory first
    if (std.fs.cwd().openFile("Jakefile", .{})) |file| {
        file.close();
        return .{ .path = "Jakefile", .dir = null };
    } else |_| {}

    // Get absolute path to current directory
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &path_buf) catch return error.FileNotFound;

    // Use a separate buffer for the current directory we're checking
    var current_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(current_buf[0..cwd.len], cwd);
    var current_dir: []const u8 = current_buf[0..cwd.len];

    // Traverse up the directory tree
    while (true) {
        // Get parent directory
        const parent = std.fs.path.dirname(current_dir) orelse break;
        if (parent.len == 0 or std.mem.eql(u8, parent, current_dir)) break;

        // Try to open Jakefile in parent
        var parent_buf: [std.fs.max_path_bytes]u8 = undefined;
        const jakefile_path = std.fmt.bufPrint(&parent_buf, "{s}/Jakefile", .{parent}) catch break;

        if (std.fs.cwd().openFile(jakefile_path, .{})) |file| {
            file.close();
            // Found it - return the path and the directory to change to
            const path_copy = allocator.dupe(u8, jakefile_path) catch return error.OutOfMemory;
            const dir_copy = allocator.dupe(u8, parent) catch {
                allocator.free(path_copy);
                return error.OutOfMemory;
            };
            return .{ .path = path_copy, .dir = dir_copy };
        } else |_| {}

        // parent is already a prefix slice of current_buf, just update the length
        current_dir = current_buf[0..parent.len];
    }

    return error.FileNotFound;
}

fn loadJakefile(allocator: std.mem.Allocator, path: []const u8) !JakefileWithSource {
    // Find the Jakefile, potentially traversing up directories
    const found = try findJakefile(allocator, path);
    defer if (found.dir) |dir| allocator.free(dir);
    const jakefile_path = found.path;
    defer if (found.dir != null) allocator.free(jakefile_path);

    // Change to the Jakefile's directory if we found it in a parent
    if (found.dir) |dir| {
        std.posix.chdir(dir) catch |err| {
            const stderr = getStderr();
            var buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Failed to change to directory '{s}': {s}\n", .{ dir, @errorName(err) }) catch "error\n";
            stderr.writeAll(msg) catch {};
            return error.FileNotFound;
        };
    }

    // Now open using just the filename since we've changed directory
    const actual_path = if (found.dir != null) "Jakefile" else jakefile_path;
    const file = try std.fs.cwd().openFile(actual_path, .{});
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

    var index = try jake.JakefileIndex.build(allocator, &jakefile);
    errdefer index.deinit();

    var runtime = jake.RuntimeContext.init(allocator);
    errdefer runtime.deinit();
    runtime.configure(&jakefile, &index);

    return JakefileWithSource{
        .jakefile = jakefile,
        .index = index,
        .runtime = runtime,
        .source = source,
        .allocator = allocator,
        .import_allocations = import_allocations,
    };
}

/// Handle the `jake upgrade` subcommand
fn handleUpgrade(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var options = upgrade.Options{};

    // Parse upgrade-specific flags
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--check")) {
            options.check_only = true;
        } else if (std.mem.eql(u8, arg, "--no-verify")) {
            options.skip_verify = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUpgradeHelp();
            return;
        } else if (arg.len > 0 and arg[0] == '-') {
            const stderr = getStderr();
            stderr.writeAll(args_mod.ansi.err_prefix ++ "Unknown option: ") catch {};
            stderr.writeAll(arg) catch {};
            stderr.writeAll("\n") catch {};
            printUpgradeHelp();
            std.process.exit(1);
        }
    }

    const stdout_writer = FileWriter{ .file = getStdout() };
    const stderr = getStderr();

    upgrade.run(allocator, version, options, stdout_writer) catch |err| {
        switch (err) {
            error.AlreadyLatest => {
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "jake {s} is already the latest version.\n", .{version}) catch "Already up to date.\n";
                stdout_writer.writeAll(msg) catch {};
                return;
            },
            error.NetworkError => {
                stderr.writeAll(args_mod.ansi.err_prefix ++ "Network error - check your connection\n") catch {};
            },
            error.HttpError => {
                stderr.writeAll(args_mod.ansi.err_prefix ++ "Failed to reach GitHub\n") catch {};
            },
            error.ChecksumMismatch => {
                stderr.writeAll(args_mod.ansi.err_prefix ++ "Checksum verification failed\n") catch {};
                stderr.writeAll("Use --no-verify to skip (not recommended)\n") catch {};
            },
            error.PermissionDenied => {
                stderr.writeAll(args_mod.ansi.err_prefix ++ "Permission denied - try running with elevated privileges\n") catch {};
            },
            error.NoReleaseFound => {
                stderr.writeAll(args_mod.ansi.err_prefix ++ "No release found for your platform\n") catch {};
            },
            else => {
                var buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Upgrade failed: {s}\n", .{@errorName(err)}) catch "error\n";
                stderr.writeAll(msg) catch {};
            },
        }
        std.process.exit(1);
    };
}

fn printUpgradeHelp() void {
    const stdout = getStdout();
    stdout.writeAll(
        \\jake upgrade - Update jake to the latest version
        \\
        \\USAGE:
        \\    jake upgrade [OPTIONS]
        \\
        \\OPTIONS:
        \\    --check       Check for updates without installing
        \\    --no-verify   Skip SHA256 checksum verification
        \\    -v, --verbose Show verbose output
        \\    -h, --help    Show this help message
        \\
        \\EXAMPLES:
        \\    jake upgrade           Download and install latest version
        \\    jake upgrade --check   Check if update is available
        \\
    ) catch {};
}

/// Handle the `jake init` subcommand
fn handleInit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var options = init.Options{};

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--force")) {
            options.force = true;
        } else if ((std.mem.startsWith(u8, arg, "-t") or std.mem.startsWith(u8, arg, "--template"))) {
            const value = if (std.mem.startsWith(u8, arg, "-t")) arg[2..] else std.mem.trimLeft(u8, arg[10..], " =");
            if (std.mem.eql(u8, value, "blank")) {
                options.template = .blank;
            } else if (std.mem.eql(u8, value, "starter")) {
                options.template = .starter;
            } else {
                const stderr = getStderr();
                stderr.writeAll(args_mod.ansi.err_prefix ++ "Unknown template: ") catch {};
                stderr.writeAll(value) catch {};
                stderr.writeAll("\nAvailable templates: starter, blank\n") catch {};
                printInitHelp();
                std.process.exit(1);
            }
        } else if (std.mem.startsWith(u8, arg, "-p") or std.mem.startsWith(u8, arg, "--path")) {
            const value = if (std.mem.startsWith(u8, arg, "-p")) arg[2..] else std.mem.trimLeft(u8, arg[6..], " =");
            if (value.len == 0) {
                const stderr = getStderr();
                stderr.writeAll(args_mod.ansi.err_prefix ++ "Missing value for --path\n") catch {};
                printInitHelp();
                std.process.exit(1);
            }
            options.path = value;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printInitHelp();
            return;
        } else if (arg.len > 0 and arg[0] == '-') {
            const stderr = getStderr();
            stderr.writeAll(args_mod.ansi.err_prefix ++ "Unknown option: ") catch {};
            stderr.writeAll(arg) catch {};
            stderr.writeAll("\n") catch {};
            printInitHelp();
            std.process.exit(1);
        } else {
            const stderr = getStderr();
            stderr.writeAll(args_mod.ansi.err_prefix ++ "Unexpected argument: ") catch {};
            stderr.writeAll(arg) catch {};
            stderr.writeAll("\n") catch {};
            printInitHelp();
            std.process.exit(1);
        }
    }

    const stdout_writer = FileWriter{ .file = getStdout() };
    const stderr = getStderr();

    init.run(allocator, options, stdout_writer) catch |err| {
        switch (err) {
            error.FileExists => {
                stderr.writeAll(args_mod.ansi.err_prefix ++ "Jakefile already exists\n") catch {};
                stderr.writeAll("Use --force to overwrite.\n") catch {};
            },
            else => {
                var buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, args_mod.ansi.err_prefix ++ "Init failed: {s}\n", .{@errorName(err)}) catch "error\n";
                stderr.writeAll(msg) catch {};
            },
        }
        std.process.exit(1);
    };
}

fn printInitHelp() void {
    const stdout = getStdout();
    init.printHelp(stdout) catch {};
}

test "main does not crash" {
    // Just ensure the module compiles
    _ = jake;
}
