// Jake Parser - Builds AST from tokens

const std = @import("std");
const lexer = @import("lexer.zig");
const hooks_mod = @import("hooks.zig");
const Token = lexer.Token;
const Lexer = lexer.Lexer;
const Hook = hooks_mod.Hook;

pub const Recipe = struct {
    name: []const u8,
    kind: Kind,
    dependencies: []const []const u8,
    file_deps: []const []const u8, // File patterns for file targets
    output: ?[]const u8, // Output file for file targets
    params: []const Param,
    commands: []const Command,
    pre_hooks: []const Hook, // @pre commands to run before recipe
    post_hooks: []const Hook, // @post commands to run after recipe
    doc_comment: ?[]const u8,
    is_default: bool,
    aliases: []const []const u8, // Alternative names for this recipe
    group: ?[]const u8, // Recipe group/category for organization
    description: ?[]const u8, // Recipe description (distinct from doc_comment)
    shell: ?[]const u8, // Shell to use (e.g., "bash", "zsh", "powershell")
    working_dir: ?[]const u8, // Working directory for recipe execution
    only_os: []const []const u8, // List of OSes this recipe runs on (e.g., ["linux", "macos"])
    quiet: bool, // Suppress command echoing for this recipe

    pub const Kind = enum {
        task, // Always runs
        file, // Only runs if output is stale
        simple, // Basic recipe (like make target)
    };

    pub const Param = struct {
        name: []const u8,
        default: ?[]const u8,
    };

    pub const Command = struct {
        line: []const u8,
        directive: ?CommandDirective,
    };

    pub const CommandDirective = enum {
        cache,
        needs,
        confirm,
        watch,
        @"if",
        elif,
        @"else",
        end,
        each,
        ignore,
    };
};

pub const Variable = struct {
    name: []const u8,
    value: []const u8,
};

pub const Directive = struct {
    kind: Kind,
    args: []const []const u8,

    pub const Kind = enum {
        dotenv,
        require,
        @"export",
    };
};

/// Represents an @import directive with path and optional namespace prefix
pub const ImportDirective = struct {
    /// The path to the imported Jakefile (relative or absolute)
    path: []const u8,
    /// Optional namespace prefix (e.g., "docker" in `@import "docker.jake" as docker`)
    prefix: ?[]const u8,
};

pub const Jakefile = struct {
    variables: []const Variable,
    recipes: []const Recipe,
    directives: []const Directive,
    imports: []const ImportDirective,
    global_pre_hooks: []const Hook, // Global @pre hooks run before any recipe
    global_post_hooks: []const Hook, // Global @post hooks run after any recipe
    source: []const u8,

    pub fn deinit(self: *Jakefile, allocator: std.mem.Allocator) void {
        allocator.free(self.variables);
        for (self.recipes) |recipe| {
            allocator.free(recipe.dependencies);
            allocator.free(recipe.file_deps);
            allocator.free(recipe.params);
            allocator.free(recipe.commands);
            allocator.free(recipe.pre_hooks);
            allocator.free(recipe.post_hooks);
            allocator.free(recipe.aliases);
            allocator.free(recipe.only_os);
        }
        allocator.free(self.recipes);
        for (self.directives) |directive| {
            allocator.free(directive.args);
        }
        allocator.free(self.directives);
        allocator.free(self.imports);
        allocator.free(self.global_pre_hooks);
        allocator.free(self.global_post_hooks);
    }

    pub fn getRecipe(self: *const Jakefile, name: []const u8) ?*const Recipe {
        for (self.recipes) |*recipe| {
            if (std.mem.eql(u8, recipe.name, name)) {
                return recipe;
            }
            // Check aliases
            for (recipe.aliases) |alias| {
                if (std.mem.eql(u8, alias, name)) {
                    return recipe;
                }
            }
        }
        return null;
    }

    pub fn getDefaultRecipe(self: *const Jakefile) ?*const Recipe {
        // First, look for explicitly marked default
        for (self.recipes) |*recipe| {
            if (recipe.is_default) {
                return recipe;
            }
        }
        // Otherwise, return the first recipe
        if (self.recipes.len > 0) {
            return &self.recipes[0];
        }
        return null;
    }

    pub fn getVariable(self: *const Jakefile, name: []const u8) ?[]const u8 {
        for (self.variables) |v| {
            if (std.mem.eql(u8, v.name, name)) {
                return v.value;
            }
        }
        return null;
    }
};

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidSyntax,
    OutOfMemory,
};

/// Detailed error information with location
pub const ErrorInfo = struct {
    line: usize,
    column: usize,
    message: []const u8,
    found_tag: ?Token.Tag,
    expected_tag: ?Token.Tag,

    /// Format the error for display
    pub fn format(
        self: ErrorInfo,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("error at line {d}, column {d}: {s}", .{
            self.line,
            self.column,
            self.message,
        });
        if (self.expected_tag) |expected| {
            try writer.print(" (expected '{s}'", .{@tagName(expected)});
            if (self.found_tag) |found| {
                try writer.print(", found '{s}')", .{@tagName(found)});
            } else {
                try writer.writeAll(")");
            }
        }
    }

    /// Format error message to a buffer, returns the formatted string slice
    pub fn formatMessage(self: ErrorInfo, buf: []u8) []const u8 {
        var fbs = std.io.fixedBufferStream(buf);
        self.format("", .{}, fbs.writer()) catch return "error: formatting failed";
        return fbs.getWritten();
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: *Lexer,
    current: Token,
    source: []const u8,

    // Accumulators
    variables: std.ArrayListUnmanaged(Variable),
    recipes: std.ArrayListUnmanaged(Recipe),
    directives: std.ArrayListUnmanaged(Directive),
    imports: std.ArrayListUnmanaged(ImportDirective),
    global_pre_hooks: std.ArrayListUnmanaged(Hook),
    global_post_hooks: std.ArrayListUnmanaged(Hook),

    // Last error information for detailed reporting
    last_error: ?ErrorInfo,

    // Pending aliases for the next recipe
    pending_aliases: std.ArrayListUnmanaged([]const u8),

    // Pending metadata for next recipe
    pending_group: ?[]const u8,
    pending_description: ?[]const u8,
    pending_only_os: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator, lex: *Lexer) Parser {
        return .{
            .allocator = allocator,
            .lexer = lex,
            .current = lex.next(),
            .source = lex.source,
            .variables = .empty,
            .recipes = .empty,
            .directives = .empty,
            .imports = .empty,
            .global_pre_hooks = .empty,
            .global_post_hooks = .empty,
            .last_error = null,
            .pending_aliases = .empty,
            .pending_group = null,
            .pending_description = null,
            .pending_only_os = .empty,
        };
    }

    /// Free all accumulated items on parse failure
    pub fn deinit(self: *Parser) void {
        self.variables.deinit(self.allocator);
        for (self.recipes.items) |recipe| {
            self.allocator.free(recipe.dependencies);
            self.allocator.free(recipe.file_deps);
            self.allocator.free(recipe.params);
            self.allocator.free(recipe.commands);
            self.allocator.free(recipe.pre_hooks);
            self.allocator.free(recipe.post_hooks);
            self.allocator.free(recipe.aliases);
            self.allocator.free(recipe.only_os);
        }
        self.recipes.deinit(self.allocator);
        for (self.directives.items) |directive| {
            self.allocator.free(directive.args);
        }
        self.directives.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.global_pre_hooks.deinit(self.allocator);
        self.global_post_hooks.deinit(self.allocator);
        self.pending_aliases.deinit(self.allocator);
        self.pending_only_os.deinit(self.allocator);
    }

    fn advance(self: *Parser) void {
        self.current = self.lexer.next();
    }

    /// Get the last error information, if any
    pub fn getLastError(self: *const Parser) ?ErrorInfo {
        return self.last_error;
    }

    fn skipNewlines(self: *Parser) void {
        while (self.current.tag == .newline or self.current.tag == .comment) {
            self.advance();
        }
    }

    /// Set an error with the current token's location
    fn setError(self: *Parser, message: []const u8, expected: ?Token.Tag) void {
        self.last_error = .{
            .line = self.current.loc.line,
            .column = self.current.loc.column,
            .message = message,
            .found_tag = self.current.tag,
            .expected_tag = expected,
        };
    }

    fn expect(self: *Parser, tag: Token.Tag) ParseError!Token {
        if (self.current.tag != tag) {
            self.setError("unexpected token", tag);
            return ParseError.UnexpectedToken;
        }
        const tok = self.current;
        self.advance();
        return tok;
    }

    /// Expect a specific token with a custom error message
    fn expectWithMessage(self: *Parser, tag: Token.Tag, message: []const u8) ParseError!Token {
        if (self.current.tag != tag) {
            self.setError(message, tag);
            return ParseError.UnexpectedToken;
        }
        const tok = self.current;
        self.advance();
        return tok;
    }

    fn slice(self: *Parser, tok: Token) []const u8 {
        return tok.slice(self.source);
    }

    /// Consume and return pending aliases, clearing them for the next recipe
    fn consumePendingAliases(self: *Parser) ParseError![]const []const u8 {
        if (self.pending_aliases.items.len == 0) {
            return &[_][]const u8{};
        }
        const aliases = self.pending_aliases.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        return aliases;
    }

    /// Consume and return pending group, clearing it for the next recipe
    fn consumePendingGroup(self: *Parser) ?[]const u8 {
        const group = self.pending_group;
        self.pending_group = null;
        return group;
    }

    /// Consume and return pending description, clearing it for the next recipe
    fn consumePendingDescription(self: *Parser) ?[]const u8 {
        const desc = self.pending_description;
        self.pending_description = null;
        return desc;
    }

    /// Consume and return pending only_os, clearing it for the next recipe
    fn consumePendingOnlyOs(self: *Parser) ParseError![]const []const u8 {
        if (self.pending_only_os.items.len == 0) {
            return &[_][]const u8{};
        }
        const only_os = self.pending_only_os.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        return only_os;
    }

    pub fn parseJakefile(self: *Parser) ParseError!Jakefile {
        errdefer self.deinit();

        while (self.current.tag != .eof) {
            self.skipNewlines();

            if (self.current.tag == .eof) break;

            switch (self.current.tag) {
                .at => try self.parseDirective(),
                .ident => try self.parseVariableOrRecipe(),
                .kw_task => try self.parseTaskRecipe(),
                .kw_file => try self.parseFileRecipe(),
                .comment => self.advance(),
                .newline => self.advance(),
                else => {
                    self.advance(); // Skip invalid token
                },
            }
        }

        return Jakefile{
            .variables = self.variables.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .recipes = self.recipes.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .directives = self.directives.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .imports = self.imports.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .global_pre_hooks = self.global_pre_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .global_post_hooks = self.global_post_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .source = self.source,
        };
    }

    fn parseDirective(self: *Parser) ParseError!void {
        _ = try self.expect(.at);

        if (self.current.tag == .kw_default) {
            // @default marker for next recipe
            self.advance();
            self.skipNewlines();

            // Parse the recipe that follows and mark it as default
            if (self.current.tag == .kw_task) {
                try self.parseTaskRecipe();
            } else if (self.current.tag == .kw_file) {
                try self.parseFileRecipe();
            } else if (self.current.tag == .ident) {
                try self.parseVariableOrRecipe();
            }

            // Mark last recipe as default
            if (self.recipes.items.len > 0) {
                self.recipes.items[self.recipes.items.len - 1].is_default = true;
            }
            return;
        }

        // Handle @import specially with "as prefix" support
        if (self.current.tag == .kw_import) {
            self.advance();
            try self.parseImportDirective();
            return;
        }

        // Handle @alias directive for recipes
        if (self.current.tag == .kw_alias) {
            self.advance();

            // Collect alias names until newline
            while (self.current.tag != .newline and self.current.tag != .eof) {
                if (self.current.tag == .ident) {
                    self.pending_aliases.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
                }
                self.advance();
            }
            return;
        }

        // Handle @group directive for recipe organization
        if (self.current.tag == .kw_group) {
            self.advance();

            // Get group name (identifier or string)
            if (self.current.tag == .ident or self.current.tag == .string) {
                self.pending_group = stripQuotes(self.slice(self.current));
                self.advance();
            }

            // Skip to end of line
            while (self.current.tag != .newline and self.current.tag != .eof) {
                self.advance();
            }
            return;
        }

        // Handle @desc or @description directive
        if (self.current.tag == .kw_desc) {
            self.advance();

            // Get description (string or remaining text)
            if (self.current.tag == .string) {
                self.pending_description = stripQuotes(self.slice(self.current));
                self.advance();
            } else {
                // Collect everything until newline as description
                const desc_start = self.current.loc.start;
                while (self.current.tag != .newline and self.current.tag != .eof) {
                    self.advance();
                }
                const desc_end = self.current.loc.start;
                const desc = std.mem.trim(u8, self.source[desc_start..desc_end], " \t");
                if (desc.len > 0) {
                    self.pending_description = desc;
                }
            }

            // Skip to end of line
            while (self.current.tag != .newline and self.current.tag != .eof) {
                self.advance();
            }
            return;
        }

        // Handle @only or @only-os directive for OS-specific recipes
        if (self.current.tag == .kw_only or self.current.tag == .kw_only_os) {
            self.advance();

            // Collect OS names until newline (e.g., linux macos windows)
            while (self.current.tag != .newline and self.current.tag != .eof) {
                if (self.current.tag == .ident) {
                    self.pending_only_os.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
                }
                self.advance();
            }
            return;
        }

        // Handle global @pre and @post hooks
        if (self.current.tag == .kw_pre or self.current.tag == .kw_post) {
            const hook_kind: Hook.Kind = if (self.current.tag == .kw_pre) .pre else .post;
            self.advance();

            // Collect the command until newline
            const cmd_start = self.current.loc.start;
            while (self.current.tag != .newline and self.current.tag != .eof) {
                self.advance();
            }
            const cmd_end = self.current.loc.start;
            const command = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t");

            const hook = Hook{
                .command = command,
                .kind = hook_kind,
                .recipe_name = null, // Global hook
            };

            switch (hook_kind) {
                .pre => self.global_pre_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
                .post => self.global_post_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
            }
            return;
        }

        // Other directives
        const kind: Directive.Kind = switch (self.current.tag) {
            .kw_dotenv => .dotenv,
            .kw_require => .require,
            .kw_export => .@"export",
            else => return, // Unknown directive, skip
        };

        self.advance();

        // Collect arguments until newline
        var args: std.ArrayListUnmanaged([]const u8) = .empty;
        while (self.current.tag != .newline and self.current.tag != .eof) {
            if (self.current.tag == .ident or self.current.tag == .string or self.current.tag == .glob_pattern) {
                args.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
            }
            self.advance();
        }

        self.directives.append(self.allocator, .{
            .kind = kind,
            .args = args.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
        }) catch return ParseError.OutOfMemory;
    }

    /// Parse @import directive: @import "path/to/file.jake" [as prefix]
    fn parseImportDirective(self: *Parser) ParseError!void {
        // Expect a path (string or identifier/glob pattern)
        var path: []const u8 = undefined;
        if (self.current.tag == .string) {
            path = stripQuotes(self.slice(self.current));
            self.advance();
        } else if (self.current.tag == .ident or self.current.tag == .glob_pattern) {
            path = self.slice(self.current);
            self.advance();
        } else {
            // No valid path, skip to end of line
            while (self.current.tag != .newline and self.current.tag != .eof) {
                self.advance();
            }
            return;
        }

        // Check for optional "as prefix" suffix
        var prefix: ?[]const u8 = null;
        if (self.current.tag == .kw_as) {
            self.advance();
            if (self.current.tag == .ident) {
                prefix = self.slice(self.current);
                self.advance();
            }
        }

        // Skip any remaining tokens on the line
        while (self.current.tag != .newline and self.current.tag != .eof) {
            self.advance();
        }

        self.imports.append(self.allocator, .{
            .path = path,
            .prefix = prefix,
        }) catch return ParseError.OutOfMemory;
    }

    fn parseVariableOrRecipe(self: *Parser) ParseError!void {
        const name_tok = self.current;
        const name = self.slice(name_tok);
        self.advance();

        if (self.current.tag == .equals) {
            // Variable assignment: name = value
            self.advance();
            const value = if (self.current.tag == .string or self.current.tag == .ident or self.current.tag == .glob_pattern)
                self.slice(self.current)
            else
                "";
            if (self.current.tag != .newline and self.current.tag != .eof) {
                self.advance();
            }
            self.variables.append(self.allocator, .{ .name = name, .value = stripQuotes(value) }) catch return ParseError.OutOfMemory;
        } else if (self.current.tag == .colon) {
            // Simple recipe: name: [deps]
            try self.parseSimpleRecipe(name);
        }
    }

    fn parseSimpleRecipe(self: *Parser, name: []const u8) ParseError!void {
        _ = try self.expectWithMessage(.colon, "expected ':' after recipe name");

        var deps: std.ArrayListUnmanaged([]const u8) = .empty;

        // Parse dependencies (can be identifiers or paths like dist/app.js)
        if (self.current.tag == .l_bracket) {
            self.advance();
            while (self.current.tag != .r_bracket and self.current.tag != .eof) {
                if (self.current.tag == .ident or self.current.tag == .glob_pattern) {
                    deps.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
                }
                self.advance();
                if (self.current.tag == .comma) self.advance();
            }
            if (self.current.tag == .r_bracket) self.advance();
        }

        self.skipNewlines();

        // Parse commands and hooks (indented lines)
        var commands: std.ArrayListUnmanaged(Recipe.Command) = .empty;
        var pre_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var post_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var working_dir: ?[]const u8 = null;
        var shell: ?[]const u8 = null;

        while (self.current.tag == .indent) {
            self.advance();

            // Check for @pre or @post hook directive
            if (self.current.tag == .at) {
                const at_pos = self.current.loc.start;
                self.advance();

                if (self.current.tag == .kw_pre or self.current.tag == .kw_post) {
                    const hook_kind: Hook.Kind = if (self.current.tag == .kw_pre) .pre else .post;
                    self.advance();

                    const cmd_start = self.current.loc.start;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const cmd_end = self.current.loc.start;
                    const command = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t");

                    const hook = Hook{
                        .command = command,
                        .kind = hook_kind,
                        .recipe_name = name,
                    };

                    switch (hook_kind) {
                        .pre => pre_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
                        .post => post_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
                    }

                    if (self.current.tag == .newline) self.advance();
                    continue;
                } else if (self.current.tag == .kw_cd) {
                    // @cd directive - set working directory for recipe
                    self.advance();
                    const path_start = self.current.loc.start;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const path_end = self.current.loc.start;
                    working_dir = stripQuotes(std.mem.trim(u8, self.source[path_start..path_end], " \t"));
                    if (self.current.tag == .newline) self.advance();
                    continue;
                } else if (self.current.tag == .kw_shell) {
                    // @shell directive - set shell for recipe
                    self.advance();
                    const shell_start = self.current.loc.start;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const shell_end = self.current.loc.start;
                    shell = stripQuotes(std.mem.trim(u8, self.source[shell_start..shell_end], " \t"));
                    if (self.current.tag == .newline) self.advance();
                    continue;
                } else {
                    // Not a hook, treat as regular command starting with @
                    const cmd_start = at_pos;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const cmd_end = self.current.loc.start;
                    commands.append(self.allocator, .{
                        .line = self.source[cmd_start..cmd_end],
                        .directive = null,
                    }) catch return ParseError.OutOfMemory;
                    if (self.current.tag == .newline) self.advance();
                    continue;
                }
            }

            const cmd_start = self.current.loc.start;
            // Consume until newline
            while (self.current.tag != .newline and self.current.tag != .eof) {
                self.advance();
            }
            const cmd_end = self.current.loc.start;
            commands.append(self.allocator, .{
                .line = self.source[cmd_start..cmd_end],
                .directive = null,
            }) catch return ParseError.OutOfMemory;
            if (self.current.tag == .newline) self.advance();
        }

        // Consume any pending metadata
        const aliases = try self.consumePendingAliases();
        const only_os = try self.consumePendingOnlyOs();

        self.recipes.append(self.allocator, .{
            .name = name,
            .kind = .simple,
            .dependencies = deps.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .file_deps = &[_][]const u8{},
            .output = null,
            .params = &[_]Recipe.Param{},
            .commands = commands.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .pre_hooks = pre_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .post_hooks = post_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .doc_comment = null,
            .is_default = false,
            .aliases = aliases,
            .group = self.consumePendingGroup(),
            .description = self.consumePendingDescription(),
            .shell = shell,
            .working_dir = working_dir,
            .only_os = only_os,
            .quiet = false,
        }) catch return ParseError.OutOfMemory;
    }

    fn parseTaskRecipe(self: *Parser) ParseError!void {
        _ = try self.expect(.kw_task);

        if (self.current.tag != .ident) {
            self.setError("expected task name after 'task'", .ident);
            return ParseError.UnexpectedToken;
        }

        const name = self.slice(self.current);
        self.advance();

        var params: std.ArrayListUnmanaged(Recipe.Param) = .empty;
        var deps: std.ArrayListUnmanaged([]const u8) = .empty;

        // Parse parameters (name=default)
        while (self.current.tag == .ident and self.current.tag != .colon) {
            const param_name = self.slice(self.current);
            self.advance();
            var default: ?[]const u8 = null;
            if (self.current.tag == .equals) {
                self.advance();
                if (self.current.tag == .string or self.current.tag == .ident) {
                    default = stripQuotes(self.slice(self.current));
                    self.advance();
                }
            }
            params.append(self.allocator, .{ .name = param_name, .default = default }) catch return ParseError.OutOfMemory;
        }

        _ = try self.expectWithMessage(.colon, "expected ':' after task name");

        // Parse dependencies (can be identifiers or paths like dist/app.js)
        if (self.current.tag == .l_bracket) {
            self.advance();
            while (self.current.tag != .r_bracket and self.current.tag != .eof) {
                if (self.current.tag == .ident or self.current.tag == .glob_pattern) {
                    deps.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
                }
                self.advance();
                if (self.current.tag == .comma) self.advance();
            }
            if (self.current.tag == .r_bracket) self.advance();
        }

        self.skipNewlines();

        // Parse commands and hooks
        var commands: std.ArrayListUnmanaged(Recipe.Command) = .empty;
        var pre_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var post_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var working_dir: ?[]const u8 = null;
        var shell: ?[]const u8 = null;

        while (self.current.tag == .indent) {
            self.advance();

            // Check for directive
            var directive: ?Recipe.CommandDirective = null;
            if (self.current.tag == .at) {
                self.advance();

                // Check for @pre or @post hook
                if (self.current.tag == .kw_pre or self.current.tag == .kw_post) {
                    const hook_kind: Hook.Kind = if (self.current.tag == .kw_pre) .pre else .post;
                    self.advance();

                    const cmd_start = self.current.loc.start;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const cmd_end = self.current.loc.start;
                    const command = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t");

                    const hook = Hook{
                        .command = command,
                        .kind = hook_kind,
                        .recipe_name = name,
                    };

                    switch (hook_kind) {
                        .pre => pre_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
                        .post => post_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
                    }

                    if (self.current.tag == .newline) self.advance();
                    continue;
                }

                // Check for @cd directive
                if (self.current.tag == .kw_cd) {
                    self.advance();
                    const path_start = self.current.loc.start;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const path_end = self.current.loc.start;
                    working_dir = stripQuotes(std.mem.trim(u8, self.source[path_start..path_end], " \t"));
                    if (self.current.tag == .newline) self.advance();
                    continue;
                }

                // Check for @shell directive
                if (self.current.tag == .kw_shell) {
                    self.advance();
                    const shell_start = self.current.loc.start;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const shell_end = self.current.loc.start;
                    shell = stripQuotes(std.mem.trim(u8, self.source[shell_start..shell_end], " \t"));
                    if (self.current.tag == .newline) self.advance();
                    continue;
                }

                // Other directives
                directive = switch (self.current.tag) {
                    .kw_cache => .cache,
                    .kw_needs => .needs,
                    .kw_confirm => .confirm,
                    .kw_watch => .watch,
                    .kw_if => .@"if",
                    .kw_elif => .elif,
                    .kw_else => .@"else",
                    .kw_end => .end,
                    .kw_each => .each,
                    .kw_ignore => .ignore,
                    else => null, // Unknown directive
                };
            }

            const cmd_start = self.current.loc.start;
            while (self.current.tag != .newline and self.current.tag != .eof) {
                self.advance();
            }
            const cmd_end = self.current.loc.start;

            commands.append(self.allocator, .{
                .line = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t"),
                .directive = directive,
            }) catch return ParseError.OutOfMemory;

            if (self.current.tag == .newline) self.advance();
        }

        // Consume any pending metadata
        const aliases = try self.consumePendingAliases();
        const only_os = try self.consumePendingOnlyOs();

        self.recipes.append(self.allocator, .{
            .name = name,
            .kind = .task,
            .dependencies = deps.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .file_deps = &[_][]const u8{},
            .output = null,
            .params = params.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .commands = commands.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .pre_hooks = pre_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .post_hooks = post_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .doc_comment = null,
            .is_default = false,
            .aliases = aliases,
            .group = self.consumePendingGroup(),
            .description = self.consumePendingDescription(),
            .shell = shell,
            .working_dir = working_dir,
            .only_os = only_os,
            .quiet = false,
        }) catch return ParseError.OutOfMemory;
    }

    fn parseFileRecipe(self: *Parser) ParseError!void {
        _ = try self.expect(.kw_file);

        if (self.current.tag != .ident and self.current.tag != .glob_pattern) {
            self.setError("expected output filename after 'file'", .ident);
            return ParseError.UnexpectedToken;
        }

        // Output file
        const output = self.slice(self.current);
        self.advance();

        _ = try self.expectWithMessage(.colon, "expected ':' after output filename");

        // File dependencies (globs)
        var file_deps: std.ArrayListUnmanaged([]const u8) = .empty;
        while (self.current.tag != .newline and self.current.tag != .eof) {
            if (self.current.tag == .ident or self.current.tag == .glob_pattern) {
                file_deps.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
            }
            self.advance();
            if (self.current.tag == .comma) self.advance();
        }

        self.skipNewlines();

        // Parse commands and hooks
        var commands: std.ArrayListUnmanaged(Recipe.Command) = .empty;
        var pre_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var post_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var working_dir: ?[]const u8 = null;
        var shell: ?[]const u8 = null;

        while (self.current.tag == .indent) {
            self.advance();

            // Check for @pre or @post hook directive
            if (self.current.tag == .at) {
                const at_pos = self.current.loc.start;
                self.advance();

                if (self.current.tag == .kw_pre or self.current.tag == .kw_post) {
                    const hook_kind: Hook.Kind = if (self.current.tag == .kw_pre) .pre else .post;
                    self.advance();

                    const cmd_start = self.current.loc.start;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const cmd_end = self.current.loc.start;
                    const command = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t");

                    const hook = Hook{
                        .command = command,
                        .kind = hook_kind,
                        .recipe_name = output,
                    };

                    switch (hook_kind) {
                        .pre => pre_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
                        .post => post_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
                    }

                    if (self.current.tag == .newline) self.advance();
                    continue;
                } else if (self.current.tag == .kw_cd) {
                    // @cd directive - set working directory for recipe
                    self.advance();
                    const path_start = self.current.loc.start;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const path_end = self.current.loc.start;
                    working_dir = stripQuotes(std.mem.trim(u8, self.source[path_start..path_end], " \t"));
                    if (self.current.tag == .newline) self.advance();
                    continue;
                } else if (self.current.tag == .kw_shell) {
                    // @shell directive - set shell for recipe
                    self.advance();
                    const shell_start = self.current.loc.start;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const shell_end = self.current.loc.start;
                    shell = stripQuotes(std.mem.trim(u8, self.source[shell_start..shell_end], " \t"));
                    if (self.current.tag == .newline) self.advance();
                    continue;
                } else {
                    // Not a hook, treat as regular command starting with @
                    const cmd_start = at_pos;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const cmd_end = self.current.loc.start;
                    commands.append(self.allocator, .{
                        .line = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t"),
                        .directive = null,
                    }) catch return ParseError.OutOfMemory;
                    if (self.current.tag == .newline) self.advance();
                    continue;
                }
            }

            const cmd_start = self.current.loc.start;
            while (self.current.tag != .newline and self.current.tag != .eof) {
                self.advance();
            }
            const cmd_end = self.current.loc.start;
            commands.append(self.allocator, .{
                .line = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t"),
                .directive = null,
            }) catch return ParseError.OutOfMemory;
            if (self.current.tag == .newline) self.advance();
        }

        // Consume any pending metadata
        const aliases = try self.consumePendingAliases();
        const only_os = try self.consumePendingOnlyOs();

        // Use output as recipe name
        self.recipes.append(self.allocator, .{
            .name = output,
            .kind = .file,
            .dependencies = &[_][]const u8{},
            .file_deps = file_deps.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .output = output,
            .params = &[_]Recipe.Param{},
            .commands = commands.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .pre_hooks = pre_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .post_hooks = post_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .doc_comment = null,
            .is_default = false,
            .aliases = aliases,
            .group = self.consumePendingGroup(),
            .description = self.consumePendingDescription(),
            .shell = shell,
            .working_dir = working_dir,
            .only_os = only_os,
            .quiet = false,
        }) catch return ParseError.OutOfMemory;
    }
};

pub fn stripQuotes(s: []const u8) []const u8 {
    if (s.len >= 2) {
        if ((s[0] == '"' and s[s.len - 1] == '"') or (s[0] == '\'' and s[s.len - 1] == '\'')) {
            return s[1 .. s.len - 1];
        }
    }
    return s;
}

test "parse variable" {
    const source = "name = \"value\"";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.variables.len);
    try std.testing.expectEqualStrings("name", jakefile.variables[0].name);
    try std.testing.expectEqualStrings("value", jakefile.variables[0].value);
}

test "parse task recipe" {
    const source =
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].name);
    try std.testing.expectEqual(Recipe.Kind.task, jakefile.recipes[0].kind);
}

test "parse recipe with deps" {
    const source =
        \\build: [compile, test]
        \\    echo "done"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].dependencies.len);
}

test "parser error message with line and column" {
    const source =
        \\task build
        \\    echo "oops"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    const result = p.parseJakefile();

    try std.testing.expectError(ParseError.UnexpectedToken, result);

    // Check error info
    const err = p.getLastError();
    try std.testing.expect(err != null);
    try std.testing.expectEqual(@as(usize, 1), err.?.line);
    try std.testing.expectEqual(@as(usize, 11), err.?.column);
    try std.testing.expectEqual(Token.Tag.colon, err.?.expected_tag.?);
    try std.testing.expectEqual(Token.Tag.newline, err.?.found_tag.?);
}

test "parser error format" {
    const err_info = ErrorInfo{
        .line = 5,
        .column = 12,
        .message = "expected ':' after recipe name",
        .found_tag = .ident,
        .expected_tag = .colon,
    };

    var buf: [256]u8 = undefined;
    const msg = err_info.formatMessage(&buf);
    try std.testing.expect(std.mem.indexOf(u8, msg, "line 5") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "column 12") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "expected ':' after recipe name") != null);
}

test "parse global pre hook" {
    const source =
        \\@pre echo "Starting..."
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.global_pre_hooks.len);
    try std.testing.expectEqual(@as(usize, 0), jakefile.global_post_hooks.len);
    try std.testing.expectEqualStrings("echo \"Starting...\"", jakefile.global_pre_hooks[0].command);
    try std.testing.expectEqual(Hook.Kind.pre, jakefile.global_pre_hooks[0].kind);
    try std.testing.expectEqual(@as(?[]const u8, null), jakefile.global_pre_hooks[0].recipe_name);
}

test "parse global post hook" {
    const source =
        \\@post echo "Done!"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), jakefile.global_pre_hooks.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.global_post_hooks.len);
    try std.testing.expectEqualStrings("echo \"Done!\"", jakefile.global_post_hooks[0].command);
    try std.testing.expectEqual(Hook.Kind.post, jakefile.global_post_hooks[0].kind);
}

test "parse task with recipe hooks" {
    const source =
        \\task build:
        \\    @pre echo "Building..."
        \\    cargo build
        \\    @post echo "Build complete!"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqualStrings("build", recipe.name);
    try std.testing.expectEqual(@as(usize, 1), recipe.pre_hooks.len);
    try std.testing.expectEqual(@as(usize, 1), recipe.post_hooks.len);
    try std.testing.expectEqual(@as(usize, 1), recipe.commands.len);
    try std.testing.expectEqualStrings("echo \"Building...\"", recipe.pre_hooks[0].command);
    try std.testing.expectEqualStrings("echo \"Build complete!\"", recipe.post_hooks[0].command);
    try std.testing.expectEqualStrings("cargo build", recipe.commands[0].line);
}

test "parse global and recipe hooks together" {
    const source =
        \\@pre echo "Global pre"
        \\@post echo "Global post"
        \\
        \\task test:
        \\    @pre echo "Test pre"
        \\    cargo test
        \\    @post echo "Test post"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Check global hooks
    try std.testing.expectEqual(@as(usize, 1), jakefile.global_pre_hooks.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.global_post_hooks.len);
    try std.testing.expectEqualStrings("echo \"Global pre\"", jakefile.global_pre_hooks[0].command);
    try std.testing.expectEqualStrings("echo \"Global post\"", jakefile.global_post_hooks[0].command);

    // Check recipe hooks
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqual(@as(usize, 1), recipe.pre_hooks.len);
    try std.testing.expectEqual(@as(usize, 1), recipe.post_hooks.len);
    try std.testing.expectEqualStrings("echo \"Test pre\"", recipe.pre_hooks[0].command);
    try std.testing.expectEqualStrings("echo \"Test post\"", recipe.post_hooks[0].command);
}

// ============================================================================
// COMPREHENSIVE PARSER TESTS
// ============================================================================

// --- Simple Recipe Tests ---

test "parse simple recipe without deps" {
    const source =
        \\clean:
        \\    rm -rf build
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("clean", jakefile.recipes[0].name);
    try std.testing.expectEqual(Recipe.Kind.simple, jakefile.recipes[0].kind);
    try std.testing.expectEqual(@as(usize, 0), jakefile.recipes[0].dependencies.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].commands.len);
}

test "parse simple recipe with single dependency" {
    const source =
        \\deploy: [build]
        \\    ./deploy.sh
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].dependencies.len);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].dependencies[0]);
}

test "parse simple recipe with multiple dependencies" {
    const source =
        \\release: [build, test, lint, format]
        \\    echo "releasing"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), jakefile.recipes[0].dependencies.len);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].dependencies[0]);
    try std.testing.expectEqualStrings("test", jakefile.recipes[0].dependencies[1]);
    try std.testing.expectEqualStrings("lint", jakefile.recipes[0].dependencies[2]);
    try std.testing.expectEqualStrings("format", jakefile.recipes[0].dependencies[3]);
}

test "parse simple recipe with multiple commands" {
    const source =
        \\setup:
        \\    npm install
        \\    npm run build
        \\    npm test
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes[0].commands.len);
}

// --- Task Recipe Tests ---

test "parse task recipe with parameters" {
    const source =
        \\task greet name:
        \\    echo "Hello, {{name}}"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(Recipe.Kind.task, jakefile.recipes[0].kind);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].params.len);
    try std.testing.expectEqualStrings("name", jakefile.recipes[0].params[0].name);
    try std.testing.expect(jakefile.recipes[0].params[0].default == null);
}

test "parse task recipe with default parameter" {
    const source =
        \\task greet name="World":
        \\    echo "Hello, {{name}}"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].params.len);
    try std.testing.expectEqualStrings("name", jakefile.recipes[0].params[0].name);
    try std.testing.expectEqualStrings("World", jakefile.recipes[0].params[0].default.?);
}

test "parse task recipe with multiple parameters" {
    const source =
        \\task deploy env target="production":
        \\    ./deploy.sh
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].params.len);
    try std.testing.expectEqualStrings("env", jakefile.recipes[0].params[0].name);
    try std.testing.expect(jakefile.recipes[0].params[0].default == null);
    try std.testing.expectEqualStrings("target", jakefile.recipes[0].params[1].name);
    try std.testing.expectEqualStrings("production", jakefile.recipes[0].params[1].default.?);
}

test "parse task recipe with dependencies" {
    const source =
        \\task test: [build]
        \\    npm test
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(Recipe.Kind.task, jakefile.recipes[0].kind);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].dependencies.len);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].dependencies[0]);
}

// --- File Recipe Tests ---

test "parse file recipe" {
    const source =
        \\file output.js: src/*.ts
        \\    tsc --outFile output.js
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("output.js", jakefile.recipes[0].name);
    try std.testing.expectEqual(Recipe.Kind.file, jakefile.recipes[0].kind);
    try std.testing.expectEqualStrings("output.js", jakefile.recipes[0].output.?);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].file_deps.len);
}

test "parse file recipe with multiple deps" {
    const source =
        \\file bundle.js: src/**/*.ts, lib/*.ts
        \\    webpack
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].file_deps.len);
    try std.testing.expectEqualStrings("src/**/*.ts", jakefile.recipes[0].file_deps[0]);
    try std.testing.expectEqualStrings("lib/*.ts", jakefile.recipes[0].file_deps[1]);
}

// --- Variable Tests ---

test "parse variable with string value" {
    const source = "name = \"value\"";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.variables.len);
    try std.testing.expectEqualStrings("name", jakefile.variables[0].name);
    try std.testing.expectEqualStrings("value", jakefile.variables[0].value);
}

test "parse variable with single quoted string" {
    const source = "name = 'value'";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("value", jakefile.variables[0].value);
}

test "parse variable with identifier value" {
    const source = "name = value";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("value", jakefile.variables[0].value);
}

test "parse multiple variables" {
    const source =
        \\env = "production"
        \\port = 8080
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.variables.len);
    try std.testing.expectEqualStrings("env", jakefile.variables[0].name);
    try std.testing.expectEqualStrings("port", jakefile.variables[1].name);
}

// --- Directive Tests ---

test "parse dotenv directive" {
    const source = "@dotenv .env";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.directives.len);
    try std.testing.expectEqual(Directive.Kind.dotenv, jakefile.directives[0].kind);
    try std.testing.expectEqual(@as(usize, 1), jakefile.directives[0].args.len);
}

test "parse require directive" {
    const source = "@require node npm docker";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.directives.len);
    try std.testing.expectEqual(Directive.Kind.require, jakefile.directives[0].kind);
    try std.testing.expectEqual(@as(usize, 3), jakefile.directives[0].args.len);
}

test "parse import directive" {
    const source = "@import \"common.jake\"";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.imports.len);
    try std.testing.expectEqualStrings("common.jake", jakefile.imports[0].path);
    try std.testing.expect(jakefile.imports[0].prefix == null);
}

test "parse import directive with prefix" {
    const source = "@import \"docker.jake\" as docker";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.imports.len);
    try std.testing.expectEqualStrings("docker.jake", jakefile.imports[0].path);
    try std.testing.expectEqualStrings("docker", jakefile.imports[0].prefix.?);
}

test "parse default directive" {
    const source =
        \\@default
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expect(jakefile.recipes[0].is_default);
}

test "parse export directive" {
    const source = "@export NODE_ENV";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.directives.len);
    try std.testing.expectEqual(Directive.Kind.@"export", jakefile.directives[0].kind);
}

// --- Default Recipe Tests ---

test "getDefaultRecipe returns first recipe when none marked" {
    const source =
        \\build:
        \\    echo "build"
        \\test:
        \\    echo "test"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const default = jakefile.getDefaultRecipe();
    try std.testing.expect(default != null);
    try std.testing.expectEqualStrings("build", default.?.name);
}

test "getDefaultRecipe returns marked recipe" {
    const source =
        \\build:
        \\    echo "build"
        \\@default
        \\test:
        \\    echo "test"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const default = jakefile.getDefaultRecipe();
    try std.testing.expect(default != null);
    try std.testing.expectEqualStrings("test", default.?.name);
}

// --- Recipe Lookup Tests ---

test "getRecipe finds existing recipe" {
    const source =
        \\build:
        \\    echo "build"
        \\test:
        \\    echo "test"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const recipe = jakefile.getRecipe("test");
    try std.testing.expect(recipe != null);
    try std.testing.expectEqualStrings("test", recipe.?.name);
}

test "getRecipe returns null for non-existent recipe" {
    const source =
        \\build:
        \\    echo "build"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const recipe = jakefile.getRecipe("nonexistent");
    try std.testing.expect(recipe == null);
}

// --- Variable Lookup Tests ---

test "getVariable finds existing variable" {
    const source =
        \\env = "production"
        \\port = 8080
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const value = jakefile.getVariable("port");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("8080", value.?);
}

test "getVariable returns null for non-existent variable" {
    const source = "env = \"production\"";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const value = jakefile.getVariable("nonexistent");
    try std.testing.expect(value == null);
}

// --- Command Directive Tests ---

test "parse task with cache directive" {
    const source =
        \\task build:
        \\    @cache
        \\    npm run build
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].commands.len);
    try std.testing.expectEqual(Recipe.CommandDirective.cache, jakefile.recipes[0].commands[0].directive.?);
}

test "parse task with if directive" {
    const source =
        \\task deploy:
        \\    @if CI
        \\    echo "deploying"
        \\    @end
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes[0].commands.len);
    try std.testing.expectEqual(Recipe.CommandDirective.@"if", jakefile.recipes[0].commands[0].directive.?);
    try std.testing.expectEqual(Recipe.CommandDirective.end, jakefile.recipes[0].commands[2].directive.?);
}

// --- Empty Input Tests ---

test "parse empty input" {
    const source = "";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 0), jakefile.variables.len);
    try std.testing.expectEqual(@as(usize, 0), jakefile.directives.len);
}

test "parse whitespace only" {
    const source = "   \n\n   ";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), jakefile.recipes.len);
}

test "parse comments only" {
    const source =
        \\# This is a comment
        \\# Another comment
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), jakefile.recipes.len);
}

// --- Mixed Content Tests ---

test "parse complete jakefile" {
    const source =
        \\# Configuration
        \\env = "production"
        \\
        \\@dotenv .env
        \\@require node npm
        \\
        \\task build:
        \\    npm run build
        \\
        \\task test: [build]
        \\    npm test
        \\
        \\@default
        \\task deploy target="staging": [test]
        \\    ./deploy.sh {{target}}
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.variables.len);
    try std.testing.expectEqual(@as(usize, 2), jakefile.directives.len);
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes.len);
    try std.testing.expect(jakefile.recipes[2].is_default);
}

// --- stripQuotes Tests ---

test "stripQuotes removes double quotes" {
    try std.testing.expectEqualStrings("hello", stripQuotes("\"hello\""));
}

test "stripQuotes removes single quotes" {
    try std.testing.expectEqualStrings("hello", stripQuotes("'hello'"));
}

test "stripQuotes preserves unquoted strings" {
    try std.testing.expectEqualStrings("hello", stripQuotes("hello"));
}

test "stripQuotes handles empty string" {
    try std.testing.expectEqualStrings("", stripQuotes(""));
}

test "stripQuotes handles empty quoted string" {
    try std.testing.expectEqualStrings("", stripQuotes("\"\""));
}

// --- @ignore Directive Tests ---

test "parse task with ignore directive" {
    const source =
        \\task test-all:
        \\    @ignore
        \\    npm test
        \\    @ignore
        \\    cargo test
        \\    echo "Tests complete"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 5), jakefile.recipes[0].commands.len);
    // First command is @ignore directive
    try std.testing.expectEqual(Recipe.CommandDirective.ignore, jakefile.recipes[0].commands[0].directive.?);
    // Second command (npm test) has no directive
    try std.testing.expect(jakefile.recipes[0].commands[1].directive == null);
    // Third command is @ignore directive
    try std.testing.expectEqual(Recipe.CommandDirective.ignore, jakefile.recipes[0].commands[2].directive.?);
    // Fourth command (cargo test) has no directive
    try std.testing.expect(jakefile.recipes[0].commands[3].directive == null);
    // Fifth command (echo) has no directive
    try std.testing.expect(jakefile.recipes[0].commands[4].directive == null);
}

// --- @group and @description Tests ---

test "parse group directive" {
    const source =
        \\@group build
        \\task compile:
        \\    gcc -o app main.c
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("compile", jakefile.recipes[0].name);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].group.?);
}

test "parse desc directive with string" {
    const source =
        \\@desc "Build the application"
        \\task build:
        \\    npm run build
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].name);
    try std.testing.expectEqualStrings("Build the application", jakefile.recipes[0].description.?);
}

test "parse description directive with string" {
    const source =
        \\@description "Run all tests"
        \\task test:
        \\    npm test
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("test", jakefile.recipes[0].name);
    try std.testing.expectEqualStrings("Run all tests", jakefile.recipes[0].description.?);
}

test "parse group and desc together" {
    const source =
        \\@group build
        \\@desc "Build the frontend application"
        \\task build-frontend:
        \\    npm run build
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("build-frontend", jakefile.recipes[0].name);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].group.?);
    try std.testing.expectEqualStrings("Build the frontend application", jakefile.recipes[0].description.?);
}

test "parse multiple recipes with different groups" {
    const source =
        \\@group build
        \\@desc "Build frontend"
        \\task build-frontend:
        \\    npm run build
        \\
        \\@group build
        \\@desc "Build backend"
        \\task build-backend:
        \\    cargo build
        \\
        \\@group test
        \\@desc "Run all tests"
        \\task test:
        \\    npm test && cargo test
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes.len);

    try std.testing.expectEqualStrings("build-frontend", jakefile.recipes[0].name);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].group.?);
    try std.testing.expectEqualStrings("Build frontend", jakefile.recipes[0].description.?);

    try std.testing.expectEqualStrings("build-backend", jakefile.recipes[1].name);
    try std.testing.expectEqualStrings("build", jakefile.recipes[1].group.?);
    try std.testing.expectEqualStrings("Build backend", jakefile.recipes[1].description.?);

    try std.testing.expectEqualStrings("test", jakefile.recipes[2].name);
    try std.testing.expectEqualStrings("test", jakefile.recipes[2].group.?);
    try std.testing.expectEqualStrings("Run all tests", jakefile.recipes[2].description.?);
}

test "parse recipe without group or description" {
    const source =
        \\task clean:
        \\    rm -rf dist
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("clean", jakefile.recipes[0].name);
    try std.testing.expect(jakefile.recipes[0].group == null);
    try std.testing.expect(jakefile.recipes[0].description == null);
}

test "parse group with quoted string" {
    const source =
        \\@group "Development Tools"
        \\task dev-server:
        \\    npm run dev
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("Development Tools", jakefile.recipes[0].group.?);
}

test "parse ignore directive standalone" {
    const source =
        \\task build:
        \\    @ignore
        \\    exit 1
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].commands.len);
    try std.testing.expectEqual(Recipe.CommandDirective.ignore, jakefile.recipes[0].commands[0].directive.?);
}

// --- Alias Tests ---

test "parse task recipe with single alias" {
    const source =
        \\@alias compile
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].name);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].aliases.len);
    try std.testing.expectEqualStrings("compile", jakefile.recipes[0].aliases[0]);
}

test "parse task recipe with multiple aliases" {
    const source =
        \\@alias compile bundle make
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes[0].aliases.len);
    try std.testing.expectEqualStrings("compile", jakefile.recipes[0].aliases[0]);
    try std.testing.expectEqualStrings("bundle", jakefile.recipes[0].aliases[1]);
    try std.testing.expectEqualStrings("make", jakefile.recipes[0].aliases[2]);
}

test "parse simple recipe with alias" {
    const source =
        \\@alias c
        \\clean:
        \\    rm -rf build
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("clean", jakefile.recipes[0].name);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].aliases.len);
    try std.testing.expectEqualStrings("c", jakefile.recipes[0].aliases[0]);
}

test "getRecipe finds recipe by alias" {
    const source =
        \\@alias compile bundle
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Should find by name
    const by_name = jakefile.getRecipe("build");
    try std.testing.expect(by_name != null);
    try std.testing.expectEqualStrings("build", by_name.?.name);

    // Should find by first alias
    const by_alias1 = jakefile.getRecipe("compile");
    try std.testing.expect(by_alias1 != null);
    try std.testing.expectEqualStrings("build", by_alias1.?.name);

    // Should find by second alias
    const by_alias2 = jakefile.getRecipe("bundle");
    try std.testing.expect(by_alias2 != null);
    try std.testing.expectEqualStrings("build", by_alias2.?.name);

    // Should not find non-existent
    const not_found = jakefile.getRecipe("nonexistent");
    try std.testing.expect(not_found == null);
}

test "alias only applies to next recipe" {
    const source =
        \\@alias a1
        \\task first:
        \\    echo "first"
        \\
        \\task second:
        \\    echo "second"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].aliases.len);
    try std.testing.expectEqual(@as(usize, 0), jakefile.recipes[1].aliases.len);
}

test "alias with default directive" {
    const source =
        \\@alias b
        \\@default
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expect(jakefile.recipes[0].is_default);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].aliases.len);
    try std.testing.expectEqualStrings("b", jakefile.recipes[0].aliases[0]);
}

// --- @only-os and @only Tests ---

test "parse only-os directive with single os" {
    const source =
        \\@only-os linux
        \\task build-linux:
        \\    ./build.sh
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].only_os.len);
    try std.testing.expectEqualStrings("linux", jakefile.recipes[0].only_os[0]);
}

test "parse only-os directive with multiple os" {
    const source =
        \\@only-os linux macos
        \\task build-unix:
        \\    ./build.sh
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].only_os.len);
    try std.testing.expectEqualStrings("linux", jakefile.recipes[0].only_os[0]);
    try std.testing.expectEqualStrings("macos", jakefile.recipes[0].only_os[1]);
}

test "parse only directive with multiple os" {
    const source =
        \\@only linux macos windows
        \\task cross-platform:
        \\    ./build.sh
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes[0].only_os.len);
    try std.testing.expectEqualStrings("linux", jakefile.recipes[0].only_os[0]);
    try std.testing.expectEqualStrings("macos", jakefile.recipes[0].only_os[1]);
    try std.testing.expectEqualStrings("windows", jakefile.recipes[0].only_os[2]);
}

test "parse only-os applies only to next recipe" {
    const source =
        \\@only-os windows
        \\task build-windows:
        \\    build.bat
        \\
        \\task build-all:
        \\    echo "all"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].only_os.len);
    try std.testing.expectEqualStrings("windows", jakefile.recipes[0].only_os[0]);
    try std.testing.expectEqual(@as(usize, 0), jakefile.recipes[1].only_os.len);
}

test "parse only-os with simple recipe" {
    const source =
        \\@only-os macos
        \\brew-install:
        \\    brew install deps
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].only_os.len);
    try std.testing.expectEqualStrings("macos", jakefile.recipes[0].only_os[0]);
}

test "parse only-os with file recipe" {
    const source =
        \\@only-os linux
        \\file output.so: src/*.c
        \\    gcc -shared -o output.so src/*.c
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].only_os.len);
    try std.testing.expectEqualStrings("linux", jakefile.recipes[0].only_os[0]);
}

test "parse only-os combined with other directives" {
    const source =
        \\@only-os linux macos
        \\@alias b
        \\@group build
        \\task build-unix:
        \\    ./build.sh
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqual(@as(usize, 2), recipe.only_os.len);
    try std.testing.expectEqual(@as(usize, 1), recipe.aliases.len);
    try std.testing.expectEqualStrings("build", recipe.group.?);
}

test "parse @cd directive in task recipe" {
    const source =
        \\task build:
        \\    @cd ./packages/frontend
        \\    npm run build
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqualStrings("build", recipe.name);
    try std.testing.expectEqualStrings("./packages/frontend", recipe.working_dir.?);
    try std.testing.expectEqual(@as(usize, 1), recipe.commands.len);
    try std.testing.expectEqualStrings("npm run build", recipe.commands[0].line);
}

test "parse @shell directive in task recipe" {
    const source =
        \\task build:
        \\    @shell bash
        \\    echo "using bash"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqualStrings("build", recipe.name);
    try std.testing.expectEqualStrings("bash", recipe.shell.?);
    try std.testing.expectEqual(@as(usize, 1), recipe.commands.len);
}

test "parse @cd and @shell together in task recipe" {
    const source =
        \\task build:
        \\    @cd ./packages/frontend
        \\    @shell bash
        \\    npm run build
        \\    npm run test
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqualStrings("build", recipe.name);
    try std.testing.expectEqualStrings("./packages/frontend", recipe.working_dir.?);
    try std.testing.expectEqualStrings("bash", recipe.shell.?);
    try std.testing.expectEqual(@as(usize, 2), recipe.commands.len);
    try std.testing.expectEqualStrings("npm run build", recipe.commands[0].line);
    try std.testing.expectEqualStrings("npm run test", recipe.commands[1].line);
}

test "parse @shell with quoted path" {
    const source =
        \\task build:
        \\    @shell "/bin/zsh"
        \\    echo "using zsh"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqualStrings("/bin/zsh", recipe.shell.?);
}

test "parse @cd directive in simple recipe" {
    const source =
        \\build:
        \\    @cd ./src
        \\    make all
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqualStrings("build", recipe.name);
    try std.testing.expectEqualStrings("./src", recipe.working_dir.?);
    try std.testing.expectEqual(@as(usize, 1), recipe.commands.len);
}

test "parse @shell directive in simple recipe" {
    const source =
        \\build:
        \\    @shell zsh
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqualStrings("zsh", recipe.shell.?);
}

test "parse @cd directive in file recipe" {
    const source =
        \\file dist/app.js: src/*.ts
        \\    @cd ./frontend
        \\    npm run build
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqualStrings("./frontend", recipe.working_dir.?);
    try std.testing.expectEqual(@as(usize, 1), recipe.commands.len);
}
