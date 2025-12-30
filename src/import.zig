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
const NeedsRequirement = parser_mod.NeedsRequirement;
const RecipeOrigin = parser_mod.RecipeOrigin;
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

/// Allocations that persist after import resolution.
/// The caller must call deinit() when the Jakefile is no longer needed.
pub const ImportAllocations = struct {
    sources: []const []const u8,
    names: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ImportAllocations) void {
        for (self.sources) |source| {
            self.allocator.free(source);
        }
        self.allocator.free(self.sources);
        for (self.names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.names);
    }
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
    /// Prefixed names that have been allocated (need to outlive resolver)
    allocated_names: std.ArrayListUnmanaged([]const u8),
    /// Old slices that were replaced during merging (to be freed)
    replaced_slices: struct {
        variables: std.ArrayListUnmanaged([]const Variable),
        recipes: std.ArrayListUnmanaged([]const Recipe),
        directives: std.ArrayListUnmanaged([]const Directive),
        pre_hooks: std.ArrayListUnmanaged([]const Hook),
        post_hooks: std.ArrayListUnmanaged([]const Hook),
        on_error_hooks: std.ArrayListUnmanaged([]const Hook),
        dependencies: std.ArrayListUnmanaged([]const []const u8),
        needs: std.ArrayListUnmanaged([]const NeedsRequirement),
        imports: std.ArrayListUnmanaged([]const ImportDirective),
    },

    pub fn init(allocator: std.mem.Allocator) ImportResolver {
        return .{
            .allocator = allocator,
            .import_stack = .{},
            .resolved_cache = .{},
            .loaded_sources = .{},
            .allocated_names = .{},
            .replaced_slices = .{
                .variables = .{},
                .recipes = .{},
                .directives = .{},
                .pre_hooks = .{},
                .post_hooks = .{},
                .on_error_hooks = .{},
                .dependencies = .{},
                .needs = .{},
                .imports = .{},
            },
        };
    }

    pub fn deinit(self: *ImportResolver) void {
        // Free import_stack keys (duplicated path strings)
        var stack_it = self.import_stack.keyIterator();
        while (stack_it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.import_stack.deinit(self.allocator);

        // Free resolved_cache keys (duplicated path strings)
        var cache_it = self.resolved_cache.keyIterator();
        while (cache_it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.resolved_cache.deinit(self.allocator);

        // Free all replaced slices that were orphaned during merging
        for (self.replaced_slices.variables.items) |slice| {
            self.allocator.free(slice);
        }
        self.replaced_slices.variables.deinit(self.allocator);

        // Only free the outer slices, not the inner content of recipes.
        // The inner content (dependencies, commands, etc.) is shallow-copied
        // to the new merged slices and still in use.
        for (self.replaced_slices.recipes.items) |slice| {
            self.allocator.free(slice);
        }
        self.replaced_slices.recipes.deinit(self.allocator);

        // Same for directives - only free the outer slice
        for (self.replaced_slices.directives.items) |slice| {
            self.allocator.free(slice);
        }
        self.replaced_slices.directives.deinit(self.allocator);

        for (self.replaced_slices.pre_hooks.items) |slice| {
            self.allocator.free(slice);
        }
        self.replaced_slices.pre_hooks.deinit(self.allocator);

        for (self.replaced_slices.post_hooks.items) |slice| {
            self.allocator.free(slice);
        }
        self.replaced_slices.post_hooks.deinit(self.allocator);

        for (self.replaced_slices.on_error_hooks.items) |slice| {
            self.allocator.free(slice);
        }
        self.replaced_slices.on_error_hooks.deinit(self.allocator);

        for (self.replaced_slices.dependencies.items) |slice| {
            self.allocator.free(slice);
        }
        self.replaced_slices.dependencies.deinit(self.allocator);

        // Note: needs slices are NOT freed here - they are managed by jakefile.deinit()
        self.replaced_slices.needs.deinit(self.allocator);

        for (self.replaced_slices.imports.items) |slice| {
            self.allocator.free(slice);
        }
        self.replaced_slices.imports.deinit(self.allocator);

        // Free loaded_sources and allocated_names if they weren't extracted.
        // After extractPersistentAllocations(), these arrays will be empty.
        // On error paths, they may still contain data that needs to be freed.
        for (self.loaded_sources.items) |source| {
            self.allocator.free(source);
        }
        self.loaded_sources.deinit(self.allocator);

        for (self.allocated_names.items) |name| {
            self.allocator.free(name);
        }
        self.allocated_names.deinit(self.allocator);
    }

    /// Extract allocations that must persist after the resolver is deinitialized.
    /// The caller is responsible for freeing these when the Jakefile is no longer needed.
    pub fn extractPersistentAllocations(self: *ImportResolver) ImportAllocations {
        const allocations = ImportAllocations{
            .sources = self.loaded_sources.toOwnedSlice(self.allocator) catch &.{},
            .names = self.allocated_names.toOwnedSlice(self.allocator) catch &.{},
            .allocator = self.allocator,
        };
        return allocations;
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
            // Clean up the import stack entry on error (free the duplicated key)
            if (self.import_stack.fetchRemove(resolved_path)) |entry| {
                self.allocator.free(entry.key);
            }
            return err;
        };

        // Get the directory of the imported file for resolving its imports
        const import_base = std.fs.path.dirname(resolved_path) orelse ".";

        // Recursively resolve imports in the imported file
        self.resolveImports(&imported, import_base) catch |err| {
            imported.deinit(self.allocator); // Free the imported jakefile on error
            if (self.import_stack.fetchRemove(resolved_path)) |entry| {
                self.allocator.free(entry.key);
            }
            return err;
        };

        // Merge the imported content into target
        self.mergeJakefile(target, imported, import_directive.prefix, resolved_path) catch |err| {
            imported.deinit(self.allocator); // Free the imported jakefile on error
            if (self.import_stack.fetchRemove(resolved_path)) |entry| {
                self.allocator.free(entry.key);
            }
            return err;
        };

        // Remove from in-progress (free the duplicated key), add to resolved cache
        if (self.import_stack.fetchRemove(resolved_path)) |entry| {
            self.allocator.free(entry.key);
        }
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
        source_file: []const u8,
    ) ImportError!void {
        // Track old slices from target that will be replaced (only if they have content)
        // These will be freed when the resolver is deinitialized
        if (target.variables.len > 0) {
            self.replaced_slices.variables.append(self.allocator, target.variables) catch return ImportError.OutOfMemory;
        }
        if (target.recipes.len > 0) {
            self.replaced_slices.recipes.append(self.allocator, target.recipes) catch return ImportError.OutOfMemory;
        }
        if (target.directives.len > 0) {
            self.replaced_slices.directives.append(self.allocator, target.directives) catch return ImportError.OutOfMemory;
        }
        if (target.global_pre_hooks.len > 0) {
            self.replaced_slices.pre_hooks.append(self.allocator, target.global_pre_hooks) catch return ImportError.OutOfMemory;
        }
        if (target.global_post_hooks.len > 0) {
            self.replaced_slices.post_hooks.append(self.allocator, target.global_post_hooks) catch return ImportError.OutOfMemory;
        }
        if (target.global_on_error_hooks.len > 0) {
            self.replaced_slices.on_error_hooks.append(self.allocator, target.global_on_error_hooks) catch return ImportError.OutOfMemory;
        }

        // Also track the imported jakefile's slices (they'll be orphaned after merge)
        if (imported.variables.len > 0) {
            self.replaced_slices.variables.append(self.allocator, imported.variables) catch return ImportError.OutOfMemory;
        }
        if (imported.recipes.len > 0) {
            self.replaced_slices.recipes.append(self.allocator, imported.recipes) catch return ImportError.OutOfMemory;
        }
        if (imported.directives.len > 0) {
            self.replaced_slices.directives.append(self.allocator, imported.directives) catch return ImportError.OutOfMemory;
        }
        if (imported.global_pre_hooks.len > 0) {
            self.replaced_slices.pre_hooks.append(self.allocator, imported.global_pre_hooks) catch return ImportError.OutOfMemory;
        }
        if (imported.global_post_hooks.len > 0) {
            self.replaced_slices.post_hooks.append(self.allocator, imported.global_post_hooks) catch return ImportError.OutOfMemory;
        }
        if (imported.global_on_error_hooks.len > 0) {
            self.replaced_slices.on_error_hooks.append(self.allocator, imported.global_on_error_hooks) catch return ImportError.OutOfMemory;
        }
        // Track imported file's imports slice (they've already been processed)
        if (imported.imports.len > 0) {
            self.replaced_slices.imports.append(self.allocator, imported.imports) catch return ImportError.OutOfMemory;
        }

        // Note: We intentionally do NOT track needs slices in replaced_slices.
        // The needs arrays are shallow-copied when recipes are merged, and
        // jakefile.deinit() will free them via allocator.free(recipe.needs).

        // Merge variables (no prefix on variables)
        const new_vars_len = target.variables.len + imported.variables.len;
        const new_vars = self.allocator.alloc(Variable, new_vars_len) catch return ImportError.OutOfMemory;
        @memcpy(new_vars[0..target.variables.len], target.variables);
        @memcpy(new_vars[target.variables.len..], imported.variables);

        // Merge recipes (with optional prefix)
        const new_recipes_len = target.recipes.len + imported.recipes.len;
        const new_recipes = self.allocator.alloc(Recipe, new_recipes_len) catch return ImportError.OutOfMemory;
        @memcpy(new_recipes[0..target.recipes.len], target.recipes);

        for (imported.recipes, 0..) |recipe, i| {
            var new_recipe = recipe;
            if (prefix) |p| {
                // Create prefixed name: "prefix.recipe_name"
                const prefixed_name = self.createPrefixedName(p, recipe.name) catch return ImportError.OutOfMemory;
                // Track the allocated name so it can be freed later
                self.allocated_names.append(self.allocator, prefixed_name) catch return ImportError.OutOfMemory;
                new_recipe.name = prefixed_name;

                // Set origin to track where this recipe came from
                new_recipe.origin = .{
                    .original_name = recipe.name,
                    .import_prefix = p,
                    .source_file = source_file,
                };

                // Also prefix dependencies that point to imported recipes
                if (recipe.dependencies.len > 0) {
                    // Track the original dependencies slice before replacing it
                    self.replaced_slices.dependencies.append(self.allocator, recipe.dependencies) catch return ImportError.OutOfMemory;

                    const new_deps = self.allocator.alloc([]const u8, recipe.dependencies.len) catch return ImportError.OutOfMemory;
                    for (recipe.dependencies, 0..) |dep, j| {
                        // Check if this dependency is from the imported file
                        if (self.isImportedRecipe(imported.recipes, dep)) {
                            const prefixed_dep = self.createPrefixedName(p, dep) catch return ImportError.OutOfMemory;
                            self.allocated_names.append(self.allocator, prefixed_dep) catch return ImportError.OutOfMemory;
                            new_deps[j] = prefixed_dep;
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

        // Merge directives (import directives are stored separately in imports array)
        const new_directives_len = target.directives.len + imported.directives.len;
        const new_directives = self.allocator.alloc(Directive, new_directives_len) catch return ImportError.OutOfMemory;
        @memcpy(new_directives[0..target.directives.len], target.directives);
        @memcpy(new_directives[target.directives.len..], imported.directives);

        // Merge global hooks
        const new_pre_hooks_len = target.global_pre_hooks.len + imported.global_pre_hooks.len;
        const new_pre_hooks = self.allocator.alloc(Hook, new_pre_hooks_len) catch return ImportError.OutOfMemory;
        @memcpy(new_pre_hooks[0..target.global_pre_hooks.len], target.global_pre_hooks);
        @memcpy(new_pre_hooks[target.global_pre_hooks.len..], imported.global_pre_hooks);

        const new_post_hooks_len = target.global_post_hooks.len + imported.global_post_hooks.len;
        const new_post_hooks = self.allocator.alloc(Hook, new_post_hooks_len) catch return ImportError.OutOfMemory;
        @memcpy(new_post_hooks[0..target.global_post_hooks.len], target.global_post_hooks);
        @memcpy(new_post_hooks[target.global_post_hooks.len..], imported.global_post_hooks);

        const new_on_error_hooks_len = target.global_on_error_hooks.len + imported.global_on_error_hooks.len;
        const new_on_error_hooks = self.allocator.alloc(Hook, new_on_error_hooks_len) catch return ImportError.OutOfMemory;
        @memcpy(new_on_error_hooks[0..target.global_on_error_hooks.len], target.global_on_error_hooks);
        @memcpy(new_on_error_hooks[target.global_on_error_hooks.len..], imported.global_on_error_hooks);

        // Update target with merged content
        target.variables = new_vars;
        target.recipes = new_recipes;
        target.directives = new_directives;
        target.global_pre_hooks = new_pre_hooks;
        target.global_post_hooks = new_post_hooks;
        target.global_on_error_hooks = new_on_error_hooks;
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

/// Convenience function to resolve imports for a Jakefile.
/// Returns allocations that must be freed when the Jakefile is no longer needed.
pub fn resolveImports(
    allocator: std.mem.Allocator,
    jakefile: *Jakefile,
    jakefile_path: []const u8,
) ImportError!ImportAllocations {
    var resolver = ImportResolver.init(allocator);
    errdefer resolver.deinit();

    // Get the directory containing the jakefile
    const base_path = std.fs.path.dirname(jakefile_path) orelse ".";

    // Add the main jakefile to import_stack for cycle detection
    const real_path = std.fs.cwd().realpathAlloc(allocator, jakefile_path) catch {
        try resolver.resolveImports(jakefile, base_path);
        const allocations = resolver.extractPersistentAllocations();
        resolver.deinit();
        return allocations;
    };
    // Add to import_stack (not resolved_cache) so that circular imports are detected
    resolver.import_stack.put(allocator, real_path, {}) catch return ImportError.OutOfMemory;

    try resolver.resolveImports(jakefile, base_path);

    // Move from import_stack to resolved_cache after successful processing
    _ = resolver.import_stack.remove(real_path);
    resolver.resolved_cache.put(allocator, real_path, {}) catch return ImportError.OutOfMemory;
    const allocations = resolver.extractPersistentAllocations();
    resolver.deinit();
    return allocations;
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

test "prefixed name with multi-char prefix" {
    var resolver = ImportResolver.init(std.testing.allocator);
    defer resolver.deinit();

    const prefixed = try resolver.createPrefixedName("deployment", "production");
    defer std.testing.allocator.free(prefixed);

    try std.testing.expectEqualStrings("deployment.production", prefixed);
}

test "isImportedRecipe finds matching recipe" {
    var resolver = ImportResolver.init(std.testing.allocator);
    defer resolver.deinit();

    const recipes = [_]Recipe{
        .{
            .name = "build",
            .loc = .{ .start = 0, .end = 0, .line = 1, .column = 1 },
            .origin = null,
            .kind = .task,
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
            .only_os = &.{},
            .shell = null,
            .working_dir = null,
            .quiet = false,
            .needs = &.{},
        },
        .{
            .name = "test",
            .loc = .{ .start = 0, .end = 0, .line = 1, .column = 1 },
            .origin = null,
            .kind = .task,
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
            .only_os = &.{},
            .shell = null,
            .working_dir = null,
            .quiet = false,
            .needs = &.{},
        },
    };

    try std.testing.expect(resolver.isImportedRecipe(&recipes, "build"));
    try std.testing.expect(resolver.isImportedRecipe(&recipes, "test"));
    try std.testing.expect(!resolver.isImportedRecipe(&recipes, "deploy"));
}

test "isImportedRecipe returns false for empty recipe list" {
    var resolver = ImportResolver.init(std.testing.allocator);
    defer resolver.deinit();

    const recipes: []const Recipe = &.{};
    try std.testing.expect(!resolver.isImportedRecipe(recipes, "anything"));
}

test "import stack tracks in-progress imports" {
    var resolver = ImportResolver.init(std.testing.allocator);
    defer resolver.deinit();

    // Simulate adding to import stack - deinit() will free the key
    try resolver.import_stack.put(std.testing.allocator, try std.testing.allocator.dupe(u8, "/path/to/file.jake"), {});

    try std.testing.expect(resolver.import_stack.contains("/path/to/file.jake"));
    try std.testing.expect(!resolver.import_stack.contains("/other/file.jake"));
}

test "resolved cache prevents re-processing" {
    var resolver = ImportResolver.init(std.testing.allocator);
    defer resolver.deinit();

    // Simulate adding to resolved cache - deinit() will free the key
    try resolver.resolved_cache.put(std.testing.allocator, try std.testing.allocator.dupe(u8, "/resolved/file.jake"), {});

    try std.testing.expect(resolver.resolved_cache.contains("/resolved/file.jake"));
    try std.testing.expectEqual(@as(usize, 1), resolver.resolved_cache.count());
}

test "loaded sources are tracked for cleanup" {
    var resolver = ImportResolver.init(std.testing.allocator);

    // Simulate adding loaded sources
    const source1 = try std.testing.allocator.dupe(u8, "task build:\n    echo hello");
    try resolver.loaded_sources.append(std.testing.allocator, source1);

    const source2 = try std.testing.allocator.dupe(u8, "task test:\n    echo test");
    try resolver.loaded_sources.append(std.testing.allocator, source2);

    try std.testing.expectEqual(@as(usize, 2), resolver.loaded_sources.items.len);

    // Extract allocations and then free them (this is the proper cleanup pattern)
    var allocs = resolver.extractPersistentAllocations();
    resolver.deinit();
    allocs.deinit();
}

test "import resolution cleans up all memory" {
    // This test exercises the full import pipeline and checks for memory leaks.
    // It creates temporary jake files, parses and resolves imports, then cleans up.
    // The testing allocator will fail if any memory is leaked.
    const allocator = std.testing.allocator;

    // Create a temporary directory for test files
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Write the imported file
    const imported_content = "task helper:\n    echo \"helper task\"\n\ntask util:\n    echo \"util task\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "imported.jake", .data = imported_content });

    // Write the main file with an import
    const main_content = "@import \"imported.jake\" as lib\n\ntask main:\n    echo \"main task\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "main.jake", .data = main_content });

    // Get the full path to main.jake
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const main_path = try tmp_dir.dir.realpath("main.jake", &path_buf);

    // Read and parse the main file
    const main_source = try tmp_dir.dir.readFileAlloc(allocator, "main.jake", 1024 * 1024);
    defer allocator.free(main_source);

    var lex = Lexer.init(main_source);
    var p = Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    // Verify we have the import directive
    try std.testing.expectEqual(@as(usize, 1), jakefile.imports.len);
    try std.testing.expectEqualStrings("imported.jake", jakefile.imports[0].path);
    try std.testing.expectEqualStrings("lib", jakefile.imports[0].prefix.?);

    // Resolve imports - this should not leak memory
    var import_allocs = try resolveImports(allocator, &jakefile, main_path);
    defer import_allocs.deinit();

    // Verify the imports were merged correctly
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes.len);

    // Find each recipe by name
    var found_main = false;
    var found_lib_helper = false;
    var found_lib_util = false;
    for (jakefile.recipes) |recipe| {
        if (std.mem.eql(u8, recipe.name, "main")) found_main = true;
        if (std.mem.eql(u8, recipe.name, "lib.helper")) found_lib_helper = true;
        if (std.mem.eql(u8, recipe.name, "lib.util")) found_lib_util = true;
    }

    try std.testing.expect(found_main);
    try std.testing.expect(found_lib_helper);
    try std.testing.expect(found_lib_util);
}

test "import resolution cleans up needs arrays from imported recipes" {
    // This test verifies that @needs arrays from imported recipes are properly freed.
    // Without proper tracking, the needs slices would leak memory.
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Imported file with @needs directive - this allocates a needs array during parsing
    const imported_content =
        \\@needs git
        \\task deploy:
        \\    echo "deploying"
        \\
        \\@needs docker
        \\@needs kubectl "Install kubectl"
        \\task k8s:
        \\    echo "kubernetes"
        \\
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "imported.jake", .data = imported_content });

    const main_content = "@import \"imported.jake\" as lib\n\ntask main:\n    echo \"main\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "main.jake", .data = main_content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const main_path = try tmp_dir.dir.realpath("main.jake", &path_buf);

    const main_source = try tmp_dir.dir.readFileAlloc(allocator, "main.jake", 1024 * 1024);
    defer allocator.free(main_source);

    var lex = Lexer.init(main_source);
    var p = Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    // Resolve imports - the testing allocator will fail if needs arrays leak
    var import_allocs = try resolveImports(allocator, &jakefile, main_path);
    defer import_allocs.deinit();

    // Verify recipes were merged
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes.len);

    // Verify the imported recipes have their needs
    for (jakefile.recipes) |recipe| {
        if (std.mem.eql(u8, recipe.name, "lib.deploy")) {
            try std.testing.expectEqual(@as(usize, 1), recipe.needs.len);
            try std.testing.expectEqualStrings("git", recipe.needs[0].command);
        }
        if (std.mem.eql(u8, recipe.name, "lib.k8s")) {
            try std.testing.expectEqual(@as(usize, 2), recipe.needs.len);
        }
    }
}

test "import sets origin for prefixed recipes with private detection" {
    // This test verifies that:
    // 1. RecipeOrigin is set correctly for imported recipes
    // 2. Private recipes (starting with _) can be detected via origin.original_name
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Imported file with a private helper task
    const imported_content =
        \\task build:
        \\    echo "building"
        \\
        \\task _helper:
        \\    echo "private helper"
        \\
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "imported.jake", .data = imported_content });

    const main_content = "@import \"imported.jake\" as lib\n\ntask main:\n    echo \"main\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "main.jake", .data = main_content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const main_path = try tmp_dir.dir.realpath("main.jake", &path_buf);

    const main_source = try tmp_dir.dir.readFileAlloc(allocator, "main.jake", 1024 * 1024);
    defer allocator.free(main_source);

    var lex = Lexer.init(main_source);
    var p = Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var import_allocs = try resolveImports(allocator, &jakefile, main_path);
    defer import_allocs.deinit();

    // Verify recipes were merged (main + lib.build + lib._helper)
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes.len);

    // Verify origin tracking for imported recipes
    for (jakefile.recipes) |recipe| {
        if (std.mem.eql(u8, recipe.name, "main")) {
            // Main recipe should have no origin
            try std.testing.expect(recipe.origin == null);
        }
        if (std.mem.eql(u8, recipe.name, "lib.build")) {
            // Should have origin with original_name = "build"
            try std.testing.expect(recipe.origin != null);
            const origin = recipe.origin.?;
            try std.testing.expectEqualStrings("build", origin.original_name);
            try std.testing.expectEqualStrings("lib", origin.import_prefix.?);
            try std.testing.expect(origin.source_file != null);
        }
        if (std.mem.eql(u8, recipe.name, "lib._helper")) {
            // Should have origin with original_name = "_helper" (private)
            try std.testing.expect(recipe.origin != null);
            const origin = recipe.origin.?;
            try std.testing.expectEqualStrings("_helper", origin.original_name);
            // Verify we can detect it's private from original_name
            try std.testing.expect(origin.original_name[0] == '_');
        }
    }
}

test "import without prefix merges recipes without prefixing" {
    // Test that @import "file.jake" (without "as prefix") merges recipes unprefixed
    // and does NOT set origin (since names aren't changed)
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const imported_content =
        \\task helper:
        \\    echo "helper"
        \\
        \\task _private:
        \\    echo "private"
        \\
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "imported.jake", .data = imported_content });

    // Import WITHOUT "as prefix"
    const main_content = "@import \"imported.jake\"\n\ntask main:\n    echo \"main\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "main.jake", .data = main_content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const main_path = try tmp_dir.dir.realpath("main.jake", &path_buf);

    const main_source = try tmp_dir.dir.readFileAlloc(allocator, "main.jake", 1024 * 1024);
    defer allocator.free(main_source);

    var lex = Lexer.init(main_source);
    var p = Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var import_allocs = try resolveImports(allocator, &jakefile, main_path);
    defer import_allocs.deinit();

    // Should have 3 recipes: main, helper, _private (unprefixed)
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes.len);

    // Verify recipes are NOT prefixed
    var found_main = false;
    var found_helper = false;
    var found_private = false;
    for (jakefile.recipes) |recipe| {
        if (std.mem.eql(u8, recipe.name, "main")) {
            found_main = true;
            try std.testing.expect(recipe.origin == null);
        }
        if (std.mem.eql(u8, recipe.name, "helper")) {
            found_helper = true;
            // Without prefix, origin should still be null (no name change)
            try std.testing.expect(recipe.origin == null);
        }
        if (std.mem.eql(u8, recipe.name, "_private")) {
            found_private = true;
            try std.testing.expect(recipe.origin == null);
        }
    }
    try std.testing.expect(found_main);
    try std.testing.expect(found_helper);
    try std.testing.expect(found_private);
}

test "multiple imports with different prefixes" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // First imported file
    const lib1_content = "task build:\n    echo \"lib1 build\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "lib1.jake", .data = lib1_content });

    // Second imported file
    const lib2_content = "task build:\n    echo \"lib2 build\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "lib2.jake", .data = lib2_content });

    // Main file imports both with different prefixes
    const main_content =
        \\@import "lib1.jake" as a
        \\@import "lib2.jake" as b
        \\
        \\task main:
        \\    echo "main"
        \\
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "main.jake", .data = main_content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const main_path = try tmp_dir.dir.realpath("main.jake", &path_buf);

    const main_source = try tmp_dir.dir.readFileAlloc(allocator, "main.jake", 1024 * 1024);
    defer allocator.free(main_source);

    var lex = Lexer.init(main_source);
    var p = Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var import_allocs = try resolveImports(allocator, &jakefile, main_path);
    defer import_allocs.deinit();

    // Should have 3 recipes: main, a.build, b.build
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes.len);

    var found_main = false;
    var found_a_build = false;
    var found_b_build = false;
    for (jakefile.recipes) |recipe| {
        if (std.mem.eql(u8, recipe.name, "main")) {
            found_main = true;
        }
        if (std.mem.eql(u8, recipe.name, "a.build")) {
            found_a_build = true;
            try std.testing.expect(recipe.origin != null);
            try std.testing.expectEqualStrings("build", recipe.origin.?.original_name);
            try std.testing.expectEqualStrings("a", recipe.origin.?.import_prefix.?);
        }
        if (std.mem.eql(u8, recipe.name, "b.build")) {
            found_b_build = true;
            try std.testing.expect(recipe.origin != null);
            try std.testing.expectEqualStrings("build", recipe.origin.?.original_name);
            try std.testing.expectEqualStrings("b", recipe.origin.?.import_prefix.?);
        }
    }
    try std.testing.expect(found_main);
    try std.testing.expect(found_a_build);
    try std.testing.expect(found_b_build);
}

test "nested imports 2 levels deep with prefixes" {
    // Test: main.jake imports lib.jake (as lib), lib.jake imports util.jake (as util)
    // Result: main has recipes: main, lib.build, lib.util.helper
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Deepest level - util.jake
    const util_content =
        \\task helper:
        \\    echo "util helper"
        \\
        \\task _private_util:
        \\    echo "private util"
        \\
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "util.jake", .data = util_content });

    // Middle level - lib.jake imports util
    const lib_content =
        \\@import "util.jake" as util
        \\
        \\task build:
        \\    echo "lib build"
        \\
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "lib.jake", .data = lib_content });

    // Top level - main.jake imports lib
    const main_content =
        \\@import "lib.jake" as lib
        \\
        \\task main:
        \\    echo "main"
        \\
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "main.jake", .data = main_content });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const main_path = try tmp_dir.dir.realpath("main.jake", &path_buf);

    const main_source = try tmp_dir.dir.readFileAlloc(allocator, "main.jake", 1024 * 1024);
    defer allocator.free(main_source);

    var lex = Lexer.init(main_source);
    var p = Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    var import_allocs = try resolveImports(allocator, &jakefile, main_path);
    defer import_allocs.deinit();

    // Should have: main, lib.build, lib.util.helper, lib.util._private_util
    try std.testing.expectEqual(@as(usize, 4), jakefile.recipes.len);

    var found_main = false;
    var found_lib_build = false;
    var found_lib_util_helper = false;
    var found_lib_util_private = false;

    for (jakefile.recipes) |recipe| {
        if (std.mem.eql(u8, recipe.name, "main")) {
            found_main = true;
            try std.testing.expect(recipe.origin == null);
        }
        if (std.mem.eql(u8, recipe.name, "lib.build")) {
            found_lib_build = true;
            try std.testing.expect(recipe.origin != null);
            try std.testing.expectEqualStrings("build", recipe.origin.?.original_name);
        }
        if (std.mem.eql(u8, recipe.name, "lib.util.helper")) {
            found_lib_util_helper = true;
            try std.testing.expect(recipe.origin != null);
            // The original name should be "util.helper" (from lib's perspective)
            try std.testing.expectEqualStrings("util.helper", recipe.origin.?.original_name);
        }
        if (std.mem.eql(u8, recipe.name, "lib.util._private_util")) {
            found_lib_util_private = true;
            try std.testing.expect(recipe.origin != null);
            // Original name preserves the nested structure
            try std.testing.expectEqualStrings("util._private_util", recipe.origin.?.original_name);
        }
    }

    try std.testing.expect(found_main);
    try std.testing.expect(found_lib_build);
    try std.testing.expect(found_lib_util_helper);
    try std.testing.expect(found_lib_util_private);
}

test "import detects direct circular dependency" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Write file A that imports file B
    const file_a = "@import \"b.jake\"\n\ntask a:\n    echo \"a\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "a.jake", .data = file_a });

    // Write file B that imports file A (circular!)
    const file_b = "@import \"a.jake\"\n\ntask b:\n    echo \"b\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "b.jake", .data = file_b });

    // Get the full path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const a_path = try tmp_dir.dir.realpath("a.jake", &path_buf);

    // Read and parse file A
    const source = try tmp_dir.dir.readFileAlloc(allocator, "a.jake", 1024 * 1024);
    defer allocator.free(source);

    var lex = Lexer.init(source);
    var p = Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    // Attempt to resolve imports - should detect circular dependency
    const result = resolveImports(allocator, &jakefile, a_path);
    try std.testing.expectError(ImportError.CircularImport, result);
}

test "import detects indirect circular dependency" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // A -> B -> C -> A (indirect cycle)
    const file_a = "@import \"b.jake\"\n\ntask a:\n    echo \"a\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "a.jake", .data = file_a });

    const file_b = "@import \"c.jake\"\n\ntask b:\n    echo \"b\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "b.jake", .data = file_b });

    const file_c = "@import \"a.jake\"\n\ntask c:\n    echo \"c\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "c.jake", .data = file_c });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const a_path = try tmp_dir.dir.realpath("a.jake", &path_buf);

    const source = try tmp_dir.dir.readFileAlloc(allocator, "a.jake", 1024 * 1024);
    defer allocator.free(source);

    var lex = Lexer.init(source);
    var p = Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    const result = resolveImports(allocator, &jakefile, a_path);
    try std.testing.expectError(ImportError.CircularImport, result);
}

test "import handles missing file gracefully" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // File that imports a non-existent file
    const file_a = "@import \"nonexistent.jake\"\n\ntask a:\n    echo \"a\"\n";
    try tmp_dir.dir.writeFile(.{ .sub_path = "a.jake", .data = file_a });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const a_path = try tmp_dir.dir.realpath("a.jake", &path_buf);

    const source = try tmp_dir.dir.readFileAlloc(allocator, "a.jake", 1024 * 1024);
    defer allocator.free(source);

    var lex = Lexer.init(source);
    var p = Parser.init(allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(allocator);

    const result = resolveImports(allocator, &jakefile, a_path);
    try std.testing.expectError(ImportError.FileNotFound, result);
}
