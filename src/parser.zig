//! Builds an AST (Jakefile struct) from a token stream.

const std = @import("std");
const lexer = @import("lexer.zig");
const hooks_mod = @import("hooks.zig");
const Token = lexer.Token;
const Lexer = lexer.Lexer;
const Hook = hooks_mod.Hook;

/// A recipe definition: task, file target, or simple command group.
pub const Recipe = struct {
    name: []const u8,
    loc: Token.Loc = .{ .start = 0, .end = 0, .line = 0, .column = 0 },
    origin: ?RecipeOrigin = null,
    kind: Kind,
    dependencies: []const []const u8,
    file_deps: []const []const u8, // File patterns for file targets
    output: ?[]const u8, // Output file for file targets
    params: []const Param,
    commands: []const Command,
    pre_hooks: []const Hook, // @pre commands to run before recipe
    post_hooks: []const Hook, // @post commands to run after recipe
    on_error_hooks: []const Hook, // @on_error commands to run if recipe fails
    doc_comment: ?[]const u8,
    is_default: bool,
    aliases: []const []const u8, // Alternative names for this recipe
    group: ?[]const u8, // Recipe group/category for organization
    description: ?[]const u8, // Recipe description (distinct from doc_comment)
    shell: ?[]const u8, // Shell to use (e.g., "bash", "zsh", "powershell")
    working_dir: ?[]const u8, // Working directory for recipe execution
    only_os: []const []const u8, // List of OSes this recipe runs on (e.g., ["linux", "macos"])
    quiet: bool, // Suppress command echoing for this recipe
    hidden: bool, // Hide from recipe listings (alternative to _ prefix)
    needs: []const NeedsRequirement, // Recipe-level command requirements
    requires: []const []const u8 = &.{}, // Recipe-level required env vars (@require before the recipe)
    timeout_seconds: ?u64, // Timeout in seconds, null = no timeout

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
        launch,
    };

    /// Check if recipe is private (hidden from listings)
    /// Hidden if: @hidden directive is set, OR name starts with underscore
    /// Uses origin.original_name for imported recipes to check the original name
    pub fn isPrivate(self: *const Recipe) bool {
        if (self.hidden) return true;
        const name = if (self.origin) |o| o.original_name else self.name;
        return name.len > 0 and name[0] == '_';
    }
};

/// Represents a recipe-level @needs requirement
pub const NeedsRequirement = struct {
    command: []const u8,
    hint: ?[]const u8, // Optional install hint
    install_task: ?[]const u8, // Optional -> task reference (todo: support arbitrary (shell) commands as install action)

};

/// Tracks where a recipe originated from (for imported recipes or external build systems)
pub const RecipeOrigin = struct {
    original_name: []const u8, // Name before prefixing (e.g., "_install")
    import_prefix: ?[]const u8, // Module prefix (e.g., "web"), null if main file
    source_file: ?[]const u8, // Path to source file, null if main file
    external_kind: ?ExternalKind = null, // null for Jake imports, set for Makefile/Justfile
    base_dir: ?[]const u8 = null, // Directory to resolve this recipe's relative paths against (set for @rooted imports)

    pub const ExternalKind = enum { makefile, justfile };
};

/// A variable assignment in a Jakefile.
pub const Variable = struct {
    name: []const u8,
    value: []const u8,
};

/// A top-level directive (@dotenv, @export, @require, etc.).
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
    /// When true, the import directive itself carried a trailing `rooted`
    /// keyword (`@import "x" rooted`), forcing the imported module to resolve
    /// its recipes' relative paths against its own directory — even when the
    /// module's own file did not declare `@rooted`. Monotonic: this OR the
    /// file's `@rooted` roots the module; there is no way to un-root.
    rooted: bool = false,
};

/// Represents a comment in the source file (for formatting preservation)
pub const CommentNode = struct {
    text: []const u8, // Comment text including #
    line: usize, // Line number (0-indexed)
    column: usize, // Column number (0-indexed)
    kind: Kind,

    pub const Kind = enum {
        standalone, // Comment on its own line
        inline_cmd, // Comment after a command on same line
        inline_var, // Comment after a variable on same line
        inline_recipe, // Comment after a recipe header on same line
    };
};

/// The complete parsed AST of a Jakefile.
pub const Jakefile = struct {
    variables: []const Variable,
    recipes: []const Recipe,
    directives: []const Directive,
    imports: []const ImportDirective,
    global_pre_hooks: []const Hook, // Global @pre hooks run before any recipe
    global_post_hooks: []const Hook, // Global @post hooks run after any recipe
    global_on_error_hooks: []const Hook, // Global @on_error hooks run when a recipe fails
    comments: []const CommentNode, // All comments for formatting preservation
    source: []const u8,
    /// When true, this file declared a top-level `@rooted` directive: its
    /// recipes' relative paths (`@cd`, `file` targets) resolve against this
    /// file's own directory when imported from a parent. No-op when run directly.
    rooted: bool = false,

    pub fn deinit(self: *Jakefile, allocator: std.mem.Allocator) void {
        allocator.free(self.variables);
        for (self.recipes) |recipe| {
            allocator.free(recipe.dependencies);
            allocator.free(recipe.file_deps);
            allocator.free(recipe.params);
            allocator.free(recipe.commands);
            allocator.free(recipe.pre_hooks);
            allocator.free(recipe.post_hooks);
            allocator.free(recipe.on_error_hooks);
            allocator.free(recipe.aliases);
            allocator.free(recipe.only_os);
            allocator.free(recipe.needs);
            allocator.free(recipe.requires);
        }
        allocator.free(self.recipes);
        for (self.directives) |directive| {
            allocator.free(directive.args);
        }
        allocator.free(self.directives);
        allocator.free(self.imports);
        allocator.free(self.global_pre_hooks);
        allocator.free(self.global_post_hooks);
        allocator.free(self.global_on_error_hooks);
        allocator.free(self.comments);
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
    InvalidTimeoutFormat,
    InvalidTimeoutValue,
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

    /// Format the error message with source context and a caret marker.
    pub fn formatDetailedMessage(self: ErrorInfo, source: []const u8, buf: []u8) []const u8 {
        var fbs = std.io.fixedBufferStream(buf);
        self.format("", .{}, fbs.writer()) catch return "error: formatting failed";

        const line_text = getSourceLine(source, self.line) orelse return fbs.getWritten();
        const trimmed_line = std.mem.trimRight(u8, line_text, "\r");

        fbs.writer().writeByte('\n') catch return fbs.getWritten();
        fbs.writer().print("{d} | {s}\n", .{ self.line, trimmed_line }) catch return fbs.getWritten();
        fbs.writer().writeAll("  | ") catch return fbs.getWritten();

        var spaces_remaining = if (self.column > 0) self.column - 1 else 0;
        while (spaces_remaining > 0) : (spaces_remaining -= 1) {
            fbs.writer().writeByte(' ') catch return fbs.getWritten();
        }
        fbs.writer().writeByte('^') catch return fbs.getWritten();
        return fbs.getWritten();
    }
};

fn getSourceLine(source: []const u8, line_number: usize) ?[]const u8 {
    if (line_number == 0) return null;

    var current_line: usize = 1;
    var start: usize = 0;
    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        if (source[i] == '\n') {
            if (current_line == line_number) {
                return source[start..i];
            }
            current_line += 1;
            start = i + 1;
        }
    }

    if (current_line == line_number and start <= source.len) {
        return source[start..];
    }

    return null;
}

/// Parses a token stream into a Jakefile AST.
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
    global_on_error_hooks: std.ArrayListUnmanaged(Hook),
    comments: std.ArrayListUnmanaged(CommentNode),

    // Last error information for detailed reporting
    last_error: ?ErrorInfo,

    // Pending aliases for the next recipe
    pending_aliases: std.ArrayListUnmanaged([]const u8),

    // Pending metadata for next recipe
    pending_group: ?[]const u8,
    pending_description: ?[]const u8,
    pending_only_os: std.ArrayListUnmanaged([]const u8),
    pending_quiet: bool,
    pending_hidden: bool,
    pending_default: bool,
    pending_doc_comment: ?[]const u8,
    pending_needs: std.ArrayListUnmanaged(NeedsRequirement),
    pending_requires: std.ArrayListUnmanaged([]const u8),
    pending_timeout: ?u64,

    // Set when a top-level `@rooted` directive is parsed
    rooted: bool,

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
            .global_on_error_hooks = .empty,
            .comments = .empty,
            .last_error = null,
            .pending_aliases = .empty,
            .pending_group = null,
            .pending_description = null,
            .pending_only_os = .empty,
            .pending_quiet = false,
            .pending_hidden = false,
            .pending_default = false,
            .pending_doc_comment = null,
            .pending_needs = .empty,
            .pending_requires = .empty,
            .pending_timeout = null,
            .rooted = false,
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
            self.allocator.free(recipe.on_error_hooks);
            self.allocator.free(recipe.aliases);
            self.allocator.free(recipe.only_os);
            self.allocator.free(recipe.needs);
            self.allocator.free(recipe.requires);
        }
        self.recipes.deinit(self.allocator);
        for (self.directives.items) |directive| {
            self.allocator.free(directive.args);
        }
        self.directives.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.global_pre_hooks.deinit(self.allocator);
        self.global_post_hooks.deinit(self.allocator);
        self.global_on_error_hooks.deinit(self.allocator);
        self.comments.deinit(self.allocator);
        self.pending_aliases.deinit(self.allocator);
        self.pending_only_os.deinit(self.allocator);
        self.pending_needs.deinit(self.allocator);
        self.pending_requires.deinit(self.allocator);
    }

    fn advance(self: *Parser) void {
        self.current = self.lexer.next();
    }

    /// Get the last error information, if any
    pub fn getLastError(self: *const Parser) ?ErrorInfo {
        return self.last_error;
    }

    /// Capture a comment token into the comments list
    fn captureComment(self: *Parser, kind: CommentNode.Kind) ParseError!void {
        if (self.current.tag != .comment) return;

        const comment_text = self.slice(self.current);
        try self.comments.append(self.allocator, .{
            .text = comment_text,
            .line = self.current.loc.line,
            .column = self.current.loc.column,
            .kind = kind,
        });
    }

    fn skipNewlines(self: *Parser) ParseError!void {
        var saw_blank_line = false;

        while (self.current.tag == .newline or self.current.tag == .comment) {
            if (self.current.tag == .newline) {
                // Two consecutive newlines = blank line, clear doc comment
                if (saw_blank_line) {
                    self.pending_doc_comment = null;
                }
                saw_blank_line = true;
            } else if (self.current.tag == .comment) {
                // Capture all comments for formatting preservation
                try self.captureComment(.standalone);

                // Also track as potential doc comment for next recipe
                // Only comments immediately before a recipe (no blank lines) are kept
                const comment_text = self.slice(self.current);
                if (comment_text.len > 1 and comment_text[0] == '#') {
                    self.pending_doc_comment = std.mem.trimLeft(u8, comment_text[1..], " ");
                }
                saw_blank_line = false; // Reset - comment breaks the blank line sequence
            }
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

    /// Consume and return pending quiet flag, clearing it for the next recipe
    fn consumePendingQuiet(self: *Parser) bool {
        const quiet = self.pending_quiet;
        self.pending_quiet = false;
        return quiet;
    }

    /// Consume and return pending hidden flag, clearing it for the next recipe
    fn consumePendingHidden(self: *Parser) bool {
        const hidden = self.pending_hidden;
        self.pending_hidden = false;
        return hidden;
    }

    /// Consume and return pending timeout, clearing it for the next recipe
    fn consumePendingTimeout(self: *Parser) ?u64 {
        const timeout = self.pending_timeout;
        self.pending_timeout = null;
        return timeout;
    }

    /// Consume and return pending doc comment, clearing it for the next recipe
    fn consumePendingDocComment(self: *Parser) ?[]const u8 {
        const doc = self.pending_doc_comment;
        self.pending_doc_comment = null;
        return doc;
    }

    fn consumePendingDefault(self: *Parser) bool {
        const is_default = self.pending_default;
        self.pending_default = false;
        return is_default;
    }

    /// Consume and return pending only_os, clearing it for the next recipe
    fn consumePendingOnlyOs(self: *Parser) ParseError![]const []const u8 {
        if (self.pending_only_os.items.len == 0) {
            return &[_][]const u8{};
        }
        const only_os = self.pending_only_os.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        return only_os;
    }

    fn consumePendingNeeds(self: *Parser) ParseError![]const NeedsRequirement {
        if (self.pending_needs.items.len == 0) {
            return &[_]NeedsRequirement{};
        }
        return self.pending_needs.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    /// `@require FOO BAR` — required environment variables. Accumulated like
    /// @needs and attached to the following recipe (recipe-scoped); a @require
    /// with no following recipe is flushed as global (see parseJakefile).
    fn parseRequireDirective(self: *Parser) ParseError!void {
        self.advance(); // consume `require`
        while (self.current.tag != .newline and self.current.tag != .eof) {
            if (self.current.tag == .ident or self.current.tag == .string) {
                const name = if (self.current.tag == .string)
                    stripQuotes(self.slice(self.current))
                else
                    self.slice(self.current);
                self.pending_requires.append(self.allocator, name) catch return ParseError.OutOfMemory;
            }
            self.advance();
        }
    }

    fn consumePendingRequires(self: *Parser) ParseError![]const []const u8 {
        if (self.pending_requires.items.len == 0) {
            return &[_][]const u8{};
        }
        return self.pending_requires.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
    }

    /// Parse timeout value from string (e.g., "30s", "5m", "2h")
    /// Returns timeout in seconds
    fn parseTimeoutValue(self: *Parser, value_str: []const u8) ParseError!u64 {
        _ = self;
        if (value_str.len < 2) {
            return ParseError.InvalidTimeoutFormat;
        }

        // Extract numeric part and unit suffix
        const unit = value_str[value_str.len - 1];
        const num_str = value_str[0 .. value_str.len - 1];

        // Parse numeric value
        const num = std.fmt.parseInt(u64, num_str, 10) catch {
            return ParseError.InvalidTimeoutFormat;
        };

        if (num == 0) {
            return ParseError.InvalidTimeoutValue;
        }

        // Convert to seconds based on unit
        const seconds: u64 = switch (unit) {
            's' => num,
            'm' => num * 60,
            'h' => num * 3600,
            else => return ParseError.InvalidTimeoutFormat,
        };

        return seconds;
    }

    /// Check if current token can be used as a name (identifier or keyword in name position).
    /// Keywords like "default", "import", "as" etc. are valid as recipe/variable names.
    fn isNameToken(self: *Parser) bool {
        return switch (self.current.tag) {
            .ident => true,
            // Allow keywords as names in identifier position
            .kw_default, .kw_import, .kw_as, .kw_if, .kw_elif, .kw_else, .kw_end => true,
            .kw_task, .kw_file, .kw_dotenv, .kw_rooted, .kw_require, .kw_watch, .kw_cache => true,
            .kw_needs, .kw_confirm, .kw_group, .kw_desc, .kw_platform, .kw_quiet => true,
            .kw_hidden, .kw_export, .kw_alias, .kw_shell, .kw_cd, .kw_pre, .kw_post => true,
            .kw_on_error, .kw_timeout, .kw_ignore, .kw_each => true,
            else => false,
        };
    }

    pub fn parseJakefile(self: *Parser) ParseError!Jakefile {
        errdefer self.deinit();

        while (self.current.tag != .eof) {
            try self.skipNewlines();

            if (self.current.tag == .eof) break;

            switch (self.current.tag) {
                .at => try self.parseDirective(),
                .ident => try self.parseVariableOrRecipe(),
                .kw_task => try self.parseTaskRecipe(),
                .kw_file => try self.parseFileRecipe(),
                .comment => {
                    // Capture all comments for formatting preservation
                    try self.captureComment(.standalone);

                    // Store comment as potential doc comment for next recipe
                    // Only kept if immediately before recipe (no blank lines)
                    const comment_text = self.slice(self.current);
                    if (comment_text.len > 1 and comment_text[0] == '#') {
                        self.pending_doc_comment = std.mem.trimLeft(u8, comment_text[1..], " ");
                    }
                    self.advance();
                },
                .newline => self.advance(),
                else => {
                    self.setError("unexpected token at top level", null);
                    return ParseError.UnexpectedToken;
                },
            }
        }

        if (self.pending_default) {
            self.setError("expected recipe after '@default'", null);
            return ParseError.UnexpectedToken;
        }

        // A @require with no following recipe never got consumed by finalizeRecipe;
        // flush it as a global directive (validated on any execution).
        if (self.pending_requires.items.len > 0) {
            const args = self.pending_requires.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
            self.directives.append(self.allocator, .{ .kind = .require, .args = args }) catch return ParseError.OutOfMemory;
        }

        var result = Jakefile{
            .variables = &.{},
            .recipes = &.{},
            .directives = &.{},
            .imports = &.{},
            .global_pre_hooks = &.{},
            .global_post_hooks = &.{},
            .global_on_error_hooks = &.{},
            .comments = &.{},
            .source = self.source,
            .rooted = self.rooted,
        };
        errdefer result.deinit(self.allocator);

        result.variables = self.variables.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        result.recipes = self.recipes.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        result.directives = self.directives.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        result.imports = self.imports.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        result.global_pre_hooks = self.global_pre_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        result.global_post_hooks = self.global_post_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        result.global_on_error_hooks = self.global_on_error_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        result.comments = self.comments.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;

        return result;
    }

    /// Parse a top-level `@directive`. Dispatches to per-directive handlers
    /// after consuming the leading `@`. Each handler is responsible for
    /// advancing past its own keyword.
    fn parseDirective(self: *Parser) ParseError!void {
        _ = try self.expect(.at);

        switch (self.current.tag) {
            .kw_default => try self.parseDefaultDirective(),
            .kw_import => {
                self.advance();
                try self.parseImportDirective();
            },
            .kw_alias => try self.parseAliasDirective(),
            .kw_group => try self.parseGroupDirective(),
            .kw_desc => try self.parseDescDirective(),
            .kw_platform => try self.parsePlatformDirective(),
            .kw_quiet => try self.parseQuietDirective(),
            .kw_hidden => try self.parseHiddenDirective(),
            .kw_timeout => try self.parseTimeoutDirective(),
            .kw_needs => try self.parseNeedsDirective(),
            .kw_pre, .kw_post => try self.parseGlobalHookDirective(),
            .kw_before, .kw_after => try self.parseTargetedHookDirective(),
            .kw_on_error => try self.parseOnErrorDirective(),
            .newline, .eof => {
                self.setError("expected directive name after '@'", null);
                return ParseError.UnexpectedToken;
            },
            .kw_dotenv, .kw_export => try self.parseGenericDirective(),
            .kw_rooted => try self.parseRootedDirective(),
            .kw_require => try self.parseRequireDirective(),
            else => {
                self.setError("unknown directive", null);
                return ParseError.UnexpectedToken;
            },
        }
    }

    /// Skip remaining tokens on the current logical line.
    fn skipToEndOfLine(self: *Parser) void {
        while (self.current.tag != .newline and self.current.tag != .eof) {
            self.advance();
        }
    }

    fn parseDefaultDirective(self: *Parser) ParseError!void {
        self.advance();
        self.pending_default = true;

        if (self.current.tag != .newline and self.current.tag != .eof and self.current.tag != .comment) {
            self.setError("expected recipe after '@default'", null);
            return ParseError.UnexpectedToken;
        }

        self.skipToEndOfLine();
    }

    fn parseAliasDirective(self: *Parser) ParseError!void {
        self.advance();
        while (self.current.tag != .newline and self.current.tag != .eof) {
            if (self.current.tag == .ident) {
                self.pending_aliases.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
            }
            self.advance();
        }
    }

    fn parseGroupDirective(self: *Parser) ParseError!void {
        self.advance();
        if (self.current.tag == .ident or self.current.tag == .string) {
            self.pending_group = stripQuotes(self.slice(self.current));
            self.advance();
        }
        self.skipToEndOfLine();
    }

    fn parseDescDirective(self: *Parser) ParseError!void {
        self.advance();
        // Clear doc_comment when explicit description is provided
        self.pending_doc_comment = null;

        if (self.current.tag == .string) {
            self.pending_description = stripQuotes(self.slice(self.current));
            self.advance();
        } else {
            // Collect everything until newline as description
            const desc_start = self.current.loc.start;
            self.skipToEndOfLine();
            const desc_end = self.current.loc.start;
            const desc = std.mem.trim(u8, self.source[desc_start..desc_end], " \t");
            if (desc.len > 0) {
                self.pending_description = desc;
            }
            return;
        }

        self.skipToEndOfLine();
    }

    fn parsePlatformDirective(self: *Parser) ParseError!void {
        self.advance();
        while (self.current.tag != .newline and self.current.tag != .eof) {
            if (self.current.tag == .ident) {
                self.pending_only_os.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
            }
            self.advance();
        }
    }

    fn parseQuietDirective(self: *Parser) ParseError!void {
        self.advance();
        self.pending_quiet = true;
        self.skipToEndOfLine();
    }

    fn parseHiddenDirective(self: *Parser) ParseError!void {
        self.advance();
        self.pending_hidden = true;
        self.skipToEndOfLine();
    }

    /// `@timeout 30s` | `@timeout 5m` | `@timeout 2h`
    fn parseTimeoutDirective(self: *Parser) ParseError!void {
        self.advance();

        // Value is either a single ident ("30s") or number + unit ident ("30" + "s").
        var timeout_str: []const u8 = undefined;

        if (self.current.tag == .ident) {
            timeout_str = self.slice(self.current);
            self.advance();
        } else if (self.current.tag == .number) {
            const num_start = self.current.loc.start;
            self.advance();

            if (self.current.tag == .ident) {
                const unit_end = self.current.loc.end;
                timeout_str = self.source[num_start..unit_end];
                self.advance();
            } else {
                self.setError("Expected time unit (s, m, or h) after number", .ident);
                return ParseError.InvalidTimeoutFormat;
            }
        } else {
            self.setError("Expected timeout value (e.g., 30s, 5m, 2h)", null);
            return ParseError.InvalidTimeoutFormat;
        }

        const timeout_seconds = self.parseTimeoutValue(timeout_str) catch |err| {
            const msg = switch (err) {
                ParseError.InvalidTimeoutFormat => "Invalid timeout format. Expected format: 30s, 5m, or 2h",
                ParseError.InvalidTimeoutValue => "Timeout must be a positive value",
                else => "Failed to parse timeout",
            };
            self.setError(msg, null);
            return ParseError.InvalidTimeoutFormat;
        };

        self.pending_timeout = timeout_seconds;
        self.skipToEndOfLine();
    }

    /// `@needs cmd1 cmd2 ...` | `@needs cmd "hint"` | `@needs cmd -> install-task`
    fn parseNeedsDirective(self: *Parser) ParseError!void {
        self.advance();

        while (self.current.tag != .newline and self.current.tag != .eof) {
            if (self.current.tag == .ident or self.current.tag == .string) {
                const cmd = if (self.current.tag == .string)
                    stripQuotes(self.slice(self.current))
                else
                    self.slice(self.current);
                self.advance();

                var hint: ?[]const u8 = null;
                var install_task: ?[]const u8 = null;

                if (self.current.tag == .string) {
                    hint = stripQuotes(self.slice(self.current));
                    self.advance();
                }

                if (self.current.tag == .arrow) {
                    self.advance();
                    if (self.current.tag == .ident) {
                        install_task = self.slice(self.current);
                        self.advance();
                    }
                }

                self.pending_needs.append(self.allocator, .{
                    .command = cmd,
                    .hint = hint,
                    .install_task = install_task,
                }) catch return ParseError.OutOfMemory;
            } else {
                self.advance(); // Skip commas, etc.
            }
        }
    }

    /// Global `@pre` / `@post` hook (no recipe target).
    fn parseGlobalHookDirective(self: *Parser) ParseError!void {
        const hook_kind: Hook.Kind = if (self.current.tag == .kw_pre) .pre else .post;
        self.advance();
        try self.appendHookFromRemainingLine(hook_kind, null);
    }

    /// Targeted `@before recipe` / `@after recipe` hook.
    fn parseTargetedHookDirective(self: *Parser) ParseError!void {
        const hook_kind: Hook.Kind = if (self.current.tag == .kw_before) .pre else .post;
        self.advance();

        if (!self.isNameToken()) {
            self.setError("expected recipe name after targeted hook directive", .ident);
            return ParseError.UnexpectedToken;
        }
        const target_recipe = self.slice(self.current);
        self.advance();

        try self.appendHookFromRemainingLine(hook_kind, target_recipe);
    }

    /// Trim and capture the rest of the current line as a hook command, then
    /// append to the appropriate global hook list.
    fn appendHookFromRemainingLine(self: *Parser, kind: Hook.Kind, target: ?[]const u8) ParseError!void {
        const cmd_start = self.current.loc.start;
        self.skipToEndOfLine();
        const cmd_end = self.current.loc.start;
        const command = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t\r");

        const hook = Hook{
            .command = command,
            .kind = kind,
            .recipe_name = target,
        };

        switch (kind) {
            .pre => self.global_pre_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
            .post => self.global_post_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
            .on_error => {}, // Routed through parseOnErrorDirective instead.
        }
    }

    /// Top-level `@on_error cmd...` — global error hook that runs whenever
    /// any recipe fails. Use body-level `@on_error` inside a recipe to attach
    /// a recipe-specific error handler.
    fn parseOnErrorDirective(self: *Parser) ParseError!void {
        self.advance();

        const cmd_start = self.current.loc.start;
        self.skipToEndOfLine();
        const cmd_end = self.current.loc.start;
        const command = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t\r");

        self.global_on_error_hooks.append(self.allocator, .{
            .command = command,
            .kind = .on_error,
            .recipe_name = null,
        }) catch return ParseError.OutOfMemory;
    }

    /// `@dotenv`, `@require`, `@export` — directives that collect free-form
    /// arguments until end of line.
    fn parseGenericDirective(self: *Parser) ParseError!void {
        const kind: Directive.Kind = switch (self.current.tag) {
            .kw_dotenv => .dotenv,
            .kw_require => .require,
            .kw_export => .@"export",
            else => unreachable, // dispatcher restricts the tags reaching here
        };

        self.advance();

        var args: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer args.deinit(self.allocator);
        while (self.current.tag != .newline and self.current.tag != .eof) {
            if (self.current.tag == .ident or self.current.tag == .string or self.current.tag == .glob_pattern) {
                args.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
            }
            self.advance();
        }

        const owned_args = args.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        errdefer self.allocator.free(owned_args);
        self.directives.append(self.allocator, .{
            .kind = kind,
            .args = owned_args,
        }) catch return ParseError.OutOfMemory;
    }

    /// `@rooted` — a module-level flag (no args). Marks this file so its
    /// recipes' relative paths resolve against its own directory when imported.
    fn parseRootedDirective(self: *Parser) ParseError!void {
        self.advance(); // consume `rooted`
        self.rooted = true;
        // No arguments; skip anything trailing on the line (e.g. a comment).
        self.skipToEndOfLine();
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
            self.setError("expected import path after '@import'", null);
            return ParseError.UnexpectedToken;
        }

        // Check for optional "as prefix" suffix
        var prefix: ?[]const u8 = null;
        if (self.current.tag == .kw_as) {
            self.advance();
            if (self.current.tag == .ident) {
                prefix = self.slice(self.current);
                self.advance();
            } else {
                self.setError("expected import prefix after 'as'", .ident);
                return ParseError.UnexpectedToken;
            }
        }

        // Check for optional trailing `rooted` modifier. The importer can force
        // the module to be rooted without editing it. Additive-only: there is
        // no `unrooted`.
        var rooted = false;
        if (self.current.tag == .kw_rooted) {
            rooted = true;
            self.advance();
        }

        // Skip any remaining tokens on the line
        while (self.current.tag != .newline and self.current.tag != .eof) {
            self.advance();
        }

        self.imports.append(self.allocator, .{
            .path = path,
            .prefix = prefix,
            .rooted = rooted,
        }) catch return ParseError.OutOfMemory;
    }

    fn parseVariableOrRecipe(self: *Parser) ParseError!void {
        const name_tok = self.current;
        const name = self.slice(name_tok);
        self.advance();

        if (self.current.tag == .equals) {
            if (self.pending_default) {
                self.setError("expected recipe after '@default'", null);
                return ParseError.UnexpectedToken;
            }
            // Variable assignment: name = value
            self.advance();
            const value = if (self.current.tag == .string or self.current.tag == .ident or self.current.tag == .glob_pattern or self.current.tag == .number)
                self.slice(self.current)
            else
                "";
            if (self.current.tag != .newline and self.current.tag != .eof) {
                self.advance();
            }
            self.variables.append(self.allocator, .{ .name = name, .value = stripQuotes(value) }) catch return ParseError.OutOfMemory;
        } else if (self.current.tag == .colon) {
            // Simple recipe: name: [deps]
            try self.parseSimpleRecipe(name, name_tok.loc);
        } else {
            self.setError("expected '=' for variable assignment or ':' for recipe definition", null);
            return ParseError.UnexpectedToken;
        }
    }

    /// Inputs to finalizeRecipe. Kind-specific list pointers are optional;
    /// when null the corresponding Recipe field is set to an empty slice.
    const RecipeInputs = struct {
        name: []const u8,
        name_loc: Token.Loc,
        kind: Recipe.Kind,
        deps: ?*std.ArrayListUnmanaged([]const u8) = null,
        file_deps: ?*std.ArrayListUnmanaged([]const u8) = null,
        output: ?[]const u8 = null,
        params: ?*std.ArrayListUnmanaged(Recipe.Param) = null,
        commands: *std.ArrayListUnmanaged(Recipe.Command),
        pre_hooks: *std.ArrayListUnmanaged(Hook),
        post_hooks: *std.ArrayListUnmanaged(Hook),
        on_error_hooks: *std.ArrayListUnmanaged(Hook),
        shell: ?[]const u8 = null,
        working_dir: ?[]const u8 = null,
    };

    /// Convert builder lists to owned slices, drain pending metadata, and
    /// append the assembled Recipe. Centralizes the finalization logic
    /// shared by parseSimpleRecipe / parseTaskRecipe / parseFileRecipe.
    fn finalizeRecipe(self: *Parser, info: RecipeInputs) ParseError!void {
        const aliases = try self.consumePendingAliases();
        errdefer self.allocator.free(aliases);
        const only_os = try self.consumePendingOnlyOs();
        errdefer self.allocator.free(only_os);
        const needs = try self.consumePendingNeeds();
        errdefer self.allocator.free(needs);
        const requires = try self.consumePendingRequires();
        errdefer self.allocator.free(requires);

        const owned_deps: []const []const u8 = if (info.deps) |d|
            (d.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory)
        else
            &[_][]const u8{};
        errdefer self.allocator.free(owned_deps);

        const owned_file_deps: []const []const u8 = if (info.file_deps) |fd|
            (fd.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory)
        else
            &[_][]const u8{};
        errdefer self.allocator.free(owned_file_deps);

        const owned_params: []const Recipe.Param = if (info.params) |p|
            (p.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory)
        else
            &[_]Recipe.Param{};
        errdefer self.allocator.free(owned_params);

        const owned_commands = info.commands.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        errdefer self.allocator.free(owned_commands);
        const owned_pre_hooks = info.pre_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        errdefer self.allocator.free(owned_pre_hooks);
        const owned_post_hooks = info.post_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        errdefer self.allocator.free(owned_post_hooks);
        const owned_on_error_hooks = info.on_error_hooks.toOwnedSlice(self.allocator) catch return ParseError.OutOfMemory;
        errdefer self.allocator.free(owned_on_error_hooks);

        self.recipes.append(self.allocator, .{
            .name = info.name,
            .loc = info.name_loc,
            .kind = info.kind,
            .dependencies = owned_deps,
            .file_deps = owned_file_deps,
            .output = info.output,
            .params = owned_params,
            .commands = owned_commands,
            .pre_hooks = owned_pre_hooks,
            .post_hooks = owned_post_hooks,
            .on_error_hooks = owned_on_error_hooks,
            .doc_comment = self.consumePendingDocComment(),
            .is_default = self.consumePendingDefault(),
            .aliases = aliases,
            .group = self.consumePendingGroup(),
            .description = self.consumePendingDescription(),
            .shell = info.shell,
            .working_dir = info.working_dir,
            .only_os = only_os,
            .quiet = self.consumePendingQuiet(),
            .hidden = self.consumePendingHidden(),
            .needs = needs,
            .requires = requires,
            .timeout_seconds = self.consumePendingTimeout(),
        }) catch return ParseError.OutOfMemory;
    }

    /// Parse the indented command body shared by simple/task/file recipes.
    /// Handles @pre/@post/@on_error hooks, @cd, @shell, command-level directives
    /// (@needs, @cache, @if, @each, …), and plain commands (including `@cmd`
    /// silent form). Consolidating this here means every recipe kind understands
    /// the full directive set — previously only `task` recipes did, so a
    /// `@needs` inside a `file` or simple recipe leaked to the shell (jake#21).
    fn parseRecipeBody(
        self: *Parser,
        recipe_name: []const u8,
        commands: *std.ArrayListUnmanaged(Recipe.Command),
        pre_hooks: *std.ArrayListUnmanaged(Hook),
        post_hooks: *std.ArrayListUnmanaged(Hook),
        on_error_hooks: *std.ArrayListUnmanaged(Hook),
        working_dir: *?[]const u8,
        shell: *?[]const u8,
    ) ParseError!void {
        while (true) {
            // Skip blank lines that appear between commands so recipe bodies
            // can use vertical whitespace for grouping. Without this, a blank
            // line silently terminated the recipe body (parser landed back at
            // top level and the next indented line failed with "unexpected token").
            while (self.current.tag == .newline) self.advance();
            if (self.current.tag != .indent) break;
            self.advance();

            // Check for directive
            var directive: ?Recipe.CommandDirective = null;
            var at_pos: ?usize = null; // Track @ position for commands like @echo
            if (self.current.tag == .at) {
                at_pos = self.current.loc.start;
                self.advance();

                // Check for @pre / @post / @on_error hook
                if (self.current.tag == .kw_pre or self.current.tag == .kw_post or self.current.tag == .kw_on_error) {
                    const hook_kind: Hook.Kind = switch (self.current.tag) {
                        .kw_pre => .pre,
                        .kw_post => .post,
                        .kw_on_error => .on_error,
                        else => unreachable,
                    };
                    self.advance();

                    const cmd_start = self.current.loc.start;
                    while (self.current.tag != .newline and self.current.tag != .eof) {
                        self.advance();
                    }
                    const cmd_end = self.current.loc.start;
                    const command = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t\r");

                    const hook = Hook{
                        .command = command,
                        .kind = hook_kind,
                        .recipe_name = recipe_name,
                    };

                    switch (hook_kind) {
                        .pre => pre_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
                        .post => post_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
                        .on_error => on_error_hooks.append(self.allocator, hook) catch return ParseError.OutOfMemory,
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
                    working_dir.* = stripQuotes(std.mem.trim(u8, self.source[path_start..path_end], " \t"));
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
                    shell.* = stripQuotes(std.mem.trim(u8, self.source[shell_start..shell_end], " \t"));
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
                    .kw_launch => .launch,
                    else => null, // Unknown directive
                };
            }

            // For commands with @ prefix but no recognized directive (like @echo),
            // include the @ in the command line
            const cmd_start = if (directive == null and at_pos != null)
                at_pos.?
            else
                self.current.loc.start;
            while (self.current.tag != .newline and self.current.tag != .eof) {
                self.advance();
            }
            const cmd_end = self.current.loc.start;

            commands.append(self.allocator, .{
                .line = std.mem.trim(u8, self.source[cmd_start..cmd_end], " \t\r"),
                .directive = directive,
            }) catch return ParseError.OutOfMemory;

            if (self.current.tag == .newline) self.advance();
        }
    }

    fn parseSimpleRecipe(self: *Parser, name: []const u8, name_loc: Token.Loc) ParseError!void {
        _ = try self.expectWithMessage(.colon, "expected ':' after recipe name");

        var deps: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer deps.deinit(self.allocator);

        // Parse dependencies (can be identifiers or paths like dist/app.js)
        if (self.current.tag == .l_bracket) {
            self.advance();
            while (self.current.tag != .r_bracket and self.current.tag != .eof) {
                if (self.isNameToken() or self.current.tag == .glob_pattern) {
                    deps.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
                }
                self.advance();
                if (self.current.tag == .comma) self.advance();
            }
            if (self.current.tag == .r_bracket) self.advance();
        } else {
            while (self.current.tag != .newline and self.current.tag != .eof) {
                if (self.isNameToken() or self.current.tag == .glob_pattern) {
                    deps.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
                }
                self.advance();
                if (self.current.tag == .comma) self.advance();
            }
        }

        try self.skipNewlines();

        // Parse commands and hooks (indented lines)
        var commands: std.ArrayListUnmanaged(Recipe.Command) = .empty;
        var pre_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var post_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var on_error_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        errdefer commands.deinit(self.allocator);
        errdefer pre_hooks.deinit(self.allocator);
        errdefer post_hooks.deinit(self.allocator);
        errdefer on_error_hooks.deinit(self.allocator);
        var working_dir: ?[]const u8 = null;
        var shell: ?[]const u8 = null;

        try self.parseRecipeBody(name, &commands, &pre_hooks, &post_hooks, &on_error_hooks, &working_dir, &shell);

        try self.finalizeRecipe(.{
            .name = name,
            .name_loc = name_loc,
            .kind = .simple,
            .deps = &deps,
            .commands = &commands,
            .pre_hooks = &pre_hooks,
            .post_hooks = &post_hooks,
            .on_error_hooks = &on_error_hooks,
            .shell = shell,
            .working_dir = working_dir,
        });
    }

    fn parseTaskRecipe(self: *Parser) ParseError!void {
        _ = try self.expect(.kw_task);

        if (!self.isNameToken()) {
            self.setError("expected task name after 'task'", .ident);
            return ParseError.UnexpectedToken;
        }

        const name = self.slice(self.current);
        const name_loc = self.current.loc;
        self.advance();

        var params: std.ArrayListUnmanaged(Recipe.Param) = .empty;
        var deps: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer params.deinit(self.allocator);
        errdefer deps.deinit(self.allocator);

        // Parse parameters (name=default). Accept reserved keywords as param
        // names (issue #23): a param name is an unambiguous position where a
        // directive keyword can never appear, so treat them as identifiers.
        while (self.isNameToken()) {
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
                if (self.isNameToken() or self.current.tag == .glob_pattern) {
                    deps.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
                }
                self.advance();
                if (self.current.tag == .comma) self.advance();
            }
            if (self.current.tag == .r_bracket) self.advance();
        } else {
            while (self.current.tag != .newline and self.current.tag != .eof) {
                if (self.isNameToken() or self.current.tag == .glob_pattern) {
                    deps.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
                }
                self.advance();
                if (self.current.tag == .comma) self.advance();
            }
        }

        try self.skipNewlines();

        // Parse commands and hooks
        var commands: std.ArrayListUnmanaged(Recipe.Command) = .empty;
        var pre_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var post_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var on_error_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        errdefer commands.deinit(self.allocator);
        errdefer pre_hooks.deinit(self.allocator);
        errdefer post_hooks.deinit(self.allocator);
        errdefer on_error_hooks.deinit(self.allocator);
        var working_dir: ?[]const u8 = null;
        var shell: ?[]const u8 = null;

        try self.parseRecipeBody(name, &commands, &pre_hooks, &post_hooks, &on_error_hooks, &working_dir, &shell);

        try self.finalizeRecipe(.{
            .name = name,
            .name_loc = name_loc,
            .kind = .task,
            .deps = &deps,
            .params = &params,
            .commands = &commands,
            .pre_hooks = &pre_hooks,
            .post_hooks = &post_hooks,
            .on_error_hooks = &on_error_hooks,
            .shell = shell,
            .working_dir = working_dir,
        });
    }

    fn parseFileRecipe(self: *Parser) ParseError!void {
        _ = try self.expect(.kw_file);

        if (!self.isNameToken() and self.current.tag != .glob_pattern) {
            self.setError("expected output filename after 'file'", .ident);
            return ParseError.UnexpectedToken;
        }

        // Output file
        const output = self.slice(self.current);
        const output_loc = self.current.loc;
        self.advance();

        _ = try self.expectWithMessage(.colon, "expected ':' after output filename");

        // File dependencies (globs)
        var file_deps: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer file_deps.deinit(self.allocator);
        while (self.current.tag != .newline and self.current.tag != .eof) {
            if (self.current.tag == .ident or self.current.tag == .glob_pattern) {
                file_deps.append(self.allocator, self.slice(self.current)) catch return ParseError.OutOfMemory;
            }
            self.advance();
            if (self.current.tag == .comma) self.advance();
        }

        try self.skipNewlines();

        // Parse commands and hooks
        var commands: std.ArrayListUnmanaged(Recipe.Command) = .empty;
        var pre_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var post_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        var on_error_hooks: std.ArrayListUnmanaged(Hook) = .empty;
        errdefer commands.deinit(self.allocator);
        errdefer pre_hooks.deinit(self.allocator);
        errdefer post_hooks.deinit(self.allocator);
        errdefer on_error_hooks.deinit(self.allocator);
        var working_dir: ?[]const u8 = null;
        var shell: ?[]const u8 = null;

        try self.parseRecipeBody(output, &commands, &pre_hooks, &post_hooks, &on_error_hooks, &working_dir, &shell);

        // Use output as both recipe name and output path.
        try self.finalizeRecipe(.{
            .name = output,
            .name_loc = output_loc,
            .kind = .file,
            .file_deps = &file_deps,
            .output = output,
            .commands = &commands,
            .pre_hooks = &pre_hooks,
            .post_hooks = &post_hooks,
            .on_error_hooks = &on_error_hooks,
            .shell = shell,
            .working_dir = working_dir,
        });
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

test "parse allows blank lines inside recipe body" {
    // Regression: a blank line previously terminated the recipe and the next
    // indented command parsed as an unexpected top-level token.
    const source =
        \\task build:
        \\    echo "first"
        \\
        \\    # comment after a blank line
        \\    echo "second"
        \\
        \\    echo "third"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    // Three echo commands; the comment is captured as its own command line.
    try std.testing.expectEqual(@as(usize, 4), jakefile.recipes[0].commands.len);
}

test "parser strips trailing CR from command lines (CRLF source)" {
    // CRLF in source must not leave \r at the end of captured directive bodies.
    // Regression: @needs fake-tool was being matched as `fake-tool\r`, breaking
    // PATH lookup on Windows where the source is checked out with CRLF.
    const source = "task build:\r\n    @needs fake-tool\r\n    echo done\r\n";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqual(@as(usize, 2), recipe.commands.len);

    const needs_line = recipe.commands[0].line;
    try std.testing.expect(std.mem.indexOfScalar(u8, needs_line, '\r') == null);
    // The `@` is consumed as a separate token; the captured body starts at `needs`.
    try std.testing.expectEqualStrings("needs fake-tool", needs_line);

    const echo_line = recipe.commands[1].line;
    try std.testing.expect(std.mem.indexOfScalar(u8, echo_line, '\r') == null);
    try std.testing.expectEqualStrings("echo done", echo_line);
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

test "parser error format includes source context" {
    const source =
        \\task build
        \\    echo "oops"
    ;

    const err_info = ErrorInfo{
        .line = 1,
        .column = 11,
        .message = "expected ':' after recipe name",
        .found_tag = .newline,
        .expected_tag = .colon,
    };

    var buf: [512]u8 = undefined;
    const msg = err_info.formatDetailedMessage(source, &buf);
    try std.testing.expect(std.mem.indexOf(u8, msg, "task build") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "^") != null);
}

test "parser rejects unknown directive" {
    const source = "@mystery value";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);

    try std.testing.expectError(ParseError.UnexpectedToken, p.parseJakefile());
    const err = p.getLastError();
    try std.testing.expect(err != null);
    try std.testing.expectEqualStrings("unknown directive", err.?.message);
}

test "parser rejects import directive without path" {
    const source = "@import";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);

    try std.testing.expectError(ParseError.UnexpectedToken, p.parseJakefile());
    const err = p.getLastError();
    try std.testing.expect(err != null);
    try std.testing.expectEqualStrings("expected import path after '@import'", err.?.message);
}

test "parser rejects bare identifier at top level" {
    const source = "build";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);

    try std.testing.expectError(ParseError.UnexpectedToken, p.parseJakefile());
    const err = p.getLastError();
    try std.testing.expect(err != null);
    try std.testing.expectEqualStrings("expected '=' for variable assignment or ':' for recipe definition", err.?.message);
}

test "parser rejects variable assignment after @default" {
    const source =
        \\task build:
        \\    echo "build"
        \\
        \\@default
        \\version = "1.0"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);

    try std.testing.expectError(ParseError.UnexpectedToken, p.parseJakefile());
    const err = p.getLastError();
    try std.testing.expect(err != null);
    try std.testing.expectEqualStrings("expected recipe after '@default'", err.?.message);
}

test "parser rejects trailing tokens after @default" {
    const source =
        \\@default build
        \\task build:
        \\    echo "build"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);

    try std.testing.expectError(ParseError.UnexpectedToken, p.parseJakefile());
    const err = p.getLastError();
    try std.testing.expect(err != null);
    try std.testing.expectEqualStrings("expected recipe after '@default'", err.?.message);
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

test "parse @before targeted hook" {
    const source =
        \\@before build echo "Before build"
        \\
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.global_pre_hooks.len);
    try std.testing.expectEqual(@as(usize, 0), jakefile.global_post_hooks.len);
    try std.testing.expectEqualStrings("echo \"Before build\"", jakefile.global_pre_hooks[0].command);
    try std.testing.expectEqual(Hook.Kind.pre, jakefile.global_pre_hooks[0].kind);
    try std.testing.expectEqualStrings("build", jakefile.global_pre_hooks[0].recipe_name.?);
}

test "parse @after targeted hook" {
    const source =
        \\@after deploy echo "After deploy"
        \\
        \\task deploy:
        \\    echo "deploying"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), jakefile.global_pre_hooks.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.global_post_hooks.len);
    try std.testing.expectEqualStrings("echo \"After deploy\"", jakefile.global_post_hooks[0].command);
    try std.testing.expectEqual(Hook.Kind.post, jakefile.global_post_hooks[0].kind);
    try std.testing.expectEqualStrings("deploy", jakefile.global_post_hooks[0].recipe_name.?);
}

test "parse @on_error global hook" {
    const source =
        \\@on_error echo "Something failed!"
        \\
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.global_on_error_hooks.len);
    try std.testing.expectEqualStrings("echo \"Something failed!\"", jakefile.global_on_error_hooks[0].command);
    try std.testing.expectEqual(Hook.Kind.on_error, jakefile.global_on_error_hooks[0].kind);
    try std.testing.expectEqual(@as(?[]const u8, null), jakefile.global_on_error_hooks[0].recipe_name);
}

test "parse @on_error with command taking string arg is global" {
    // @on_error command "arg" - treated as global because "arg" is not an ident
    const source =
        \\@on_error notify "Build failed!"
        \\
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.global_on_error_hooks.len);
    try std.testing.expectEqualStrings("notify \"Build failed!\"", jakefile.global_on_error_hooks[0].command);
    try std.testing.expectEqual(Hook.Kind.on_error, jakefile.global_on_error_hooks[0].kind);
    try std.testing.expectEqual(@as(?[]const u8, null), jakefile.global_on_error_hooks[0].recipe_name);
}

test "parse body-level @on_error attaches to recipe" {
    const source =
        \\task deploy:
        \\    echo "deploying"
        \\    @on_error notify "Deploy failed!"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqual(@as(usize, 1), recipe.on_error_hooks.len);
    try std.testing.expectEqualStrings("notify \"Deploy failed!\"", recipe.on_error_hooks[0].command);
    try std.testing.expectEqual(Hook.Kind.on_error, recipe.on_error_hooks[0].kind);
    try std.testing.expectEqualStrings("deploy", recipe.on_error_hooks[0].recipe_name.?);
    try std.testing.expectEqual(@as(usize, 0), jakefile.global_on_error_hooks.len);
}

test "parse mixed global and body-level @on_error" {
    const source =
        \\@on_error echo "Global error handler"
        \\
        \\task build:
        \\    echo "building"
        \\    @on_error notify "Build failed!"
        \\
        \\task deploy:
        \\    echo "deploying"
        \\    @on_error rollback --auto
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // One global hook
    try std.testing.expectEqual(@as(usize, 1), jakefile.global_on_error_hooks.len);
    try std.testing.expectEqual(@as(?[]const u8, null), jakefile.global_on_error_hooks[0].recipe_name);
    try std.testing.expectEqualStrings("echo \"Global error handler\"", jakefile.global_on_error_hooks[0].command);

    // Two recipes, each with its own on_error
    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes.len);

    const build = jakefile.getRecipe("build").?;
    try std.testing.expectEqual(@as(usize, 1), build.on_error_hooks.len);
    try std.testing.expectEqualStrings("notify \"Build failed!\"", build.on_error_hooks[0].command);

    const deploy = jakefile.getRecipe("deploy").?;
    try std.testing.expectEqual(@as(usize, 1), deploy.on_error_hooks.len);
    try std.testing.expectEqualStrings("rollback --auto", deploy.on_error_hooks[0].command);
}

test "parse @on_error with complex shell command" {
    const source =
        \\@on_error curl -X POST -d '{"error": "build failed"}' https://hooks.example.com/notify
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.global_on_error_hooks.len);
    try std.testing.expectEqual(@as(?[]const u8, null), jakefile.global_on_error_hooks[0].recipe_name);
    try std.testing.expectEqualStrings("curl -X POST -d '{\"error\": \"build failed\"}' https://hooks.example.com/notify", jakefile.global_on_error_hooks[0].command);
}

test "parse multiple targeted hooks" {
    const source =
        \\@before build echo "Before build"
        \\@after build echo "After build"
        \\@before test echo "Before test"
        \\@after test echo "After test"
        \\
        \\task build:
        \\    echo "building"
        \\
        \\task test:
        \\    echo "testing"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.global_pre_hooks.len);
    try std.testing.expectEqual(@as(usize, 2), jakefile.global_post_hooks.len);

    // First @before targets build
    try std.testing.expectEqualStrings("build", jakefile.global_pre_hooks[0].recipe_name.?);
    // Second @before targets test
    try std.testing.expectEqualStrings("test", jakefile.global_pre_hooks[1].recipe_name.?);
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

test "recipe loc is set correctly during parsing" {
    const source =
        \\task build:
        \\    echo "building"
        \\
        \\task _private:
        \\    echo "private"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes.len);

    // First recipe "build" should be at line 1
    const build = jakefile.recipes[0];
    try std.testing.expectEqualStrings("build", build.name);
    try std.testing.expectEqual(@as(usize, 1), build.loc.line);
    try std.testing.expect(build.loc.start > 0); // After "task "

    // Second recipe "_private" should be at line 4
    const private = jakefile.recipes[1];
    try std.testing.expectEqualStrings("_private", private.name);
    try std.testing.expectEqual(@as(usize, 4), private.loc.line);
    // Verify origin is null for non-imported recipes
    try std.testing.expect(private.origin == null);
}

test "simple recipe loc is set correctly" {
    const source =
        \\build:
        \\    echo "building"
        \\
        \\clean:
        \\    rm -rf dist
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes.len);

    // Simple recipe "build" at line 1, column 1
    const build = jakefile.recipes[0];
    try std.testing.expectEqualStrings("build", build.name);
    try std.testing.expectEqual(@as(usize, 1), build.loc.line);
    try std.testing.expectEqual(@as(usize, 1), build.loc.column);
    try std.testing.expectEqual(Recipe.Kind.simple, build.kind);

    // Simple recipe "clean" at line 4
    const clean = jakefile.recipes[1];
    try std.testing.expectEqualStrings("clean", clean.name);
    try std.testing.expectEqual(@as(usize, 4), clean.loc.line);
}

test "file recipe loc is set correctly" {
    const source =
        \\file dist/app.js: src/**/*.ts
        \\    tsc --outFile dist/app.js
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);

    const file_recipe = jakefile.recipes[0];
    try std.testing.expectEqualStrings("dist/app.js", file_recipe.name);
    try std.testing.expectEqual(@as(usize, 1), file_recipe.loc.line);
    try std.testing.expectEqual(Recipe.Kind.file, file_recipe.kind);
    // Verify loc.start points to after "file "
    try std.testing.expect(file_recipe.loc.start == 5);
}

test "recipe loc.end captures name end position" {
    const source = "task build:\n    echo hi";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const recipe = jakefile.recipes[0];
    // "build" starts at position 5 (after "task ") and ends at 10
    try std.testing.expectEqual(@as(usize, 5), recipe.loc.start);
    try std.testing.expectEqual(@as(usize, 10), recipe.loc.end);
    // Verify the slice matches
    try std.testing.expectEqualStrings("build", source[recipe.loc.start..recipe.loc.end]);
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

test "parse task recipe with reserved keyword parameter name" {
    // Regression: issue #23 — reserved keywords rejected as task parameter names.
    const source =
        \\task trace file="traces.jsonl":
        \\    echo {{file}}
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].params.len);
    try std.testing.expectEqualStrings("file", jakefile.recipes[0].params[0].name);
    try std.testing.expectEqualStrings("traces.jsonl", jakefile.recipes[0].params[0].default.?);
}

test "parse task recipe with multiple reserved keyword parameter names" {
    // Regression: issue #23 — several reserved keywords must work as param names.
    const source =
        \\task probe cd needs confirm="yes":
        \\    echo {{cd}} {{needs}} {{confirm}}
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes[0].params.len);
    try std.testing.expectEqualStrings("cd", jakefile.recipes[0].params[0].name);
    try std.testing.expectEqualStrings("needs", jakefile.recipes[0].params[1].name);
    try std.testing.expectEqualStrings("confirm", jakefile.recipes[0].params[2].name);
    try std.testing.expectEqualStrings("yes", jakefile.recipes[0].params[2].default.?);
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

test "file recipe body parses command-level directives (jake#21)" {
    // @needs (and other directives) inside a file recipe body must be parsed
    // as directives, not leaked to the shell as a literal `needs` command.
    const source =
        \\file out.txt: in.txt
        \\    @needs echo
        \\    @ignore rm -f stale
        \\    echo hi > out.txt
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const recipe = jakefile.recipes[0];
    try std.testing.expectEqual(Recipe.Kind.file, recipe.kind);
    try std.testing.expectEqual(@as(usize, 3), recipe.commands.len);
    try std.testing.expectEqual(Recipe.CommandDirective.needs, recipe.commands[0].directive.?);
    try std.testing.expectEqualStrings("needs echo", recipe.commands[0].line);
    try std.testing.expectEqual(Recipe.CommandDirective.ignore, recipe.commands[1].directive.?);
    try std.testing.expectEqual(@as(?Recipe.CommandDirective, null), recipe.commands[2].directive);
}

test "simple recipe body parses command-level directives (jake#21)" {
    const source =
        \\build:
        \\    @needs cc
        \\    cc -o app main.c
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const recipe = jakefile.recipes[0];
    try std.testing.expectEqual(Recipe.Kind.simple, recipe.kind);
    try std.testing.expectEqual(Recipe.CommandDirective.needs, recipe.commands[0].directive.?);
}

test "file recipe still treats unknown @cmd as silent command" {
    // `@echo` is not a directive keyword — the @ means "silent" and the whole
    // line (including the @) is preserved as the command.
    const source =
        \\file out.txt: in.txt
        \\    @echo building
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    const recipe = jakefile.recipes[0];
    try std.testing.expectEqual(@as(?Recipe.CommandDirective, null), recipe.commands[0].directive);
    try std.testing.expectEqualStrings("@echo building", recipe.commands[0].line);
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

test "parse rooted directive sets flag" {
    const source = "@rooted\n\ntask build:\n    echo hi\n";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expect(jakefile.rooted);
    // `@rooted` is a flag, not a collected directive.
    try std.testing.expectEqual(@as(usize, 0), jakefile.directives.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
}

test "rooted flag defaults to false without directive" {
    const source = "task build:\n    echo hi\n";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expect(!jakefile.rooted);
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
    try std.testing.expect(!jakefile.imports[0].rooted);
}

test "parse import directive with rooted modifier" {
    const source = "@import \"sub/Jakefile\" rooted";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.imports.len);
    try std.testing.expectEqualStrings("sub/Jakefile", jakefile.imports[0].path);
    try std.testing.expect(jakefile.imports[0].prefix == null);
    try std.testing.expect(jakefile.imports[0].rooted);
}

test "parse import directive with prefix and rooted modifier" {
    const source = "@import \"vendored/tool/Jakefile\" as tool rooted";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.imports.len);
    try std.testing.expectEqualStrings("vendored/tool/Jakefile", jakefile.imports[0].path);
    try std.testing.expectEqualStrings("tool", jakefile.imports[0].prefix.?);
    try std.testing.expect(jakefile.imports[0].rooted);
}

test "plain import has rooted false" {
    const source = "@import \"common.jake\"";
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expect(!jakefile.imports[0].rooted);
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

test "parse default directive with intervening metadata" {
    const source =
        \\@default
        \\@group build
        \\@desc "Build the project"
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expect(jakefile.recipes[0].is_default);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].group.?);
    try std.testing.expectEqualStrings("Build the project", jakefile.recipes[0].description.?);
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
    // Only @dotenv is global; `@require node npm` is recipe-scoped to `build`.
    try std.testing.expectEqual(@as(usize, 1), jakefile.directives.len);
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].requires.len);
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

// --- @group and @desc Tests ---

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

test "parse @desc with unquoted text" {
    const source =
        \\@desc Run the test suite
        \\task test:
        \\    npm test
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("Run the test suite", jakefile.recipes[0].description.?);
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

// --- @platform Tests ---

test "parse platform directive with single os" {
    const source =
        \\@platform linux
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

test "parse platform directive with multiple os" {
    const source =
        \\@platform linux macos
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

test "parse platform directive with three os" {
    const source =
        \\@platform linux macos windows
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

test "parse platform applies only to next recipe" {
    const source =
        \\@platform windows
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

test "parse platform with simple recipe" {
    const source =
        \\@platform macos
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

test "parse platform with file recipe" {
    const source =
        \\@platform linux
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

test "parse platform combined with other directives" {
    const source =
        \\@platform linux macos
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

// Recipe-level @needs tests

test "parse recipe-level @needs simple command" {
    const source =
        \\@needs docker
        \\task build:
        \\    docker build .
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].needs.len);
    try std.testing.expectEqualStrings("docker", jakefile.recipes[0].needs[0].command);
    try std.testing.expectEqual(@as(?[]const u8, null), jakefile.recipes[0].needs[0].hint);
    try std.testing.expectEqual(@as(?[]const u8, null), jakefile.recipes[0].needs[0].install_task);
}

test "parse recipe-level @needs with hint" {
    const source =
        \\@needs docker "Install Docker Desktop from docker.com"
        \\task build:
        \\    docker build .
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].needs.len);
    try std.testing.expectEqualStrings("docker", jakefile.recipes[0].needs[0].command);
    try std.testing.expectEqualStrings("Install Docker Desktop from docker.com", jakefile.recipes[0].needs[0].hint.?);
    try std.testing.expectEqual(@as(?[]const u8, null), jakefile.recipes[0].needs[0].install_task);
}

test "parse recipe-level @needs with install task" {
    const source =
        \\@needs docker -> install-docker
        \\task build:
        \\    docker build .
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].needs.len);
    try std.testing.expectEqualStrings("docker", jakefile.recipes[0].needs[0].command);
    try std.testing.expectEqual(@as(?[]const u8, null), jakefile.recipes[0].needs[0].hint);
    try std.testing.expectEqualStrings("install-docker", jakefile.recipes[0].needs[0].install_task.?);
}

test "parse recipe-level @needs with quoted command path" {
    const source =
        \\@needs "/bin/sh"
        \\task test:
        \\    echo "hi"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].needs.len);
    try std.testing.expectEqualStrings("/bin/sh", jakefile.recipes[0].needs[0].command);
}

test "parse recipe-level @needs with hint and install task" {
    const source =
        \\@needs docker "Docker is required" -> install-docker
        \\task build:
        \\    docker build .
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].needs.len);
    try std.testing.expectEqualStrings("docker", jakefile.recipes[0].needs[0].command);
    try std.testing.expectEqualStrings("Docker is required", jakefile.recipes[0].needs[0].hint.?);
    try std.testing.expectEqualStrings("install-docker", jakefile.recipes[0].needs[0].install_task.?);
}

test "parse multiple recipe-level @needs directives accumulate" {
    const source =
        \\@needs docker
        \\@needs npm "Install Node.js"
        \\task build:
        \\    docker build .
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].needs.len);
    try std.testing.expectEqualStrings("docker", jakefile.recipes[0].needs[0].command);
    try std.testing.expectEqualStrings("npm", jakefile.recipes[0].needs[1].command);
    try std.testing.expectEqualStrings("Install Node.js", jakefile.recipes[0].needs[1].hint.?);
}

test "parse recipe-level @needs with multiple commands on same line" {
    const source =
        \\@needs docker npm node
        \\task build:
        \\    docker build .
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes[0].needs.len);
    try std.testing.expectEqualStrings("docker", jakefile.recipes[0].needs[0].command);
    try std.testing.expectEqualStrings("npm", jakefile.recipes[0].needs[1].command);
    try std.testing.expectEqualStrings("node", jakefile.recipes[0].needs[2].command);
}

test "parse recipe-level @needs on file recipe" {
    const source =
        \\@needs gcc
        \\file output.o: input.c
        \\    gcc -c input.c -o output.o
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(Recipe.Kind.file, jakefile.recipes[0].kind);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].needs.len);
    try std.testing.expectEqualStrings("gcc", jakefile.recipes[0].needs[0].command);
}

test "parse recipe-level @needs on simple recipe" {
    const source =
        \\@needs make
        \\build:
        \\    make all
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(Recipe.Kind.simple, jakefile.recipes[0].kind);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].needs.len);
    try std.testing.expectEqualStrings("make", jakefile.recipes[0].needs[0].command);
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

test "parse doc comment before recipe" {
    const source =
        \\# Build the application
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];
    try std.testing.expectEqualStrings("Build the application", recipe.doc_comment.?);
}

test "doc comment only applies to next recipe" {
    const source =
        \\# Comment for build
        \\task build:
        \\    echo "building"
        \\
        \\task test:
        \\    echo "testing"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes.len);

    // First recipe should have the doc comment
    const build = jakefile.getRecipe("build").?;
    try std.testing.expectEqualStrings("Comment for build", build.doc_comment.?);

    // Second recipe should not have a doc comment
    const test_recipe = jakefile.getRecipe("test").?;
    try std.testing.expect(test_recipe.doc_comment == null);
}

test "desc clears doc_comment when explicitly set" {
    const source =
        \\# Doc comment here
        \\@desc "Explicit description"
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];

    // doc_comment is cleared when @desc is provided (avoids file headers showing)
    try std.testing.expect(recipe.doc_comment == null);
    try std.testing.expectEqualStrings("Explicit description", recipe.description.?);
}

// Regression test: only comments immediately before recipe are captured (no blank lines)
test "blank line clears doc_comment" {
    const source =
        \\# This comment has a blank line after it
        \\
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];

    // Blank line between comment and recipe clears doc_comment
    try std.testing.expect(recipe.doc_comment == null);
}

test "comment immediately before recipe is captured" {
    const source =
        \\# This comment is immediately before the recipe
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];

    // No blank line, so comment is captured
    try std.testing.expectEqualStrings("This comment is immediately before the recipe", recipe.doc_comment.?);
}

test "section headers with blank lines are not captured" {
    // Common pattern: section header followed by blank line
    const source =
        \\# ============================================================================
        \\# Build Section
        \\# ============================================================================
        \\
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    const recipe = jakefile.recipes[0];

    // Blank line after section header clears doc_comment
    try std.testing.expect(recipe.doc_comment == null);
}

// ============================================================================
// Edge case tests from TODO.md test gaps
// ============================================================================

test "parse empty dependency list" {
    const source =
        \\task build: []
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].name);
    try std.testing.expectEqual(@as(usize, 0), jakefile.recipes[0].dependencies.len);
}

test "parse trailing comma in dependencies" {
    const source =
        \\build: [a, b,]
        \\    echo "done"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].dependencies.len);
    try std.testing.expectEqualStrings("a", jakefile.recipes[0].dependencies[0]);
    try std.testing.expectEqualStrings("b", jakefile.recipes[0].dependencies[1]);
}

test "parse dependency with hyphens" {
    const source =
        \\build: [my-dep, another-one]
        \\    echo "done"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 2), jakefile.recipes[0].dependencies.len);
    try std.testing.expectEqualStrings("my-dep", jakefile.recipes[0].dependencies[0]);
    try std.testing.expectEqualStrings("another-one", jakefile.recipes[0].dependencies[1]);
}

test "parse parameter with empty quoted default" {
    const source =
        \\task build a="":
        \\    echo "a is: $a"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].params.len);
    try std.testing.expectEqualStrings("a", jakefile.recipes[0].params[0].name);
    try std.testing.expectEqualStrings("", jakefile.recipes[0].params[0].default.?);
}

test "parse parameter default with spaces" {
    const source =
        \\task greet name="hello world":
        \\    echo "$name"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes[0].params.len);
    try std.testing.expectEqualStrings("name", jakefile.recipes[0].params[0].name);
    try std.testing.expectEqualStrings("hello world", jakefile.recipes[0].params[0].default.?);
}

test "parse multiple parameters with mixed defaults" {
    const source =
        \\task test a b="default" c:
        \\    echo "$a $b $c"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(usize, 3), jakefile.recipes[0].params.len);
    try std.testing.expectEqualStrings("a", jakefile.recipes[0].params[0].name);
    try std.testing.expect(jakefile.recipes[0].params[0].default == null);
    try std.testing.expectEqualStrings("b", jakefile.recipes[0].params[1].name);
    try std.testing.expectEqualStrings("default", jakefile.recipes[0].params[1].default.?);
    try std.testing.expectEqualStrings("c", jakefile.recipes[0].params[2].name);
    try std.testing.expect(jakefile.recipes[0].params[2].default == null);
}

// --- Comment Capture Tests ---

test "parser captures standalone comments" {
    const source =
        \\# Header comment
        \\name = "test"
        \\
        \\# Section comment
        \\# Another comment
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // Should capture all standalone comments
    try std.testing.expect(jakefile.comments.len >= 3);

    // Verify first comment
    try std.testing.expectEqualStrings("# Header comment", jakefile.comments[0].text);
    try std.testing.expect(jakefile.comments[0].kind == .standalone);
    try std.testing.expect(jakefile.comments[0].line == 1); // Lines are 1-indexed
}

test "parser tracks comment positions" {
    const source =
        \\# First line comment
        \\
        \\# Third line comment
        \\task test:
        \\    echo "test"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expect(jakefile.comments.len >= 2);
    try std.testing.expect(jakefile.comments[0].line == 1); // Line 1 (1-indexed)
    try std.testing.expect(jakefile.comments[1].line == 3); // Line 3 (after blank line)
}

// --- @timeout directive tests ---

test "parse @timeout with valid seconds" {
    const source =
        \\@timeout 30s
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqual(@as(?u64, 30), jakefile.recipes[0].timeout_seconds);
}

test "parse @timeout with valid minutes" {
    const source =
        \\@timeout 5m
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u64, 300), jakefile.recipes[0].timeout_seconds);
}

test "parse @timeout with valid hours" {
    const source =
        \\@timeout 2h
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u64, 7200), jakefile.recipes[0].timeout_seconds);
}

test "parse @timeout with invalid unit returns error" {
    const source =
        \\@timeout 30x
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    const result = p.parseJakefile();

    try std.testing.expectError(ParseError.InvalidTimeoutFormat, result);
}

test "parse @timeout with zero value returns error" {
    const source =
        \\@timeout 0s
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    const result = p.parseJakefile();

    try std.testing.expectError(ParseError.InvalidTimeoutFormat, result);
}

test "parse @timeout with minimum valid value" {
    const source =
        \\@timeout 1s
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u64, 1), jakefile.recipes[0].timeout_seconds);
}

test "parse @timeout with large value" {
    const source =
        \\@timeout 86400s
        \\task build:
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    // 86400 seconds = 24 hours
    try std.testing.expectEqual(@as(?u64, 86400), jakefile.recipes[0].timeout_seconds);
}

test "parse @timeout only applies to next recipe" {
    const source =
        \\@timeout 30s
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
    try std.testing.expectEqual(@as(?u64, 30), jakefile.recipes[0].timeout_seconds);
    try std.testing.expectEqual(@as(?u64, null), jakefile.recipes[1].timeout_seconds);
}

test "parse task named 'default' (keyword as identifier)" {
    const source =
        \\task default:
        \\    echo "hello"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("default", jakefile.recipes[0].name);
}

test "parse task with keyword names as dependencies" {
    const source =
        \\task build: default
        \\    echo "building"
    ;
    var lex = Lexer.init(source);
    var p = Parser.init(std.testing.allocator, &lex);
    var jakefile = try p.parseJakefile();
    defer jakefile.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), jakefile.recipes.len);
    try std.testing.expectEqualStrings("build", jakefile.recipes[0].name);
}

// --- Fuzz Testing ---

test "fuzz parser" {
    try std.testing.fuzz({}, struct {
        fn testOne(_: void, input: []const u8) !void {
            var lex = Lexer.init(input);
            var p = Parser.init(std.testing.allocator, &lex);

            // Parse the fuzzed input - errors are expected for invalid syntax
            var jakefile = p.parseJakefile() catch return;
            defer jakefile.deinit(std.testing.allocator);
        }
    }.testOne, .{});
}
