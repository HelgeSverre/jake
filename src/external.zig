//! External Build System Integration
//!
//! This module detects and parses Makefile and Justfile targets,
//! converting them to Jake Recipe structs for unified listing and execution.

const std = @import("std");
const parser = @import("parser.zig");
const Recipe = parser.Recipe;
const RecipeOrigin = parser.RecipeOrigin;
const ExternalKind = RecipeOrigin.ExternalKind;

pub const ExternalFiles = struct {
    makefile: ?[]const u8,
    justfile: ?[]const u8,

    pub fn deinit(self: *ExternalFiles, allocator: std.mem.Allocator) void {
        if (self.makefile) |mf| allocator.free(mf);
        if (self.justfile) |jf| allocator.free(jf);
    }
};

pub const ExternalRecipes = struct {
    recipes: []Recipe,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ExternalRecipes) void {
        for (self.recipes) |recipe| {
            self.allocator.free(recipe.name);
            if (recipe.description) |desc| {
                self.allocator.free(desc);
            }
            // Free the duplicated origin strings
            if (recipe.origin) |origin| {
                self.allocator.free(origin.original_name);
                if (origin.source_file) |sf| {
                    self.allocator.free(sf);
                }
            }
        }
        self.allocator.free(self.recipes);
    }
};

fn ownedEmptyExternalRecipes(allocator: std.mem.Allocator) ExternalRecipes {
    return .{
        .recipes = allocator.alloc(Recipe, 0) catch unreachable,
        .allocator = allocator,
    };
}

fn joinBasePath(allocator: std.mem.Allocator, base_dir: []const u8, file_name: []const u8) ![]u8 {
    if (base_dir.len == 0 or std.mem.eql(u8, base_dir, ".")) {
        return try allocator.dupe(u8, file_name);
    }

    return try std.fs.path.join(allocator, &[_][]const u8{ base_dir, file_name });
}

/// Detect Makefile and Justfile in the given directory
pub fn detectExternalFiles(allocator: std.mem.Allocator, dir_path: []const u8) !ExternalFiles {
    var dir = std.fs.cwd().openDir(dir_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return ExternalFiles{ .makefile = null, .justfile = null },
        else => return err,
    };
    defer dir.close();

    return detectExternalFilesInDir(allocator, dir);
}

/// Detect Makefile and Justfile in an already-open directory
pub fn detectExternalFilesInDir(allocator: std.mem.Allocator, dir: std.fs.Dir) !ExternalFiles {
    var result = ExternalFiles{ .makefile = null, .justfile = null };

    // Check for Makefile variants (in priority order)
    const makefile_names = [_][]const u8{ "GNUmakefile", "Makefile", "makefile" };
    for (makefile_names) |name| {
        if (dir.statFile(name)) |_| {
            result.makefile = try allocator.dupe(u8, name);
            break;
        } else |_| {}
    }

    // Check for Justfile variants (in priority order)
    const justfile_names = [_][]const u8{ "justfile", "Justfile", ".justfile" };
    for (justfile_names) |name| {
        if (dir.statFile(name)) |_| {
            result.justfile = try allocator.dupe(u8, name);
            break;
        } else |_| {}
    }

    return result;
}

/// Parse Makefile targets into Recipe structs
pub fn parseMakefile(allocator: std.mem.Allocator, path: []const u8) !ExternalRecipes {
    const file = std.fs.cwd().openFile(path, .{}) catch {
        return ownedEmptyExternalRecipes(allocator);
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return ownedEmptyExternalRecipes(allocator);
    };
    defer allocator.free(content);

    return parseMakefileContent(allocator, content, path);
}

/// Parse Makefile content to extract targets
fn parseMakefileContent(allocator: std.mem.Allocator, content: []const u8, source_file_param: []const u8) !ExternalRecipes {
    var recipes: std.ArrayListUnmanaged(Recipe) = .empty;
    errdefer {
        for (recipes.items) |recipe| {
            allocator.free(recipe.name);
            if (recipe.description) |desc| allocator.free(desc);
            if (recipe.origin) |origin| {
                allocator.free(origin.original_name);
                if (origin.source_file) |sf| allocator.free(sf);
            }
        }
        recipes.deinit(allocator);
    }

    var phony_targets = std.StringHashMap(void).init(allocator);
    defer phony_targets.deinit();

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Check for .PHONY declaration
        if (std.mem.startsWith(u8, trimmed, ".PHONY:")) {
            const phony_list = std.mem.trim(u8, trimmed[7..], " \t");
            var phony_iter = std.mem.tokenizeAny(u8, phony_list, " \t");
            while (phony_iter.next()) |target| {
                try phony_targets.put(target, {});
            }
            continue;
        }

        // Skip special targets and includes
        if (trimmed[0] == '.' or trimmed[0] == '-' or std.mem.startsWith(u8, trimmed, "include ")) {
            continue;
        }

        // Look for target definitions: "target:" or "target: deps"
        if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
            // Skip if it looks like a variable assignment (:= or ::=)
            if (colon_pos + 1 < trimmed.len and (trimmed[colon_pos + 1] == '=' or trimmed[colon_pos + 1] == ':')) {
                continue;
            }

            const target_part = std.mem.trim(u8, trimmed[0..colon_pos], " \t");

            // Skip pattern rules (contain %)
            if (std.mem.indexOf(u8, target_part, "%") != null) continue;

            // Skip targets with variable references
            if (std.mem.indexOf(u8, target_part, "$") != null) continue;

            // Handle multiple targets on one line
            var target_iter = std.mem.tokenizeAny(u8, target_part, " \t");
            while (target_iter.next()) |target| {
                // Skip invalid target names
                if (target.len == 0) continue;
                if (target[0] == '.' or target[0] == '$') continue;

                // Create prefixed name: "make.target"
                const prefixed_name = try std.fmt.allocPrint(allocator, "make.{s}", .{target});
                errdefer allocator.free(prefixed_name);

                // Duplicate the original name and source file since content will be freed
                const original_name = try allocator.dupe(u8, target);
                errdefer allocator.free(original_name);

                const source_file = try allocator.dupe(u8, source_file_param);
                errdefer allocator.free(source_file);

                const recipe = Recipe{
                    .name = prefixed_name,
                    .kind = .simple,
                    .dependencies = &.{},
                    .file_deps = &.{},
                    .output = null,
                    .params = &.{},
                    .commands = &.{},
                    .pre_hooks = &.{},
                    .post_hooks = &.{},
                    .doc_comment = null,
                    .is_default = false,
                    .aliases = &.{},
                    .group = null,
                    .description = null,
                    .shell = null,
                    .working_dir = null,
                    .only_os = &.{},
                    .quiet = false,
                    .hidden = target[0] == '_',
                    .needs = &.{},
                    .timeout_seconds = null,
                    .origin = RecipeOrigin{
                        .original_name = original_name,
                        .import_prefix = "make",
                        .source_file = source_file,
                        .external_kind = .makefile,
                    },
                };

                try recipes.append(allocator, recipe);
            }
        }
    }

    return ExternalRecipes{
        .recipes = try recipes.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Parse Justfile targets into Recipe structs
/// Uses `just --list` command for accurate parsing
pub fn parseJustfile(allocator: std.mem.Allocator, path: []const u8) !ExternalRecipes {
    // Try using `just --list` first for accurate parsing
    const result = try runJustList(allocator, path);
    if (result.recipes.len > 0) {
        return result;
    }

    // Fallback: parse file directly (less accurate but works without `just` installed)
    return parseJustfileDirect(allocator, path);
}

/// Run `just --list` to get recipe list
fn runJustList(allocator: std.mem.Allocator, path_param: []const u8) !ExternalRecipes {
    var recipes: std.ArrayListUnmanaged(Recipe) = .empty;
    errdefer {
        for (recipes.items) |recipe| {
            allocator.free(recipe.name);
            if (recipe.description) |desc| allocator.free(desc);
            if (recipe.origin) |origin| {
                allocator.free(origin.original_name);
                if (origin.source_file) |sf| allocator.free(sf);
            }
        }
        recipes.deinit(allocator);
    }

    // Run: just --justfile <path> --list --unsorted --list-heading '' --list-prefix ''
    const justfile_arg = std.fs.path.basename(path_param);
    const justfile_dir = std.fs.path.dirname(path_param) orelse ".";

    var child = std.process.Child.init(&[_][]const u8{
        "just",
        "--justfile",
        justfile_arg,
        "--list",
        "--unsorted",
        "--list-heading",
        "",
        "--list-prefix",
        "",
    }, allocator);
    child.cwd = justfile_dir;

    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore; // Don't need stderr, avoid deadlock if buffer fills

    _ = child.spawn() catch {
        // `just` not installed, return empty
        return ownedEmptyExternalRecipes(allocator);
    };

    const stdout_file = child.stdout orelse {
        return ownedEmptyExternalRecipes(allocator);
    };
    const stdout = stdout_file.readToEndAlloc(allocator, 64 * 1024) catch {
        return ownedEmptyExternalRecipes(allocator);
    };
    defer allocator.free(stdout);

    _ = child.wait() catch {
        return ownedEmptyExternalRecipes(allocator);
    };

    // Parse output: each line is "recipe_name  # description" or just "recipe_name"
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip lines starting with [ (like [info], [private], etc.)
        if (trimmed.len > 0 and trimmed[0] == '[') continue;

        var name: []const u8 = undefined;
        var description: ?[]const u8 = null;

        // Check for description separator " # "
        if (std.mem.indexOf(u8, trimmed, " # ")) |desc_pos| {
            name = std.mem.trim(u8, trimmed[0..desc_pos], " \t");
            description = try allocator.dupe(u8, std.mem.trim(u8, trimmed[desc_pos + 3 ..], " \t"));
        } else {
            // No description, just the name (might have parameters)
            // Handle "recipe arg1 arg2" format
            var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
            name = parts.next() orelse continue;
        }

        // Create prefixed name: "just.target"
        const prefixed_name = try std.fmt.allocPrint(allocator, "just.{s}", .{name});
        errdefer allocator.free(prefixed_name);

        // Duplicate the original name and source file since stdout will be freed
        const original_name = try allocator.dupe(u8, name);
        errdefer allocator.free(original_name);

        const source_file = try allocator.dupe(u8, path_param);
        errdefer allocator.free(source_file);

        const recipe = Recipe{
            .name = prefixed_name,
            .kind = .simple,
            .dependencies = &.{},
            .file_deps = &.{},
            .output = null,
            .params = &.{},
            .commands = &.{},
            .pre_hooks = &.{},
            .post_hooks = &.{},
            .doc_comment = null,
            .is_default = false,
            .aliases = &.{},
            .group = null,
            .description = description,
            .shell = null,
            .working_dir = null,
            .only_os = &.{},
            .quiet = false,
            .hidden = name[0] == '_',
            .needs = &.{},
            .timeout_seconds = null,
            .origin = RecipeOrigin{
                .original_name = original_name,
                .import_prefix = "just",
                .source_file = source_file,
                .external_kind = .justfile,
            },
        };

        try recipes.append(allocator, recipe);
    }

    return ExternalRecipes{
        .recipes = try recipes.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Parse Justfile directly (fallback when `just` is not installed)
fn parseJustfileDirect(allocator: std.mem.Allocator, path_param: []const u8) !ExternalRecipes {
    const file = std.fs.cwd().openFile(path_param, .{}) catch {
        return ownedEmptyExternalRecipes(allocator);
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch {
        return ownedEmptyExternalRecipes(allocator);
    };
    defer allocator.free(content);

    var recipes: std.ArrayListUnmanaged(Recipe) = .empty;
    errdefer {
        for (recipes.items) |recipe| {
            allocator.free(recipe.name);
            if (recipe.description) |desc| allocator.free(desc);
            if (recipe.origin) |origin| {
                allocator.free(origin.original_name);
                if (origin.source_file) |sf| allocator.free(sf);
            }
        }
        recipes.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, content, '\n');
    var prev_comment: ?[]const u8 = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Track comments for descriptions
        if (trimmed.len > 0 and trimmed[0] == '#') {
            prev_comment = std.mem.trim(u8, trimmed[1..], " \t");
            continue;
        }

        // Skip empty lines (but preserve comment for next recipe)
        if (trimmed.len == 0) continue;

        // Skip attributes like [private], [group('name')]
        if (trimmed[0] == '[') {
            continue;
        }

        // Look for recipe definitions: "recipe:" or "recipe arg:"
        // Must start at beginning of line (not indented)
        if (line.len > 0 and line[0] != ' ' and line[0] != '\t') {
            if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
                // Skip if it looks like a variable assignment
                if (colon_pos + 1 < trimmed.len and trimmed[colon_pos + 1] == '=') {
                    prev_comment = null;
                    continue;
                }

                const recipe_part = trimmed[0..colon_pos];

                // Extract just the recipe name (before any parameters)
                var parts = std.mem.tokenizeAny(u8, recipe_part, " \t");
                const name = parts.next() orelse {
                    prev_comment = null;
                    continue;
                };

                // Skip invalid names
                if (name.len == 0 or name[0] == '@') {
                    prev_comment = null;
                    continue;
                }

                // Create prefixed name: "just.target"
                const prefixed_name = try std.fmt.allocPrint(allocator, "just.{s}", .{name});
                errdefer allocator.free(prefixed_name);

                // Duplicate the original name and source file since content will be freed
                const original_name = try allocator.dupe(u8, name);
                errdefer allocator.free(original_name);

                const source_file = try allocator.dupe(u8, path_param);
                errdefer allocator.free(source_file);

                var description: ?[]const u8 = null;
                if (prev_comment) |comment| {
                    description = try allocator.dupe(u8, comment);
                }

                const recipe = Recipe{
                    .name = prefixed_name,
                    .kind = .simple,
                    .dependencies = &.{},
                    .file_deps = &.{},
                    .output = null,
                    .params = &.{},
                    .commands = &.{},
                    .pre_hooks = &.{},
                    .post_hooks = &.{},
                    .doc_comment = null,
                    .is_default = false,
                    .aliases = &.{},
                    .group = null,
                    .description = description,
                    .shell = null,
                    .working_dir = null,
                    .only_os = &.{},
                    .quiet = false,
                    .hidden = name[0] == '_',
                    .needs = &.{},
                    .timeout_seconds = null,
                    .origin = RecipeOrigin{
                        .original_name = original_name,
                        .import_prefix = "just",
                        .source_file = source_file,
                        .external_kind = .justfile,
                    },
                };

                try recipes.append(allocator, recipe);
            }
        }

        prev_comment = null;
    }

    return ExternalRecipes{
        .recipes = try recipes.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Load external Makefile/Justfile recipes and merge them into the jakefile
/// This should be called after import resolution but before building the index
pub fn loadAndMergeExternalRecipes(
    allocator: std.mem.Allocator,
    jakefile: *parser.Jakefile,
    base_dir: []const u8,
) !?ExternalRecipes {
    // Detect external files in the base directory
    const external_files = try detectExternalFiles(allocator, base_dir);
    defer {
        if (external_files.makefile) |mf| allocator.free(mf);
        if (external_files.justfile) |jf| allocator.free(jf);
    }

    // If no external files found, nothing to do
    if (external_files.makefile == null and external_files.justfile == null) {
        return null;
    }

    // Collect all external recipes
    var all_external: std.ArrayListUnmanaged(Recipe) = .empty;
    errdefer {
        for (all_external.items) |recipe| {
            allocator.free(recipe.name);
            if (recipe.description) |desc| allocator.free(desc);
            if (recipe.origin) |origin| {
                allocator.free(origin.original_name);
                if (origin.source_file) |source_file| {
                    allocator.free(source_file);
                }
            }
        }
        all_external.deinit(allocator);
    }

    // Parse Makefile if present
    if (external_files.makefile) |makefile_name| {
        const makefile_path = try joinBasePath(allocator, base_dir, makefile_name);
        defer allocator.free(makefile_path);

        const make_recipes = try parseMakefile(allocator, makefile_path);
        defer allocator.free(make_recipes.recipes);
        // Don't call make_recipes.deinit() - we're taking ownership of the recipes
        for (make_recipes.recipes) |recipe| {
            try all_external.append(allocator, recipe);
        }
    }

    // Parse Justfile if present
    if (external_files.justfile) |justfile_name| {
        const justfile_path = try joinBasePath(allocator, base_dir, justfile_name);
        defer allocator.free(justfile_path);

        const just_recipes = try parseJustfile(allocator, justfile_path);
        defer allocator.free(just_recipes.recipes);
        // Don't call just_recipes.deinit() - we're taking ownership of the recipes
        for (just_recipes.recipes) |recipe| {
            try all_external.append(allocator, recipe);
        }
    }

    if (all_external.items.len == 0) {
        return null;
    }

    // Merge external recipes into the jakefile's recipes
    const existing_len = jakefile.recipes.len;
    const new_len = existing_len + all_external.items.len;

    // Save old slice to free after copying
    const old_recipes = jakefile.recipes;

    // Allocate new recipes array
    const new_recipes = try allocator.alloc(Recipe, new_len);
    @memcpy(new_recipes[0..existing_len], old_recipes);
    @memcpy(new_recipes[existing_len..], all_external.items);

    // Free the old slice (just the array backing, not the Recipe internal allocations
    // which are shallow-copied and will be freed by jakefile.deinit)
    allocator.free(old_recipes);

    // Replace the jakefile's recipes slice with the merged array
    jakefile.recipes = new_recipes;

    return ExternalRecipes{
        .recipes = try all_external.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "parseMakefileContent - basic targets" {
    const allocator = std.testing.allocator;

    const content =
        \\# Makefile
        \\.PHONY: all clean test
        \\
        \\all: build test
        \\    echo "Building all"
        \\
        \\build:
        \\    gcc -o main main.c
        \\
        \\clean:
        \\    rm -f *.o
        \\
        \\_private:
        \\    echo "Private target"
    ;

    var result = try parseMakefileContent(allocator, content, "Makefile");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 4), result.recipes.len);

    // Check first recipe
    try std.testing.expectEqualStrings("make.all", result.recipes[0].name);
    try std.testing.expect(result.recipes[0].origin.?.external_kind == .makefile);
    try std.testing.expectEqualStrings("all", result.recipes[0].origin.?.original_name);

    // Check hidden recipe
    try std.testing.expectEqualStrings("make._private", result.recipes[3].name);
    try std.testing.expect(result.recipes[3].hidden);
}

test "parseMakefileContent - skip pattern rules" {
    const allocator = std.testing.allocator;

    const content =
        \\%.o: %.c
        \\    $(CC) -c $< -o $@
        \\
        \\build:
        \\    make all
    ;

    var result = try parseMakefileContent(allocator, content, "Makefile");
    defer result.deinit();

    // Should only have 'build', not the pattern rule
    try std.testing.expectEqual(@as(usize, 1), result.recipes.len);
    try std.testing.expectEqualStrings("make.build", result.recipes[0].name);
}

test "parseMakefileContent - skip variable assignments" {
    const allocator = std.testing.allocator;

    const content =
        \\CC := gcc
        \\CFLAGS = -Wall
        \\
        \\build:
        \\    $(CC) $(CFLAGS) main.c
    ;

    var result = try parseMakefileContent(allocator, content, "Makefile");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.recipes.len);
    try std.testing.expectEqualStrings("make.build", result.recipes[0].name);
}

test "parseMakefile missing file returns deinit-safe empty allocation" {
    var result = try parseMakefile(std.testing.allocator, "definitely-missing-makefile");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.recipes.len);
}

test "loadAndMergeExternalRecipes resolves external files relative to base_dir" {
    if (@import("builtin").os.tag == .windows) return;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makePath("nested");

    const makefile =
        "nested-target:\n" ++
        "\tprintf nested-target\n";
    {
        const file = try tmp_dir.dir.createFile("nested/Makefile", .{});
        defer file.close();
        try file.writeAll(makefile);
    }

    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);

    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    const source =
        \\task local:
        \\    echo local
    ;
    var lex = @import("lexer.zig").Lexer.init(source);
    var p = parser.Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    var external_allocations = (try loadAndMergeExternalRecipes(std.testing.allocator, &jakefile, "nested")).?;
    defer external_allocations.deinit();

    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), external_allocations.recipes.len);
    try std.testing.expectEqualStrings("make.nested-target", external_allocations.recipes[0].name);
    try std.testing.expectEqualStrings("nested/Makefile", external_allocations.recipes[0].origin.?.source_file.?);
}
