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
        } else if (arg[0] != '-') {
            recipe_name = arg;
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
    const jakefile = loadJakefile(allocator, jakefile_path) catch |err| {
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

    var executor = jake.Executor.init(allocator, &jakefile);
    defer executor.deinit();
    executor.dry_run = dry_run;
    executor.verbose = verbose;

    // List recipes or run default if no recipe specified
    if (list_recipes or (recipe_name == null and args.len == 1)) {
        executor.listRecipes();
        return;
    }

    // Get recipe to run
    const target = recipe_name orelse blk: {
        if (jakefile.getDefaultRecipe()) |r| {
            break :blk r.name;
        }
        getStderr().writeAll("\x1b[1;31merror:\x1b[0m No default recipe and no recipe specified\n") catch {};
        std.process.exit(1);
    };

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

fn loadJakefile(allocator: std.mem.Allocator, path: []const u8) !jake.Jakefile {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    // Note: source is kept alive as jakefile.source references it

    var lex = jake.Lexer.init(source);
    var p = jake.Parser.init(allocator, &lex);
    return p.parseJakefile();
}

fn printHelp() void {
    const help_text =
        \\jake - A modern command runner with dependency tracking
        \\
        \\USAGE:
        \\    jake [OPTIONS] [RECIPE]
        \\
        \\OPTIONS:
        \\    -h, --help       Show this help message
        \\    -V, --version    Show version
        \\    -l, --list       List available recipes
        \\    -n, --dry-run    Print commands without executing
        \\    -v, --verbose    Show verbose output
        \\    -f, --jakefile   Use specified Jakefile
        \\
        \\EXAMPLES:
        \\    jake              Run default recipe (or list if none)
        \\    jake build        Run the 'build' recipe
        \\    jake -n deploy    Dry-run the 'deploy' recipe
        \\    jake -l           List all recipes
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
    ;
    getStdout().writeAll(help_text) catch {};
}

test "main does not crash" {
    // Just ensure the module compiles
    _ = jake;
}
