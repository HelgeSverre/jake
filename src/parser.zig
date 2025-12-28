// Jake Parser - Builds AST from tokens

const std = @import("std");
const lexer = @import("lexer.zig");
const Token = lexer.Token;
const Lexer = lexer.Lexer;

pub const Recipe = struct {
    name: []const u8,
    kind: Kind,
    dependencies: []const []const u8,
    file_deps: []const []const u8, // File patterns for file targets
    output: ?[]const u8, // Output file for file targets
    params: []const Param,
    commands: []const Command,
    doc_comment: ?[]const u8,
    is_default: bool,

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
        import,
        default,
        builtin,
        before,
        after,
        on_error,
    };
};

pub const Jakefile = struct {
    variables: []const Variable,
    recipes: []const Recipe,
    directives: []const Directive,
    source: []const u8,

    pub fn deinit(self: *Jakefile, allocator: std.mem.Allocator) void {
        allocator.free(self.variables);
        for (self.recipes) |recipe| {
            allocator.free(recipe.dependencies);
            allocator.free(recipe.file_deps);
            allocator.free(recipe.params);
            allocator.free(recipe.commands);
        }
        allocator.free(self.recipes);
        for (self.directives) |directive| {
            allocator.free(directive.args);
        }
        allocator.free(self.directives);
    }

    pub fn getRecipe(self: *const Jakefile, name: []const u8) ?*const Recipe {
        for (self.recipes) |*recipe| {
            if (std.mem.eql(u8, recipe.name, name)) {
                return recipe;
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

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: *Lexer,
    current: Token,
    source: []const u8,

    // Accumulators
    variables: std.ArrayListUnmanaged(Variable),
    recipes: std.ArrayListUnmanaged(Recipe),
    directives: std.ArrayListUnmanaged(Directive),

    pub fn init(allocator: std.mem.Allocator, lex: *Lexer) Parser {
        return .{
            .allocator = allocator,
            .lexer = lex,
            .current = lex.next(),
            .source = lex.source,
            .variables = .empty,
            .recipes = .empty,
            .directives = .empty,
        };
    }

    fn advance(self: *Parser) void {
        self.current = self.lexer.next();
    }

    fn skipNewlines(self: *Parser) void {
        while (self.current.tag == .newline or self.current.tag == .comment) {
            self.advance();
        }
    }

    fn expect(self: *Parser, tag: Token.Tag) ParseError!Token {
        if (self.current.tag != tag) {
            return ParseError.UnexpectedToken;
        }
        const tok = self.current;
        self.advance();
        return tok;
    }

    fn slice(self: *Parser, tok: Token) []const u8 {
        return tok.slice(self.source);
    }

    pub fn parseJakefile(self: *Parser) ParseError!Jakefile {
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

        // Other directives
        const kind: Directive.Kind = switch (self.current.tag) {
            .kw_dotenv => .dotenv,
            .kw_require => .require,
            .kw_import => .import,
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
        _ = try self.expect(.colon);

        var deps: std.ArrayListUnmanaged([]const u8) = .empty;

        // Parse dependencies
        if (self.current.tag == .l_bracket) {
            self.advance();
            while (self.current.tag != .r_bracket and self.current.tag != .eof) {
                if (self.current.tag == .ident) {
                    deps.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
                }
                self.advance();
                if (self.current.tag == .comma) self.advance();
            }
            if (self.current.tag == .r_bracket) self.advance();
        }

        self.skipNewlines();

        // Parse commands (indented lines)
        var commands: std.ArrayListUnmanaged(Recipe.Command) = .empty;
        while (self.current.tag == .indent) {
            self.advance();
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

        self.recipes.append(self.allocator, .{
            .name = name,
            .kind = .simple,
            .dependencies = deps.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .file_deps = &[_][]const u8{},
            .output = null,
            .params = &[_]Recipe.Param{},
            .commands = commands.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .doc_comment = null,
            .is_default = false,
        }) catch return ParseError.OutOfMemory;
    }

    fn parseTaskRecipe(self: *Parser) ParseError!void {
        _ = try self.expect(.kw_task);

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

        _ = try self.expect(.colon);

        // Parse dependencies
        if (self.current.tag == .l_bracket) {
            self.advance();
            while (self.current.tag != .r_bracket and self.current.tag != .eof) {
                if (self.current.tag == .ident) {
                    deps.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
                }
                self.advance();
                if (self.current.tag == .comma) self.advance();
            }
            if (self.current.tag == .r_bracket) self.advance();
        }

        self.skipNewlines();

        // Parse commands
        var commands: std.ArrayListUnmanaged(Recipe.Command) = .empty;
        while (self.current.tag == .indent) {
            self.advance();

            // Check for directive
            var directive: ?Recipe.CommandDirective = null;
            if (self.current.tag == .at) {
                self.advance();
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
                    else => null,
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

        self.recipes.append(self.allocator, .{
            .name = name,
            .kind = .task,
            .dependencies = deps.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .file_deps = &[_][]const u8{},
            .output = null,
            .params = params.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .commands = commands.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .doc_comment = null,
            .is_default = false,
        }) catch return ParseError.OutOfMemory;
    }

    fn parseFileRecipe(self: *Parser) ParseError!void {
        _ = try self.expect(.kw_file);

        // Output file
        const output = self.slice(self.current);
        self.advance();

        _ = try self.expect(.colon);

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

        // Parse commands
        var commands: std.ArrayListUnmanaged(Recipe.Command) = .empty;
        while (self.current.tag == .indent) {
            self.advance();
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

        // Use output as recipe name
        self.recipes.append(self.allocator, .{
            .name = output,
            .kind = .file,
            .dependencies = &[_][]const u8{},
            .file_deps = file_deps.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .output = output,
            .params = &[_]Recipe.Param{},
            .commands = commands.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory,
            .doc_comment = null,
            .is_default = false,
        }) catch return ParseError.OutOfMemory;
    }
};

fn stripQuotes(s: []const u8) []const u8 {
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
    var parser = Parser.init(std.testing.allocator, &lex);
    const jakefile = try parser.parseJakefile();

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
    var parser = Parser.init(std.testing.allocator, &lex);
    const jakefile = try parser.parseJakefile();

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
    var parser = Parser.init(std.testing.allocator, &lex);
    const jakefile = try parser.parseJakefile();

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].dependencies.len);
}
