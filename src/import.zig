// Jake Import System - Handles importing recipes from other Jakefiles
//
// Features:
// - @import "path/to/file.jake" - import all recipes
// - @import "file.jake" as prefix - import with namespace prefix
// - Circular import detection
// - Relative path resolution

const std = @import("std");
const parser_mod = @import("parser.zig");
const lexer_mod = @import("lexer.zig");
const hooks_mod = @import("hooks.zig");

const Jakefile = parser_mod.Jakefile;
const ImportDirective = parser_mod.ImportDirective;
const Recipe = parser_mod.Recipe;
const Variable = parser_mod.Variable;
const Directive = parser_mod.Directive;
const Parser = parser_mod.Parser;
const Lexer = lexer_mod.Lexer;
const Hook = hooks_mod.Hook;

pub const ImportError = error{
    CircularImport,
    FileNotFound,
    AccessDenied,
    ParseError,
    OutOfMemory,
    InvalidPath,
    Unexpected,
};

/// Resolves and processes imports for Jakefiles
pub const ImportResolver = struct {
    allocator: std.mem.Allocator,
    /// Stack of file paths currently being processed (for cycle detection)
    import_stack: std.StringHashMapUnmanaged(void),
    /// Cache of already resolved absolute paths to avoid re-processing
    resolved_cache: std.StringHashMapUnmanaged(void),
    /// Sources that have been loaded (kept alive for slices in Jakefile)
    loaded_sources: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator) ImportResolver {
        return .{
            .allocator = allocator,
            .import_stack = .{},
            .resolved_cache = .{},
            .loaded_sources = .{},
        };
    }

    pub fn deinit(self: *ImportResolver) void {
        self.import_stack.deinit(self.allocator);
        self.resolved_cache.deinit(self.allocator);
        for (self.loaded_sources.items) |source| {
            self.allocator.free(source);
        }
        self.loaded_sources.deinit(self.allocator);
    }

    /// Resolve all imports for a Jakefile, merging imported content into it.
    /// The base_path is the directory containing the Jakefile being processed.
    pub fn resolveImports(
        self: *ImportResolver,
        jakefile: *Jakefile,
        base_path: []const u8,
    ) ImportError!void {
        // Process each import directive
        for (jakefile.imports) |import_directive| {
            try self.processImport(jakefile, import_directive, base_path);
        }
    }

    /// Process a single import directive
    fn processImport(
        self: *ImportResolver,
        target: *Jakefile,
        import_directive: ImportDirective,
        base_path: []const u8,
    ) ImportError!void {
        // Resolve the import path relative to base_path
        const resolved_path = try self.resolvePath(import_directive.path, base_path);
        defer self.allocator.free(resolved_path);

        // Check for circular imports
        if (self.import_stack.contains(resolved_path)) {
            return ImportError.CircularImport;
        }

        // Check if already processed
        if (self.resolved_cache.contains(resolved_path)) {
            return; // Already imported, skip
        }

        // Mark as in-progress
        self.import_stack.put(self.allocator, try self.allocator.dupe(u8, resolved_path), {}) catch return ImportError.OutOfMemory;

        // Load and parse the imported file
        var imported = self.loadAndParse(resolved_path) catch |err| {
            // Clean up the import stack entry on error
            _ = self.import_stack.remove(resolved_path);
            return err;
        };

        // Get the directory of the imported file for resolving its imports
        const import_base = std.fs.path.dirname(resolved_path) orelse ".";

        // Recursively resolve imports in the imported file
        self.resolveImports(&imported, import_base) catch |err| {
            _ = self.import_stack.remove(resolved_path);
            return err;
        };

        // Merge the imported content into target
        self.mergeJakefile(target, imported, import_directive.prefix) catch |err| {
            _ = self.import_stack.remove(resolved_path);
            return err;
        };

        // Remove from in-progress, add to resolved cache
        _ = self.import_stack.remove(resolved_path);
        self.resolved_cache.put(self.allocator, try self.allocator.dupe(u8, resolved_path), {}) catch return ImportError.OutOfMemory;
    }

    /// Resolve a potentially relative path to an absolute path
    fn resolvePath(self: *ImportResolver, path: []const u8, base_path: []const u8) ImportError![]const u8 {
        // If path is absolute, use it directly
        if (std.fs.path.isAbsolute(path)) {
            return self.allocator.dupe(u8, path) catch return ImportError.OutOfMemory;
        }

        // Otherwise, join with base_path
        const joined = std.fs.path.join(self.allocator, &[_][]const u8{ base_path, path }) catch return ImportError.OutOfMemory;
        errdefer self.allocator.free(joined);

        // Resolve to real path (handles .., symlinks, etc.)
        const real_path = std.fs.cwd().realpathAlloc(self.allocator, joined) catch |err| {
            return switch (err) {
                error.FileNotFound => ImportError.FileNotFound,
                error.AccessDenied => ImportError.AccessDenied,
                else => ImportError.InvalidPath,
            };
        };
        self.allocator.free(joined);

        return real_path;
    }

    /// Load a file and parse it as a Jakefile
    fn loadAndParse(self: *ImportResolver, path: []const u8) ImportError!Jakefile {
        // Open and read file
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound => ImportError.FileNotFound,
                error.AccessDenied => ImportError.AccessDenied,
                else => ImportError.Unexpected,
            };
        };
        defer file.close();

        const source = file.readToEndAlloc(self.allocator, 1024 * 1024) catch return ImportError.OutOfMemory;
        // Keep source alive
        self.loaded_sources.append(self.allocator, source) catch return ImportError.OutOfMemory;

        // Parse
        var lex = Lexer.init(source);
        var p = Parser.init(self.allocator, &lex);
        return p.parseJakefile() catch return ImportError.ParseError;
    }

    /// Merge an imported Jakefile into the target, optionally with a prefix
    fn mergeJakefile(
        self: *ImportResolver,
        target: *Jakefile,
        imported: Jakefile,
        prefix: ?[]const u8,
    ) ImportError!void {
        // Merge variables (no prefix on variables)
        const new_vars_len = target.variables.len + imported.variables.len;
        const new_vars = self.allocator.alloc(Variable, new_vars_len) catch return ImportError.OutOfMemory;
        @memcpy(new_vars[0..target.variables.len], target.variables);
        @memcpy(new_vars[target.variables.len..], imported.variables);
        // Note: We don't free the old slice as it may still be referenced

        // Merge recipes (with optional prefix)
        const new_recipes_len = target.recipes.len + imported.recipes.len;
        const new_recipes = self.allocator.alloc(Recipe, new_recipes_len) catch return ImportError.OutOfMemory;
        @memcpy(new_recipes[0..target.recipes.len], target.recipes);

        for (imported.recipes, 0..) |recipe, i| {
            var new_recipe = recipe;
            if (prefix) |p| {
                // Create prefixed name: "prefix.recipe_name"
                new_recipe.name = self.createPrefixedName(p, recipe.name) catch return ImportError.OutOfMemory;

                // Also prefix dependencies that point to imported recipes
                if (recipe.dependencies.len > 0) {
                    const new_deps = self.allocator.alloc([]const u8, recipe.dependencies.len) catch return ImportError.OutOfMemory;
                    for (recipe.dependencies, 0..) |dep, j| {
                        // Check if this dependency is from the imported file
                        if (self.isImportedRecipe(imported.recipes, dep)) {
                            new_deps[j] = self.createPrefixedName(p, dep) catch return ImportError.OutOfMemory;
                        } else {
                            new_deps[j] = dep;
                        }
                    }
                    new_recipe.dependencies = new_deps;
                }
            }
            // Don't carry over is_default from imported files
            new_recipe.is_default = false;
            new_recipes[target.recipes.len + i] = new_recipe;
        }

        // Merge directives (skip import directives from imported file)
        var directive_count: usize = 0;
        for (imported.directives) |d| {
            if (d.kind != .import) {
                directive_count += 1;
            }
        }
        const new_directives_len = target.directives.len + directive_count;
        const new_directives = self.allocator.alloc(Directive, new_directives_len) catch return ImportError.OutOfMemory;
        @memcpy(new_directives[0..target.directives.len], target.directives);
        var idx: usize = target.directives.len;
        for (imported.directives) |d| {
            if (d.kind != .import) {
                new_directives[idx] = d;
                idx += 1;
            }
        }

        // Merge global hooks
        const new_pre_hooks_len = target.global_pre_hooks.len + imported.global_pre_hooks.len;
        const new_pre_hooks = self.allocator.alloc(Hook, new_pre_hooks_len) catch return ImportError.OutOfMemory;
        @memcpy(new_pre_hooks[0..target.global_pre_hooks.len], target.global_pre_hooks);
        @memcpy(new_pre_hooks[target.global_pre_hooks.len..], imported.global_pre_hooks);

        const new_post_hooks_len = target.global_post_hooks.len + imported.global_post_hooks.len;
        const new_post_hooks = self.allocator.alloc(Hook, new_post_hooks_len) catch return ImportError.OutOfMemory;
        @memcpy(new_post_hooks[0..target.global_post_hooks.len], target.global_post_hooks);
        @memcpy(new_post_hooks[target.global_post_hooks.len..], imported.global_post_hooks);

        // Update target with merged content
        target.variables = new_vars;
        target.recipes = new_recipes;
        target.directives = new_directives;
        target.global_pre_hooks = new_pre_hooks;
        target.global_post_hooks = new_post_hooks;
    }

    /// Create a prefixed name like "prefix.name"
    fn createPrefixedName(self: *ImportResolver, prefix: []const u8, name: []const u8) ![]const u8 {
        const prefixed = self.allocator.alloc(u8, prefix.len + 1 + name.len) catch return ImportError.OutOfMemory;
        @memcpy(prefixed[0..prefix.len], prefix);
        prefixed[prefix.len] = '.';
        @memcpy(prefixed[prefix.len + 1 ..], name);
        return prefixed;
    }

    /// Check if a dependency name refers to a recipe in the given list
    fn isImportedRecipe(self: *ImportResolver, recipes: []const Recipe, dep_name: []const u8) bool {
        _ = self;
        for (recipes) |recipe| {
            if (std.mem.eql(u8, recipe.name, dep_name)) {
                return true;
            }
        }
        return false;
    }
};

/// Convenience function to resolve imports for a Jakefile
pub fn resolveImports(
    allocator: std.mem.Allocator,
    jakefile: *Jakefile,
    jakefile_path: []const u8,
) ImportError!void {
    var resolver = ImportResolver.init(allocator);
    // Note: We don't deinit the resolver since the sources need to stay alive
    // for the Jakefile slices. The caller is responsible for freeing memory
    // when done with the Jakefile.

    // Get the directory containing the jakefile
    const base_path = std.fs.path.dirname(jakefile_path) orelse ".";

    // Add the main jakefile to resolved cache to prevent self-import
    const real_path = std.fs.cwd().realpathAlloc(allocator, jakefile_path) catch {
        return resolver.resolveImports(jakefile, base_path);
    };
    resolver.resolved_cache.put(allocator, real_path, {}) catch return ImportError.OutOfMemory;

    return resolver.resolveImports(jakefile, base_path);
}

test "import resolver init" {
    var resolver = ImportResolver.init(std.testing.allocator);
    defer resolver.deinit();

    try std.testing.expectEqual(@as(usize, 0), resolver.import_stack.count());
    try std.testing.expectEqual(@as(usize, 0), resolver.resolved_cache.count());
}

test "prefixed name creation" {
    var resolver = ImportResolver.init(std.testing.allocator);
    defer resolver.deinit();

    const prefixed = try resolver.createPrefixedName("docker", "build");
    defer std.testing.allocator.free(prefixed);

    try std.testing.expectEqualStrings("docker.build", prefixed);
}
