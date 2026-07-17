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
            if (recipe.group) |g| {
                self.allocator.free(g);
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
        // Indented lines are recipe commands or continuations, never target
        // definitions — in a Makefile every target starts at column 0. Skipping
        // them prevents a shell command that happens to contain a colon (e.g.
        // `curl -fsSL https://…` or `cd web && npm run og:check`) from being
        // mis-parsed into bogus targets like `make.curl` / `make.https` (jake#22).
        if (line.len > 0 and (line[0] == ' ' or line[0] == '\t')) continue;

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
                    .on_error_hooks = &.{},
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

    return parseJustListOutput(allocator, stdout, path_param);
}

/// Parse the output of `just --list --list-heading '' --list-prefix ''` into
/// recipes. Split out from `runJustList` so the (bug-prone) line parsing can be
/// unit-tested without spawning `just`.
fn parseJustListOutput(allocator: std.mem.Allocator, stdout: []const u8, path_param: []const u8) !ExternalRecipes {
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

    // Each line is "recipe_name [params] [# description]" or a "[group]" header.
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip lines starting with [ (like [group], [private], etc.)
        if (trimmed[0] == '[') continue;

        var description: ?[]const u8 = null;

        // Split off an optional " # description" suffix, then take the first
        // whitespace token of what remains as the recipe name. `just --list`
        // prints parameters and defaults inline (`dev path="."`, `web port="3333"`),
        // so the name is only the leading token — taking the whole pre-`#` span
        // leaked params into the name (`just.dev path="."`), breaking listing and
        // invocation for the majority of real justfiles.
        const name_part = if (std.mem.indexOf(u8, trimmed, " # ")) |desc_pos| blk: {
            description = try allocator.dupe(u8, std.mem.trim(u8, trimmed[desc_pos + 3 ..], " \t"));
            break :blk std.mem.trim(u8, trimmed[0..desc_pos], " \t");
        } else trimmed;
        errdefer if (description) |d| allocator.free(d);

        var name_parts = std.mem.tokenizeAny(u8, name_part, " \t");
        const name = name_parts.next() orelse {
            if (description) |d| allocator.free(d);
            continue;
        };

        // Skip submodule markers (`just --list` prints `mymod ...` for a `mod`),
        // which are not directly-runnable recipes.
        if (name_parts.next()) |second| {
            if (std.mem.eql(u8, second, "...")) {
                if (description) |d| allocator.free(d);
                continue;
            }
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
            .on_error_hooks = &.{},
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

/// Attributes accumulated from `[...]` lines preceding a recipe. `doc`/`group`
/// arg slices borrow from the source buffer (valid for the parse's lifetime).
const JustAttributes = struct {
    private: bool = false,
    doc: ?[]const u8 = null,
    group: ?[]const u8 = null,

    fn clear(self: *JustAttributes) void {
        self.* = .{};
    }
};

/// Parse a `[...]` attribute line into `attrs`, respecting quoted payloads so a
/// comma or keyword inside `[doc('a, private')]` is not misread. Handles
/// comma-separated attributes (`[macos, linux]`) and parenthesized string args
/// (`[group('build')]`, `[doc("text")]`). Unknown attributes are ignored.
fn parseJustAttributeLine(line: []const u8, attrs: *JustAttributes) void {
    // Strip the surrounding brackets: `[a, b('c')]` -> `a, b('c')`.
    const close = std.mem.lastIndexOfScalar(u8, line, ']') orelse return;
    if (close == 0) return;
    const inner = line[1..close];

    var i: usize = 0;
    while (i < inner.len) {
        // Skip separators/whitespace between attributes.
        while (i < inner.len and (inner[i] == ' ' or inner[i] == '\t' or inner[i] == ',')) i += 1;
        const name_start = i;
        while (i < inner.len and (std.ascii.isAlphanumeric(inner[i]) or inner[i] == '-' or inner[i] == '_')) i += 1;
        const attr_name = inner[name_start..i];

        // Optional parenthesized argument, e.g. group('name') / doc("text").
        var arg: ?[]const u8 = null;
        while (i < inner.len and (inner[i] == ' ' or inner[i] == '\t')) i += 1;
        if (i < inner.len and inner[i] == '(') {
            i += 1;
            const arg_start = i;
            var quote: ?u8 = null;
            while (i < inner.len) : (i += 1) {
                const c = inner[i];
                if (quote) |q| {
                    if (c == q) quote = null;
                } else if (c == '\'' or c == '"') {
                    quote = c;
                } else if (c == ')') break;
            }
            arg = std.mem.trim(u8, inner[arg_start..i], " \t'\"");
            if (i < inner.len) i += 1; // consume ')'
        }

        if (attr_name.len == 0) {
            i += 1; // guard against no progress on stray punctuation
            continue;
        }
        if (std.mem.eql(u8, attr_name, "private")) {
            attrs.private = true;
        } else if (std.mem.eql(u8, attr_name, "doc")) {
            attrs.doc = arg; // `[doc]` with no arg leaves it null (suppresses comment)
        } else if (std.mem.eql(u8, attr_name, "group")) {
            attrs.group = arg;
        }
    }
}

/// Parse a Justfile directly, without invoking `just`. Used as a fallback when
/// `just` is not installed or `just --list` fails. Mirrors `just`'s own
/// listing: recipe names only (parameters/dependencies stripped), `@` quiet
/// markers removed, `[private]`/`_`-prefixed recipes hidden, `[doc(...)]` and
/// leading `#` comments as descriptions, `[group(...)]` captured, platform
/// variants deduped, and comment/attribute association broken by a blank line.
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
            if (recipe.group) |g| allocator.free(g);
            if (recipe.origin) |origin| {
                allocator.free(origin.original_name);
                if (origin.source_file) |sf| allocator.free(sf);
            }
        }
        recipes.deinit(allocator);
    }

    // Track names already emitted so platform-guarded duplicate definitions
    // (`[windows] install …` + `[unix] install …`) list once, matching `just`.
    // Keys borrow from `content`, which outlives this map (defers run LIFO).
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var lines = std.mem.splitScalar(u8, content, '\n');
    // Pending doc/attribute state attached to the *next* recipe. All slices
    // borrow from `content`; a blank line clears them (just breaks association).
    var prev_comment: ?[]const u8 = null;
    var attrs: JustAttributes = .{};

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Blank line: breaks comment/attribute association with the next recipe.
        if (trimmed.len == 0) {
            prev_comment = null;
            attrs.clear();
            continue;
        }

        // Comment line becomes the description of the following recipe.
        if (trimmed[0] == '#') {
            prev_comment = std.mem.trim(u8, trimmed[1..], " \t");
            continue;
        }

        // Attribute line(s) — accumulate, preserving any preceding comment.
        if (trimmed[0] == '[') {
            parseJustAttributeLine(trimmed, &attrs);
            continue;
        }

        // Recipe definitions start at column 0 (indented lines are recipe bodies).
        if (line[0] == ' ' or line[0] == '\t') continue;

        const colon_pos = std.mem.indexOfScalar(u8, trimmed, ':') orelse {
            // Non-recipe statement (`mod foo`, `import "x"`, bare `set …`).
            prev_comment = null;
            attrs.clear();
            continue;
        };

        // Assignment (`x := …`, `export x := …`, `alias b := …`), not a recipe.
        if (colon_pos + 1 < trimmed.len and trimmed[colon_pos + 1] == '=') {
            prev_comment = null;
            attrs.clear();
            continue;
        }

        const recipe_part = trimmed[0..colon_pos];
        var parts = std.mem.tokenizeAny(u8, recipe_part, " \t");
        var name = parts.next() orelse {
            prev_comment = null;
            attrs.clear();
            continue;
        };

        // A leading '@' marks a quiet recipe (`@build:` defines `build`).
        if (name.len > 0 and name[0] == '@') name = name[1..];

        // Skip invalid names and duplicates (platform-guarded variants).
        if (name.len == 0 or seen.contains(name)) {
            prev_comment = null;
            attrs.clear();
            continue;
        }

        const prefixed_name = try std.fmt.allocPrint(allocator, "just.{s}", .{name});
        errdefer allocator.free(prefixed_name);

        const original_name = try allocator.dupe(u8, name);
        errdefer allocator.free(original_name);

        const source_file = try allocator.dupe(u8, path_param);
        errdefer allocator.free(source_file);

        // Description: `[doc('…')]` takes precedence over a leading `#` comment.
        var description: ?[]const u8 = null;
        if (attrs.doc) |d| {
            description = try allocator.dupe(u8, d);
        } else if (prev_comment) |comment| {
            description = try allocator.dupe(u8, comment);
        }
        errdefer if (description) |d| allocator.free(d);

        const group: ?[]const u8 = if (attrs.group) |g| try allocator.dupe(u8, g) else null;
        errdefer if (group) |g| allocator.free(g);

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
            .on_error_hooks = &.{},
            .doc_comment = null,
            .is_default = false,
            .aliases = &.{},
            .group = group,
            .description = description,
            .shell = null,
            .working_dir = null,
            .only_os = &.{},
            .quiet = false,
            .hidden = attrs.private or name[0] == '_',
            .needs = &.{},
            .timeout_seconds = null,
            .origin = RecipeOrigin{
                .original_name = original_name,
                .import_prefix = "just",
                .source_file = source_file,
                .external_kind = .justfile,
            },
        };

        // Record the name before appending so `append` is the last fallible op:
        // if it fails, the recipe is not in the list and the per-iteration
        // errdefers (not the outer one) free its strings — no double free.
        try seen.put(name, {});
        try recipes.append(allocator, recipe);

        prev_comment = null;
        attrs.clear();
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

test "parseJustListOutput - strips params, keeps only the recipe name" {
    const allocator = std.testing.allocator;

    // Mirrors real `just --list --list-heading '' --list-prefix ''` output:
    // recipes print their parameters and defaults inline, optionally followed by
    // a " # description". The recipe name is only the leading token. Group
    // headers ("[bench]") and submodule markers ("website ...") are not recipes.
    const output =
        "website ...                        # Marketing site (Astro + bun)\n" ++
        "build                              # Build the solution.\n" ++
        "[bench]\n" ++
        "bench filter=\"*\"                   # Run benchmarks.\n" ++
        "dev path=\".\"\n" ++
        "aot rid=\"osx-arm64\" out=\"dist-aot\" # NativeAOT.\n" ++
        "_helper\n";

    var result = try parseJustListOutput(allocator, output, "justfile");
    defer result.deinit();

    // website (submodule) and [bench] (group header) are excluded.
    try std.testing.expectEqual(@as(usize, 5), result.recipes.len);
    try std.testing.expectEqualStrings("just.build", result.recipes[0].name);
    try std.testing.expectEqualStrings("just.bench", result.recipes[1].name);
    try std.testing.expectEqualStrings("just.dev", result.recipes[2].name);
    try std.testing.expectEqualStrings("just.aot", result.recipes[3].name);
    try std.testing.expectEqualStrings("just._helper", result.recipes[4].name);

    // Original (unprefixed) name and description round-trip correctly.
    try std.testing.expectEqualStrings("bench", result.recipes[1].origin.?.original_name);
    try std.testing.expectEqualStrings("Run benchmarks.", result.recipes[1].description.?);
    // dev has params but no description.
    try std.testing.expect(result.recipes[2].description == null);
    // Leading-underscore recipes are hidden.
    try std.testing.expect(result.recipes[4].hidden);
}

test "parseJustListOutput - empty output yields no recipes" {
    var result = try parseJustListOutput(std.testing.allocator, "", "justfile");
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.recipes.len);
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

test "parseMakefileContent - tab-indented recipe lines with colons are not targets" {
    const allocator = std.testing.allocator;

    // Real Makefiles indent recipe bodies with tabs. Lines like the `curl`
    // URL and `npm run og:check` contain colons but must NOT be parsed as
    // target definitions (jake#22). Continuation lines are indented too.
    const content =
        "site-og:\n" ++
        "\tcd website && npm run og:check\n" ++
        "\tcd website && npm run og\n" ++
        "\n" ++
        "notebook-ui-vendor:\n" ++
        "\tmkdir -p vendor\n" ++
        "\tcurl -fsSL https://unpkg.com/@sema-lang/ui/dist/sema-ui.js \\\n" ++
        "\t  -o vendor/sema-ui.js\n" ++
        "\t@echo \"done: vendored\"\n";

    var result = try parseMakefileContent(allocator, content, "Makefile");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.recipes.len);
    try std.testing.expectEqualStrings("make.site-og", result.recipes[0].name);
    try std.testing.expectEqualStrings("make.notebook-ui-vendor", result.recipes[1].name);
}

test "parseMakefile missing file returns deinit-safe empty allocation" {
    var result = try parseMakefile(std.testing.allocator, "definitely-missing-makefile");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.recipes.len);
}

test "parseJustAttributeLine parses names, args, and quoted payloads" {
    {
        var a: JustAttributes = .{};
        parseJustAttributeLine("[private]", &a);
        try std.testing.expect(a.private);
        try std.testing.expect(a.doc == null and a.group == null);
    }
    {
        var a: JustAttributes = .{};
        parseJustAttributeLine("[group('deploy')]", &a);
        try std.testing.expectEqualStrings("deploy", a.group.?);
    }
    {
        var a: JustAttributes = .{};
        parseJustAttributeLine("[doc(\"explicit doc\")]", &a);
        try std.testing.expectEqualStrings("explicit doc", a.doc.?);
    }
    {
        // Comma-separated attributes on one line; `private` must be detected.
        var a: JustAttributes = .{};
        parseJustAttributeLine("[macos, private]", &a);
        try std.testing.expect(a.private);
    }
    {
        // A keyword inside a quoted arg must NOT be misread as an attribute.
        var a: JustAttributes = .{};
        parseJustAttributeLine("[doc('this is private, really')]", &a);
        try std.testing.expect(!a.private);
        try std.testing.expectEqualStrings("this is private, really", a.doc.?);
    }
    {
        // A closing paren *inside* the quoted arg must not end the arg early,
        // and a keyword after it must not leak in as a separate attribute.
        var a: JustAttributes = .{};
        parseJustAttributeLine("[doc('run (private) mode')]", &a);
        try std.testing.expect(!a.private);
        try std.testing.expectEqualStrings("run (private) mode", a.doc.?);
    }
}

test "parseJustfileDirect matches just's listing semantics" {
    if (@import("builtin").os.tag == .windows) return;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // This justfile and the expected result were validated against real
    // `just --list` / `just --summary` output (just 1.50.0). The direct parser
    // is the fallback used when `just` is unavailable, so it must reproduce the
    // same visible-recipe set, hidden flags, and descriptions.
    const justfile =
        "# top comment for build\n" ++
        "build:\n" ++
        "    echo build\n" ++
        "\n" ++
        "# comment then blank\n" ++
        "\n" ++
        "after-blank:\n" ++
        "    echo x\n" ++
        "\n" ++
        "[private]\n" ++
        "secret:\n" ++
        "    echo s\n" ++
        "\n" ++
        "# doc for grouped\n" ++
        "[group('deploy')]\n" ++
        "[confirm]\n" ++
        "deploy:\n" ++
        "    echo d\n" ++
        "\n" ++
        "[doc('explicit doc')]\n" ++
        "documented:\n" ++
        "    echo doc\n" ++
        "\n" ++
        "_under:\n" ++
        "    echo u\n" ++
        "\n" ++
        "@quietrec:\n" ++
        "    echo q\n" ++
        "\n" ++
        "export FOO := \"bar\"\n" ++
        "alias b := build\n" ++
        "set shell := [\"bash\", \"-c\"]\n" ++
        "mod submod\n" ++
        "import \"other.just\"\n" ++
        "\n" ++
        "[unix]\n" ++
        "plat:\n" ++
        "    echo unix\n" ++
        "[windows]\n" ++
        "plat:\n" ++
        "    echo win\n" ++
        "\n" ++
        "variadic +args:\n" ++
        "    echo {{args}}\n" ++
        "\n" ++
        "with-colon-default host=\"0.0.0.0:8080\":\n" ++
        "    echo {{host}}\n";
    {
        const file = try tmp_dir.dir.createFile("justfile", .{});
        defer file.close();
        try file.writeAll(justfile);
    }

    const cwd = std.fs.cwd();
    const old_cwd = try cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(old_cwd);
    const tmp_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(old_cwd) catch {};

    var result = try parseJustfileDirect(std.testing.allocator, "justfile");
    defer result.deinit();

    // Build a name -> recipe map for order-independent assertions.
    var by_name = std.StringHashMap(*const Recipe).init(std.testing.allocator);
    defer by_name.deinit();
    for (result.recipes) |*r| try by_name.put(r.origin.?.original_name, r);

    // Every real recipe is present (assignments/set/mod/import are not recipes).
    const expected = [_][]const u8{
        "build",  "after-blank", "secret", "deploy",   "documented",
        "_under", "quietrec",    "plat",   "variadic", "with-colon-default",
    };
    for (expected) |n| try std.testing.expect(by_name.contains(n));
    try std.testing.expectEqual(@as(usize, expected.len), result.recipes.len);

    // Non-recipes must not leak in.
    try std.testing.expect(!by_name.contains("FOO"));
    try std.testing.expect(!by_name.contains("b"));
    try std.testing.expect(!by_name.contains("shell"));
    try std.testing.expect(!by_name.contains("submod"));

    // `[private]` and `_`-prefixed recipes are hidden; others visible.
    try std.testing.expect(by_name.get("secret").?.hidden);
    try std.testing.expect(by_name.get("_under").?.hidden);
    try std.testing.expect(!by_name.get("build").?.hidden);
    try std.testing.expect(!by_name.get("deploy").?.hidden);

    // Description from a leading comment.
    try std.testing.expectEqualStrings("top comment for build", by_name.get("build").?.description.?);
    // Blank line breaks the comment association.
    try std.testing.expect(by_name.get("after-blank").?.description == null);
    // `[doc('…')]` provides the description.
    try std.testing.expectEqualStrings("explicit doc", by_name.get("documented").?.description.?);
    // Comment survives intervening attribute lines.
    try std.testing.expectEqualStrings("doc for grouped", by_name.get("deploy").?.description.?);
    // `[group('…')]` is captured.
    try std.testing.expectEqualStrings("deploy", by_name.get("deploy").?.group.?);
    // `@` quiet marker stripped; colon inside a default doesn't corrupt the name.
    try std.testing.expectEqualStrings("just.quietrec", by_name.get("quietrec").?.name);
    try std.testing.expectEqualStrings("just.with-colon-default", by_name.get("with-colon-default").?.name);
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
