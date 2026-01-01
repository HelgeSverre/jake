const std = @import("std");
const parser = @import("parser.zig");

const DirectiveSlices = std.EnumArray(parser.Directive.Kind, []const *const parser.Directive);
const DirectiveListArray = std.EnumArray(parser.Directive.Kind, std.ArrayListUnmanaged(*const parser.Directive));
const directive_kinds = std.enums.values(parser.Directive.Kind);

pub const JakefileIndex = struct {
    allocator: std.mem.Allocator,
    jakefile: *const parser.Jakefile,
    recipes: std.StringHashMap(*const parser.Recipe),
    variables: std.StringHashMap([]const u8),
    directives: DirectiveSlices,
    default_recipe: ?*const parser.Recipe,

    pub fn build(allocator: std.mem.Allocator, jakefile: *const parser.Jakefile) !JakefileIndex {
        var index = JakefileIndex{
            .allocator = allocator,
            .jakefile = jakefile,
            .recipes = std.StringHashMap(*const parser.Recipe).init(allocator),
            .variables = std.StringHashMap([]const u8).init(allocator),
            .directives = DirectiveSlices.initFill(&.{}),
            .default_recipe = null,
        };
        errdefer index.deinit();

        try index.populate();
        return index;
    }

    fn populate(self: *JakefileIndex) !void {
        try self.populateRecipes();
        try self.populateVariables();
        try self.populateDirectives();
    }

    fn populateRecipes(self: *JakefileIndex) !void {
        for (self.jakefile.recipes) |*recipe| {
            try self.insertRecipeName(recipe.name, recipe);
            for (recipe.aliases) |alias| {
                try self.insertRecipeName(alias, recipe);
            }

            if (recipe.is_default and self.default_recipe == null) {
                self.default_recipe = recipe;
            }
        }

        if (self.default_recipe == null and self.jakefile.recipes.len > 0) {
            self.default_recipe = &self.jakefile.recipes[0];
        }
    }

    fn insertRecipeName(self: *JakefileIndex, name: []const u8, recipe: *const parser.Recipe) !void {
        if (self.recipes.get(name) != null) {
            return; // Preserve first definition behavior
        }
        try self.recipes.put(name, recipe);
    }

    fn populateVariables(self: *JakefileIndex) !void {
        for (self.jakefile.variables) |variable| {
            if (self.variables.contains(variable.name)) continue;
            try self.variables.put(variable.name, variable.value);
        }
    }

    fn populateDirectives(self: *JakefileIndex) !void {
        var lists = DirectiveListArray.initFill(std.ArrayListUnmanaged(*const parser.Directive).empty);
        errdefer {
            inline for (directive_kinds) |kind| {
                lists.getPtr(kind).deinit(self.allocator);
            }
        }

        for (self.jakefile.directives) |*directive| {
            lists.getPtr(directive.kind).append(self.allocator, directive) catch return error.OutOfMemory;
        }

        inline for (directive_kinds) |kind| {
            const slice = try lists.getPtr(kind).toOwnedSlice(self.allocator);
            self.directives.set(kind, slice);
        }
    }

    pub fn deinit(self: *JakefileIndex) void {
        self.recipes.deinit();
        self.variables.deinit();
        inline for (directive_kinds) |kind| {
            const slice = self.directives.get(kind);
            if (slice.len > 0) {
                self.allocator.free(slice);
            }
        }
    }

    pub fn getRecipe(self: *const JakefileIndex, name: []const u8) ?*const parser.Recipe {
        return self.recipes.get(name);
    }

    pub fn getVariable(self: *const JakefileIndex, name: []const u8) ?[]const u8 {
        return self.variables.get(name);
    }

    pub fn getDefaultRecipe(self: *const JakefileIndex) ?*const parser.Recipe {
        return self.default_recipe;
    }

    pub fn getDirectives(self: *const JakefileIndex, kind: parser.Directive.Kind) []const *const parser.Directive {
        return self.directives.get(kind);
    }

    pub fn variablesIterator(self: *const JakefileIndex) std.StringHashMap([]const u8).Iterator {
        return self.variables.iterator();
    }
};
