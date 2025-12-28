// Jake - A modern command runner with dependency tracking
// The best of Make and Just combined

const std = @import("std");
const jake = @import("jake");

const version = "0.1.0";

fn getStdout() std.fs.File {
    return std.fs.File.stdout();
}

fn getStderr() std.fs.File {
    return std.fs.File.stderr();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var recipe_name: ?[]const u8 = null;
    var jakefile_path: []const u8 = "Jakefile";
    var dry_run = false;
    var verbose = false;
    var list_recipes = false;
    var show_help = false;
    var show_version = false;
    var watch_mode = false;
    var jobs: usize = 0; // 0 = sequential (default), N = parallel with N threads
    var watch_patterns: std.ArrayListUnmanaged([]const u8) = .empty;
    defer watch_patterns.deinit(allocator);
    var positional_args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer positional_args.deinit(allocator);

    // Parse arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) {
            show_version = true;
        } else if (std.mem.eql(u8, arg, "--list") or std.mem.eql(u8, arg, "-l")) {
            list_recipes = true;
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--jakefile")) {
            i += 1;
            if (i < args.len) {
                jakefile_path = args[i];
            }
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--watch")) {
            watch_mode = true;
            // Check if next arg is a watch pattern (doesn't start with -)
            if (i + 1 < args.len and args[i + 1][0] != '-') {
                i += 1;
                try watch_patterns.append(allocator, args[i]);
            }
        } else if (std.mem.eql(u8, arg, "-j") or std.mem.eql(u8, arg, "--jobs")) {
            // -j or --jobs: check for next argument
            if (i + 1 < args.len and args[i + 1][0] != '-') {
                i += 1;
                jobs = std.fmt.parseInt(usize, args[i], 10) catch {
                    getStderr().writeAll("\x1b[1;31merror:\x1b[0m Invalid value for --jobs\n") catch {};
                    std.process.exit(1);
                };
            } else {
                // -j without argument: use CPU count
                jobs = std.Thread.getCpuCount() catch 4;
            }
        } else if (std.mem.startsWith(u8, arg, "-j")) {
            // Handle -jN format (e.g., -j4)
            const num_str = arg[2..];
            if (num_str.len > 0) {
                jobs = std.fmt.parseInt(usize, num_str, 10) catch {
                    getStderr().writeAll("\x1b[1;31merror:\x1b[0m Invalid value for -j\n") catch {};
                    std.process.exit(1);
                };
            } else {
                jobs = std.Thread.getCpuCount() catch 4;
            }
        } else if (arg[0] != '-') {
            if (recipe_name == null) {
                recipe_name = arg;
            } else {
                // After recipe name, collect as positional args
                try positional_args.append(allocator, arg);
            }
        }
    }

    if (show_version) {
        try getStdout().writeAll("jake " ++ version ++ "\n");
        return;
    }

    if (show_help) {
        printHelp();
        return;
    }

    // Load Jakefile
    var jakefile_data = loadJakefile(allocator, jakefile_path) catch |err| {
        const stderr = getStderr();
        if (err == error.FileNotFound) {
            stderr.writeAll("\x1b[1;31merror:\x1b[0m No Jakefile found\n") catch {};
            stderr.writeAll("Create a file named 'Jakefile' in the current directory.\n") catch {};
        } else {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "\x1b[1;31merror:\x1b[0m Failed to load Jakefile: {s}\n", .{@errorName(err)}) catch "error\n";
            stderr.writeAll(msg) catch {};
        }
        std.process.exit(1);
    };
    defer jakefile_data.deinit();

    var executor = jake.Executor.init(allocator, &jakefile_data.jakefile);
    defer executor.deinit();
    executor.dry_run = dry_run;
    executor.verbose = verbose;
    executor.jobs = jobs;
    executor.setPositionalArgs(positional_args.items);

    // List recipes or run default if no recipe specified
    if (list_recipes or (recipe_name == null and args.len == 1)) {
        executor.listRecipes();
        return;
    }

    // Get recipe to run
    const target = recipe_name orelse blk: {
        if (jakefile_data.jakefile.getDefaultRecipe()) |r| {
            break :blk r.name;
        }
        getStderr().writeAll("\x1b[1;31merror:\x1b[0m No default recipe and no recipe specified\n") catch {};
        std.process.exit(1);
    };

    // Watch mode
    if (watch_mode) {
        var watcher = jake.Watcher.init(allocator, &jakefile_data.jakefile);
        defer watcher.deinit();
        watcher.dry_run = dry_run;
        watcher.verbose = verbose;

        // Add explicit watch patterns from CLI
        for (watch_patterns.items) |pattern| {
            watcher.addPattern(pattern) catch {};
        }

        // If no explicit patterns, watch the Jakefile and recipe dependencies
        if (watch_patterns.items.len == 0) {
            watcher.addPattern(jakefile_path) catch {};
            watcher.addRecipeDeps(target) catch {};
        }

        watcher.watch(target) catch |err| {
            const stderr = getStderr();
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "\x1b[1;31merror:\x1b[0m Watch failed: {s}\n", .{@errorName(err)}) catch "error\n";
            stderr.writeAll(msg) catch {};
            std.process.exit(1);
        };
        return;
    }

    // Execute
    executor.execute(target) catch |err| {
        const stderr = getStderr();
        var buf: [512]u8 = undefined;
        const msg = switch (err) {
            error.RecipeNotFound => std.fmt.bufPrint(&buf, "\x1b[1;31merror:\x1b[0m Recipe '{s}' not found\nRun 'jake --list' to see available recipes.\n", .{target}) catch "error\n",
            error.CyclicDependency => std.fmt.bufPrint(&buf, "\x1b[1;31merror:\x1b[0m Cyclic dependency detected in '{s}'\n", .{target}) catch "error\n",
            error.CommandFailed => std.fmt.bufPrint(&buf, "\x1b[1;31merror:\x1b[0m Recipe '{s}' failed\n", .{target}) catch "error\n",
            else => std.fmt.bufPrint(&buf, "\x1b[1;31merror:\x1b[0m {s}\n", .{@errorName(err)}) catch "error\n",
        };
        stderr.writeAll(msg) catch {};
        std.process.exit(1);
    };
}

const JakefileWithSource = struct {
    jakefile: jake.Jakefile,
    source: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *JakefileWithSource) void {
        self.jakefile.deinit(self.allocator);
        self.allocator.free(self.source);
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
    if (jakefile.imports.len > 0) {
        jake.resolveImports(allocator, &jakefile, path) catch |err| {
            const stderr = getStderr();
            var buf: [512]u8 = undefined;
            const msg = switch (err) {
                error.CircularImport => "Circular import detected",
                error.FileNotFound => "Imported file not found",
                error.ParseError => "Failed to parse imported file",
                else => @errorName(err),
            };
            const err_msg = std.fmt.bufPrint(&buf, "\x1b[1;31merror:\x1b[0m Import failed: {s}\n", .{msg}) catch "error\n";
            stderr.writeAll(err_msg) catch {};
            return error.ImportFailed;
        };
    }

    return JakefileWithSource{
        .jakefile = jakefile,
        .source = source,
        .allocator = allocator,
    };
}

fn printHelp() void {
    const help_text =
        \\jake - A modern command runner with dependency tracking
        \\
        \\USAGE:
        \\    jake [OPTIONS] [RECIPE]
        \\
        \\OPTIONS:
        \\    -h, --help         Show this help message
        \\    -V, --version      Show version
        \\    -l, --list         List available recipes
        \\    -n, --dry-run      Print commands without executing
        \\    -v, --verbose      Show verbose output
        \\    -f, --jakefile     Use specified Jakefile
        \\    -w, --watch [PAT]  Watch files and re-run on changes
        \\                       Optional: specify glob pattern to watch
        \\    -j, --jobs [N]     Run N recipes in parallel (default: CPU count)
        \\                       Use -jN or --jobs N to specify thread count
        \\
        \\EXAMPLES:
        \\    jake                    Run default recipe (or list if none)
        \\    jake build              Run the 'build' recipe
        \\    jake -n deploy          Dry-run the 'deploy' recipe
        \\    jake -l                 List all recipes
        \\    jake -w build           Watch and re-run 'build' on changes
        \\    jake -w "src/**" build  Watch src/ and re-run 'build'
        \\    jake -j4 build          Run 'build' with 4 parallel jobs
        \\    jake -j build           Run 'build' with CPU count parallel jobs
        \\
        \\JAKEFILE SYNTAX:
        \\    # Variables
        \\    name = "value"
        \\
        \\    # Task recipe (always runs)
        \\    task build:
        \\        echo "building..."
        \\
        \\    # File recipe (only runs if output is stale)
        \\    file dist/app.js: src/**/*.ts
        \\        esbuild src/index.ts --outfile=dist/app.js
        \\
        \\    # Recipe with dependencies
        \\    deploy: [build, test]
        \\        rsync dist/ server:/var/www/
        \\
        \\    # Import from other Jakefiles
        \\    @import "scripts/docker.jake"           # import all recipes
        \\    @import "scripts/deploy.jake" as deploy # import with prefix
        \\                                            # use as: deploy.production
        \\
    ;
    getStdout().writeAll(help_text) catch {};
}

test "main does not crash" {
    // Just ensure the module compiles
    _ = jake;
}
