// Jake Lexer - Tokenizes Jakefile source code

const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const Tag = enum {
        // Literals
        ident,
        string,
        number,
        glob_pattern, // e.g., src/**/*.ts

        // Keywords
        kw_task,
        kw_file,
        kw_default,
        kw_if,
        kw_elif,
        kw_else,
        kw_end,
        kw_import,
        kw_dotenv,
        kw_require,
        kw_watch,
        kw_cache,
        kw_needs,
        kw_confirm,
        kw_each,

        // Symbols
        equals, // =
        colon, // :
        comma, // ,
        pipe, // |
        arrow, // ->
        at, // @
        l_bracket, // [
        r_bracket, // ]
        l_brace, // {
        r_brace, // }
        l_paren, // (
        r_paren, // )

        // Whitespace
        newline,
        indent, // 4 spaces or 1 tab at line start

        // Other
        comment,
        invalid,
        eof,
    };

    pub fn slice(self: Token, source: []const u8) []const u8 {
        return source[self.loc.start..self.loc.end];
    }
};

pub const Lexer = struct {
    source: []const u8,
    index: usize,
    line_start: bool,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .index = 0,
            .line_start = true,
        };
    }

    pub fn next(self: *Lexer) Token {
        // Handle indentation at line start
        if (self.line_start) {
            self.line_start = false;
            if (self.index < self.source.len) {
                const indent_start = self.index;
                var spaces: usize = 0;

                while (self.index < self.source.len) {
                    if (self.source[self.index] == ' ') {
                        spaces += 1;
                        self.index += 1;
                    } else if (self.source[self.index] == '\t') {
                        spaces += 4; // Treat tab as 4 spaces
                        self.index += 1;
                    } else {
                        break;
                    }
                }

                if (spaces >= 4) {
                    return .{
                        .tag = .indent,
                        .loc = .{ .start = indent_start, .end = self.index },
                    };
                }
                // If less than 4 spaces, reset and continue normal parsing
                // (those spaces are insignificant)
            }
        }

        // Skip non-significant whitespace (spaces not at line start)
        while (self.index < self.source.len and self.source[self.index] == ' ') {
            self.index += 1;
        }

        if (self.index >= self.source.len) {
            return .{ .tag = .eof, .loc = .{ .start = self.index, .end = self.index } };
        }

        const start = self.index;
        const c = self.source[self.index];

        // Single character tokens
        switch (c) {
            '\n' => {
                self.index += 1;
                self.line_start = true;
                return .{ .tag = .newline, .loc = .{ .start = start, .end = self.index } };
            },
            '=' => {
                self.index += 1;
                return .{ .tag = .equals, .loc = .{ .start = start, .end = self.index } };
            },
            ':' => {
                self.index += 1;
                return .{ .tag = .colon, .loc = .{ .start = start, .end = self.index } };
            },
            ',' => {
                self.index += 1;
                return .{ .tag = .comma, .loc = .{ .start = start, .end = self.index } };
            },
            '|' => {
                self.index += 1;
                return .{ .tag = .pipe, .loc = .{ .start = start, .end = self.index } };
            },
            '[' => {
                self.index += 1;
                return .{ .tag = .l_bracket, .loc = .{ .start = start, .end = self.index } };
            },
            ']' => {
                self.index += 1;
                return .{ .tag = .r_bracket, .loc = .{ .start = start, .end = self.index } };
            },
            '{' => {
                self.index += 1;
                return .{ .tag = .l_brace, .loc = .{ .start = start, .end = self.index } };
            },
            '}' => {
                self.index += 1;
                return .{ .tag = .r_brace, .loc = .{ .start = start, .end = self.index } };
            },
            '(' => {
                self.index += 1;
                return .{ .tag = .l_paren, .loc = .{ .start = start, .end = self.index } };
            },
            ')' => {
                self.index += 1;
                return .{ .tag = .r_paren, .loc = .{ .start = start, .end = self.index } };
            },
            '@' => {
                self.index += 1;
                return .{ .tag = .at, .loc = .{ .start = start, .end = self.index } };
            },
            '-' => {
                if (self.index + 1 < self.source.len and self.source[self.index + 1] == '>') {
                    self.index += 2;
                    return .{ .tag = .arrow, .loc = .{ .start = start, .end = self.index } };
                }
                // Otherwise treat as part of identifier or glob
                return self.scanIdentOrGlob();
            },
            '#' => {
                // Comment - consume until end of line
                while (self.index < self.source.len and self.source[self.index] != '\n') {
                    self.index += 1;
                }
                return .{ .tag = .comment, .loc = .{ .start = start, .end = self.index } };
            },
            '"' => return self.scanString(),
            '\'' => return self.scanString(),
            else => {
                if (isIdentStart(c)) {
                    return self.scanIdentOrKeyword();
                } else if (isDigit(c)) {
                    return self.scanNumber();
                }
                self.index += 1;
                return .{ .tag = .invalid, .loc = .{ .start = start, .end = self.index } };
            },
        }
    }

    fn scanIdentOrKeyword(self: *Lexer) Token {
        const start = self.index;

        while (self.index < self.source.len and isIdentContinue(self.source[self.index])) {
            self.index += 1;
        }

        const ident = self.source[start..self.index];

        // Check for keywords
        const tag: Token.Tag = if (std.mem.eql(u8, ident, "task"))
            .kw_task
        else if (std.mem.eql(u8, ident, "file"))
            .kw_file
        else if (std.mem.eql(u8, ident, "default"))
            .kw_default
        else if (std.mem.eql(u8, ident, "if"))
            .kw_if
        else if (std.mem.eql(u8, ident, "elif"))
            .kw_elif
        else if (std.mem.eql(u8, ident, "else"))
            .kw_else
        else if (std.mem.eql(u8, ident, "end"))
            .kw_end
        else if (std.mem.eql(u8, ident, "import"))
            .kw_import
        else if (std.mem.eql(u8, ident, "dotenv"))
            .kw_dotenv
        else if (std.mem.eql(u8, ident, "require"))
            .kw_require
        else if (std.mem.eql(u8, ident, "watch"))
            .kw_watch
        else if (std.mem.eql(u8, ident, "cache"))
            .kw_cache
        else if (std.mem.eql(u8, ident, "needs"))
            .kw_needs
        else if (std.mem.eql(u8, ident, "confirm"))
            .kw_confirm
        else if (std.mem.eql(u8, ident, "each"))
            .kw_each
        else
            .ident;

        return .{ .tag = tag, .loc = .{ .start = start, .end = self.index } };
    }

    fn scanIdentOrGlob(self: *Lexer) Token {
        const start = self.index;

        // Glob patterns can contain: letters, digits, _, -, ., /, *, **
        while (self.index < self.source.len) {
            const ch = self.source[self.index];
            if (isIdentContinue(ch) or ch == '/' or ch == '*' or ch == '.') {
                self.index += 1;
            } else {
                break;
            }
        }

        const text = self.source[start..self.index];

        // Determine if it's a glob pattern (contains * or /)
        const is_glob = std.mem.indexOfAny(u8, text, "*/") != null;

        return .{
            .tag = if (is_glob) .glob_pattern else .ident,
            .loc = .{ .start = start, .end = self.index },
        };
    }

    fn scanString(self: *Lexer) Token {
        const start = self.index;
        const quote = self.source[self.index];
        self.index += 1; // Skip opening quote

        while (self.index < self.source.len) {
            if (self.source[self.index] == quote) {
                self.index += 1; // Include closing quote
                break;
            }
            if (self.source[self.index] == '\\' and self.index + 1 < self.source.len) {
                self.index += 2; // Skip escape sequence
            } else {
                self.index += 1;
            }
        }

        return .{ .tag = .string, .loc = .{ .start = start, .end = self.index } };
    }

    fn scanNumber(self: *Lexer) Token {
        const start = self.index;

        while (self.index < self.source.len and isDigit(self.source[self.index])) {
            self.index += 1;
        }

        return .{ .tag = .number, .loc = .{ .start = start, .end = self.index } };
    }

    fn isIdentStart(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn isIdentContinue(c: u8) bool {
        return isIdentStart(c) or isDigit(c) or c == '-' or c == '.';
    }

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }
};

test "lexer basic tokens" {
    const source = "name = \"value\"";
    var lex = Lexer.init(source);

    const t1 = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, t1.tag);
    try std.testing.expectEqualStrings("name", t1.slice(source));

    const t2 = lex.next();
    try std.testing.expectEqual(Token.Tag.equals, t2.tag);

    const t3 = lex.next();
    try std.testing.expectEqual(Token.Tag.string, t3.tag);
}

test "lexer keywords" {
    const source = "task file default";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_file, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_default, lex.next().tag);
}

test "lexer indentation" {
    const source = "task:\n    echo";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.indent, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
}
