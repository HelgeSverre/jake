// Jake Lexer - Tokenizes Jakefile source code

const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
        line: usize, // 1-based line number
        column: usize, // 1-based column number
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
        kw_as,
        kw_dotenv,
        kw_require,
        kw_watch,
        kw_cache,
        kw_needs,
        kw_confirm,
        kw_each,
        kw_pre,
        kw_post,
        kw_export,

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
    line: usize, // 1-based current line number
    column: usize, // 1-based current column number

    /// Tab width for column calculations (default: 4)
    pub const TAB_WIDTH: usize = 4;

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .index = 0,
            .line_start = true,
            .line = 1,
            .column = 1,
        };
    }

    /// Advance the index by one character and update line/column tracking
    fn advanceIndex(self: *Lexer) void {
        if (self.index < self.source.len) {
            if (self.source[self.index] == '\n') {
                self.line += 1;
                self.column = 1;
            } else if (self.source[self.index] == '\t') {
                // Tab advances to next tab stop
                self.column = ((self.column - 1) / TAB_WIDTH + 1) * TAB_WIDTH + 1;
            } else {
                self.column += 1;
            }
            self.index += 1;
        }
    }

    /// Create a Loc with the given start position and current end position
    fn makeLoc(self: *const Lexer, start: usize, start_line: usize, start_column: usize) Token.Loc {
        return .{
            .start = start,
            .end = self.index,
            .line = start_line,
            .column = start_column,
        };
    }

    pub fn next(self: *Lexer) Token {
        // Handle indentation at line start
        if (self.line_start) {
            self.line_start = false;
            if (self.index < self.source.len) {
                const indent_start = self.index;
                const indent_line = self.line;
                const indent_column = self.column;
                var spaces: usize = 0;

                while (self.index < self.source.len) {
                    if (self.source[self.index] == ' ') {
                        spaces += 1;
                        self.advanceIndex();
                    } else if (self.source[self.index] == '\t') {
                        spaces += 4; // Treat tab as 4 spaces for indentation counting
                        self.advanceIndex();
                    } else {
                        break;
                    }
                }

                if (spaces >= 4) {
                    return .{
                        .tag = .indent,
                        .loc = .{
                            .start = indent_start,
                            .end = self.index,
                            .line = indent_line,
                            .column = indent_column,
                        },
                    };
                }
                // If less than 4 spaces, continue normal parsing
                // (those spaces are insignificant)
            }
        }

        // Skip non-significant whitespace (spaces and tabs not at line start)
        while (self.index < self.source.len and (self.source[self.index] == ' ' or self.source[self.index] == '\t')) {
            self.advanceIndex();
        }

        if (self.index >= self.source.len) {
            return .{
                .tag = .eof,
                .loc = .{
                    .start = self.index,
                    .end = self.index,
                    .line = self.line,
                    .column = self.column,
                },
            };
        }

        const start = self.index;
        const start_line = self.line;
        const start_column = self.column;
        const c = self.source[self.index];

        // Single character tokens
        switch (c) {
            '\n' => {
                self.advanceIndex();
                self.line_start = true;
                return .{
                    .tag = .newline,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            '=' => {
                self.advanceIndex();
                return .{
                    .tag = .equals,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            ':' => {
                self.advanceIndex();
                return .{
                    .tag = .colon,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            ',' => {
                self.advanceIndex();
                return .{
                    .tag = .comma,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            '|' => {
                self.advanceIndex();
                return .{
                    .tag = .pipe,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            '[' => {
                self.advanceIndex();
                return .{
                    .tag = .l_bracket,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            ']' => {
                self.advanceIndex();
                return .{
                    .tag = .r_bracket,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            '{' => {
                self.advanceIndex();
                return .{
                    .tag = .l_brace,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            '}' => {
                self.advanceIndex();
                return .{
                    .tag = .r_brace,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            '(' => {
                self.advanceIndex();
                return .{
                    .tag = .l_paren,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            ')' => {
                self.advanceIndex();
                return .{
                    .tag = .r_paren,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            '@' => {
                self.advanceIndex();
                return .{
                    .tag = .at,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            '-' => {
                if (self.index + 1 < self.source.len and self.source[self.index + 1] == '>') {
                    self.advanceIndex();
                    self.advanceIndex();
                    return .{
                        .tag = .arrow,
                        .loc = self.makeLoc(start, start_line, start_column),
                    };
                }
                // Otherwise treat as part of identifier or glob
                return self.scanIdentOrGlob(start, start_line, start_column);
            },
            '#' => {
                // Comment - consume until end of line
                while (self.index < self.source.len and self.source[self.index] != '\n') {
                    self.advanceIndex();
                }
                return .{
                    .tag = .comment,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
            '"', '\'' => return self.scanString(start, start_line, start_column),
            '.' => {
                // Starts with dot - could be a dotfile like .env or a path like ./foo
                return self.scanIdentKeywordOrGlob(start, start_line, start_column);
            },
            else => {
                if (isIdentStart(c)) {
                    return self.scanIdentKeywordOrGlob(start, start_line, start_column);
                } else if (isDigit(c)) {
                    return self.scanNumber(start, start_line, start_column);
                }
                self.advanceIndex();
                return .{
                    .tag = .invalid,
                    .loc = self.makeLoc(start, start_line, start_column),
                };
            },
        }
    }

    fn scanIdentKeywordOrGlob(self: *Lexer, start: usize, start_line: usize, start_column: usize) Token {
        // Scan identifier/keyword or glob pattern
        // Glob patterns can contain: letters, digits, _, -, ., /, *, **
        while (self.index < self.source.len) {
            const ch = self.source[self.index];
            if (isIdentContinue(ch) or ch == '/' or ch == '*' or ch == '.') {
                self.advanceIndex();
            } else {
                break;
            }
        }

        const text = self.source[start..self.index];

        // Determine if it's a glob pattern (contains * or /)
        // Note: "." alone or in the middle of an identifier is not a glob
        const is_glob = std.mem.indexOfAny(u8, text, "*/") != null;

        if (is_glob) {
            return .{
                .tag = .glob_pattern,
                .loc = self.makeLoc(start, start_line, start_column),
            };
        }

        // Check for keywords
        const tag: Token.Tag = if (std.mem.eql(u8, text, "task"))
            .kw_task
        else if (std.mem.eql(u8, text, "file"))
            .kw_file
        else if (std.mem.eql(u8, text, "default"))
            .kw_default
        else if (std.mem.eql(u8, text, "if"))
            .kw_if
        else if (std.mem.eql(u8, text, "elif"))
            .kw_elif
        else if (std.mem.eql(u8, text, "else"))
            .kw_else
        else if (std.mem.eql(u8, text, "end"))
            .kw_end
        else if (std.mem.eql(u8, text, "import"))
            .kw_import
        else if (std.mem.eql(u8, text, "as"))
            .kw_as
        else if (std.mem.eql(u8, text, "dotenv"))
            .kw_dotenv
        else if (std.mem.eql(u8, text, "require"))
            .kw_require
        else if (std.mem.eql(u8, text, "watch"))
            .kw_watch
        else if (std.mem.eql(u8, text, "cache"))
            .kw_cache
        else if (std.mem.eql(u8, text, "needs"))
            .kw_needs
        else if (std.mem.eql(u8, text, "confirm"))
            .kw_confirm
        else if (std.mem.eql(u8, text, "each"))
            .kw_each
        else if (std.mem.eql(u8, text, "pre"))
            .kw_pre
        else if (std.mem.eql(u8, text, "post"))
            .kw_post
        else if (std.mem.eql(u8, text, "export"))
            .kw_export
        else
            .ident;

        return .{
            .tag = tag,
            .loc = self.makeLoc(start, start_line, start_column),
        };
    }

    fn scanIdentOrGlob(self: *Lexer, start: usize, start_line: usize, start_column: usize) Token {
        // Glob patterns can contain: letters, digits, _, -, ., /, *, **
        while (self.index < self.source.len) {
            const ch = self.source[self.index];
            if (isIdentContinue(ch) or ch == '/' or ch == '*' or ch == '.') {
                self.advanceIndex();
            } else {
                break;
            }
        }

        const text = self.source[start..self.index];

        // Determine if it's a glob pattern (contains * or /)
        const is_glob = std.mem.indexOfAny(u8, text, "*/") != null;

        return .{
            .tag = if (is_glob) .glob_pattern else .ident,
            .loc = self.makeLoc(start, start_line, start_column),
        };
    }

    fn scanString(self: *Lexer, start: usize, start_line: usize, start_column: usize) Token {
        const quote = self.source[self.index];
        self.advanceIndex(); // Skip opening quote

        while (self.index < self.source.len) {
            if (self.source[self.index] == quote) {
                self.advanceIndex(); // Include closing quote
                break;
            }
            if (self.source[self.index] == '\\' and self.index + 1 < self.source.len) {
                self.advanceIndex(); // Skip backslash
                self.advanceIndex(); // Skip escaped character
            } else {
                self.advanceIndex();
            }
        }

        return .{
            .tag = .string,
            .loc = self.makeLoc(start, start_line, start_column),
        };
    }

    fn scanNumber(self: *Lexer, start: usize, start_line: usize, start_column: usize) Token {
        while (self.index < self.source.len and isDigit(self.source[self.index])) {
            self.advanceIndex();
        }

        return .{
            .tag = .number,
            .loc = self.makeLoc(start, start_line, start_column),
        };
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
    try std.testing.expectEqual(@as(usize, 1), t1.loc.line);
    try std.testing.expectEqual(@as(usize, 1), t1.loc.column);

    const t2 = lex.next();
    try std.testing.expectEqual(Token.Tag.equals, t2.tag);
    try std.testing.expectEqual(@as(usize, 1), t2.loc.line);
    try std.testing.expectEqual(@as(usize, 6), t2.loc.column);

    const t3 = lex.next();
    try std.testing.expectEqual(Token.Tag.string, t3.tag);
    try std.testing.expectEqual(@as(usize, 1), t3.loc.line);
    try std.testing.expectEqual(@as(usize, 8), t3.loc.column);
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

    const echo_tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, echo_tok.tag);
    try std.testing.expectEqual(@as(usize, 2), echo_tok.loc.line);
    try std.testing.expectEqual(@as(usize, 5), echo_tok.loc.column);
}

test "lexer line and column tracking" {
    const source = "foo\nbar baz\n  qux";
    var lex = Lexer.init(source);

    // foo at line 1, col 1
    const t1 = lex.next();
    try std.testing.expectEqual(@as(usize, 1), t1.loc.line);
    try std.testing.expectEqual(@as(usize, 1), t1.loc.column);

    // newline
    _ = lex.next();

    // bar at line 2, col 1
    const t2 = lex.next();
    try std.testing.expectEqual(@as(usize, 2), t2.loc.line);
    try std.testing.expectEqual(@as(usize, 1), t2.loc.column);

    // baz at line 2, col 5
    const t3 = lex.next();
    try std.testing.expectEqual(@as(usize, 2), t3.loc.line);
    try std.testing.expectEqual(@as(usize, 5), t3.loc.column);

    // newline
    _ = lex.next();

    // qux at line 3 (after 2 insignificant spaces)
    const t4 = lex.next();
    try std.testing.expectEqual(@as(usize, 3), t4.loc.line);
    try std.testing.expectEqual(@as(usize, 3), t4.loc.column);
}

test "lexer multi-line string" {
    const source = "\"hello\nworld\"";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.string, tok.tag);
    // String starts at line 1, col 1
    try std.testing.expectEqual(@as(usize, 1), tok.loc.line);
    try std.testing.expectEqual(@as(usize, 1), tok.loc.column);
}

test "lexer tab column tracking" {
    const source = "a\tb";
    var lex = Lexer.init(source);

    const t1 = lex.next();
    try std.testing.expectEqual(@as(usize, 1), t1.loc.column);

    const t2 = lex.next();
    // After 'a' at col 1, tab advances to col 5 (next tab stop), 'b' starts at col 5
    try std.testing.expectEqual(@as(usize, 5), t2.loc.column);
}

// ============================================================================
// COMPREHENSIVE LEXER TESTS
// ============================================================================

// --- Token Types: All Keywords ---

test "lexer all keywords" {
    const source = "task file default if elif else end import as dotenv require watch cache needs confirm each pre post export";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_file, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_default, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_if, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_elif, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_else, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_end, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_import, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_as, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_dotenv, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_require, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_watch, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_cache, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_needs, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_confirm, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_each, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_pre, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_post, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_export, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.eof, lex.next().tag);
}

// --- Token Types: All Symbols ---

test "lexer all symbols" {
    const source = "= : , | -> @ [ ] { } ( )";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.equals, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.comma, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.pipe, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.arrow, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.at, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.l_bracket, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.r_bracket, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.l_brace, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.r_brace, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.l_paren, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.r_paren, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.eof, lex.next().tag);
}

// --- Token Types: Strings ---

test "lexer double quoted string" {
    const source = "\"hello world\"";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.string, tok.tag);
    try std.testing.expectEqualStrings("\"hello world\"", tok.slice(source));
}

test "lexer single quoted string" {
    const source = "'hello world'";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.string, tok.tag);
    try std.testing.expectEqualStrings("'hello world'", tok.slice(source));
}

test "lexer string with escape sequences" {
    const source = "\"hello\\nworld\\t\\\"escaped\\\"\"";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.string, tok.tag);
    try std.testing.expectEqualStrings("\"hello\\nworld\\t\\\"escaped\\\"\"", tok.slice(source));
}

test "lexer empty string" {
    const source = "\"\"";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.string, tok.tag);
    try std.testing.expectEqualStrings("\"\"", tok.slice(source));
}

test "lexer string with special characters" {
    const source = "\"hello @#$%^&*()\"";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.string, tok.tag);
    try std.testing.expectEqualStrings("\"hello @#$%^&*()\"", tok.slice(source));
}

// --- Token Types: Numbers ---

test "lexer numbers" {
    const source = "42 0 123456789";
    var lex = Lexer.init(source);

    var tok = lex.next();
    try std.testing.expectEqual(Token.Tag.number, tok.tag);
    try std.testing.expectEqualStrings("42", tok.slice(source));

    tok = lex.next();
    try std.testing.expectEqual(Token.Tag.number, tok.tag);
    try std.testing.expectEqualStrings("0", tok.slice(source));

    tok = lex.next();
    try std.testing.expectEqual(Token.Tag.number, tok.tag);
    try std.testing.expectEqualStrings("123456789", tok.slice(source));
}

// --- Token Types: Glob Patterns ---

test "lexer glob pattern with asterisk" {
    const source = "src/*.ts";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.glob_pattern, tok.tag);
    try std.testing.expectEqualStrings("src/*.ts", tok.slice(source));
}

test "lexer glob pattern with double asterisk" {
    const source = "src/**/*.ts";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.glob_pattern, tok.tag);
    try std.testing.expectEqualStrings("src/**/*.ts", tok.slice(source));
}

test "lexer glob pattern with path only" {
    const source = "src/lib/utils.ts";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.glob_pattern, tok.tag);
    try std.testing.expectEqualStrings("src/lib/utils.ts", tok.slice(source));
}

test "lexer identifier not glob" {
    const source = "myvar";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, tok.tag);
    try std.testing.expectEqualStrings("myvar", tok.slice(source));
}

// --- Token Types: Identifiers ---

test "lexer identifier with underscores" {
    const source = "my_var_name";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, tok.tag);
    try std.testing.expectEqualStrings("my_var_name", tok.slice(source));
}

test "lexer identifier with hyphens" {
    const source = "my-var-name";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, tok.tag);
    try std.testing.expectEqualStrings("my-var-name", tok.slice(source));
}

test "lexer identifier with digits" {
    const source = "var123";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, tok.tag);
    try std.testing.expectEqualStrings("var123", tok.slice(source));
}

test "lexer identifier starting with underscore" {
    const source = "_private";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, tok.tag);
    try std.testing.expectEqualStrings("_private", tok.slice(source));
}

// --- Edge Cases: Empty Input ---

test "lexer empty input" {
    const source = "";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.eof, lex.next().tag);
}

test "lexer whitespace only" {
    const source = "   ";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.eof, lex.next().tag);
}

test "lexer newlines only" {
    const source = "\n\n\n";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.eof, lex.next().tag);
}

// --- Edge Cases: Malformed Strings ---

test "lexer unterminated double quoted string" {
    const source = "\"hello world";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.string, tok.tag);
    // Should consume until end
    try std.testing.expectEqualStrings("\"hello world", tok.slice(source));
}

test "lexer unterminated single quoted string" {
    const source = "'hello world";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.string, tok.tag);
    try std.testing.expectEqualStrings("'hello world", tok.slice(source));
}

// --- Edge Cases: Unicode ---

test "lexer unicode in string" {
    const source = "\"hello \xC3\xA9\xC3\xA0\xC3\xBC world\"";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.string, tok.tag);
}

test "lexer emoji in string" {
    const source = "\"hello \xF0\x9F\x98\x80 world\"";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.string, tok.tag);
}

// --- Indentation Handling ---

test "lexer tab indentation" {
    const source = "task:\n\techo";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.indent, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
}

test "lexer mixed spaces and tabs indentation" {
    const source = "task:\n  \techo";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    // 2 spaces + 1 tab = 6 spaces total, which is >= 4, so indent
    try std.testing.expectEqual(Token.Tag.indent, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
}

test "lexer insufficient indentation" {
    const source = "task:\n  echo";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    // Only 2 spaces, not enough for indent
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
}

test "lexer multiple indent levels" {
    const source = "task:\n    level1\n        level2";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.indent, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.indent, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
}

// --- Comments ---

test "lexer comment" {
    const source = "# this is a comment";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.comment, tok.tag);
    try std.testing.expectEqualStrings("# this is a comment", tok.slice(source));
}

test "lexer comment at end of line" {
    const source = "task # inline comment\n";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.comment, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
}

test "lexer comment with special characters" {
    const source = "# comment with @#$%^&*()";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.comment, tok.tag);
}

test "lexer empty comment" {
    const source = "#\n";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.comment, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
}

// --- Arrow Token ---

test "lexer arrow token" {
    const source = "a -> b";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.arrow, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
}

test "lexer hyphen not arrow" {
    const source = "-notarrow";
    var lex = Lexer.init(source);

    const tok = lex.next();
    // Should be scanned as identifier or glob
    try std.testing.expect(tok.tag == .ident or tok.tag == .glob_pattern);
}

// --- Invalid Characters ---

test "lexer invalid character" {
    const source = "`";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqual(Token.Tag.invalid, tok.tag);
}

test "lexer invalid character in sequence" {
    const source = "task ` build";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.invalid, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
}

// --- Complex Sequences ---

test "lexer complex recipe header" {
    const source = "task build arg1 arg2=\"default\":";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.equals, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.string, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
}

test "lexer file recipe with globs" {
    const source = "file dist/output.js: src/**/*.ts, lib/*.ts";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_file, lex.next().tag);
    // dist/output.js contains / so it's a glob_pattern
    try std.testing.expectEqual(Token.Tag.glob_pattern, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.glob_pattern, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.comma, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.glob_pattern, lex.next().tag);
}

test "lexer directive sequence" {
    const source = "@dotenv .env\n@require node npm";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.at, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_dotenv, lex.next().tag);
    // .env doesn't contain * or /, so it's an identifier (dotted name)
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.at, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.kw_require, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
}

test "lexer dependencies in brackets" {
    const source = "build: [compile, test, lint]";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.l_bracket, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.comma, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.comma, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.r_bracket, lex.next().tag);
}

// --- Token Location ---

test "lexer token locations" {
    const source = "task build";
    var lex = Lexer.init(source);

    const tok1 = lex.next();
    try std.testing.expectEqual(@as(usize, 0), tok1.loc.start);
    try std.testing.expectEqual(@as(usize, 4), tok1.loc.end);

    const tok2 = lex.next();
    try std.testing.expectEqual(@as(usize, 5), tok2.loc.start);
    try std.testing.expectEqual(@as(usize, 10), tok2.loc.end);
}

test "lexer slice function" {
    const source = "hello world";
    var lex = Lexer.init(source);

    const tok = lex.next();
    try std.testing.expectEqualStrings("hello", tok.slice(source));
}

// --- Keyword vs Identifier Boundaries ---

test "lexer keyword prefix not keyword" {
    const source = "taskname filetype defaultvalue";
    var lex = Lexer.init(source);

    // These should be identifiers, not keywords
    var tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, tok.tag);
    try std.testing.expectEqualStrings("taskname", tok.slice(source));

    tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, tok.tag);
    try std.testing.expectEqualStrings("filetype", tok.slice(source));

    tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, tok.tag);
    try std.testing.expectEqualStrings("defaultvalue", tok.slice(source));
}

test "lexer keyword with underscore suffix" {
    const source = "task_runner file_path";
    var lex = Lexer.init(source);

    var tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, tok.tag);
    try std.testing.expectEqualStrings("task_runner", tok.slice(source));

    tok = lex.next();
    try std.testing.expectEqual(Token.Tag.ident, tok.tag);
    try std.testing.expectEqualStrings("file_path", tok.slice(source));
}

// --- Consecutive Symbols ---

test "lexer consecutive symbols" {
    const source = "::,,==";
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.comma, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.comma, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.equals, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.equals, lex.next().tag);
}

// --- Multiline Input ---

test "lexer multiline recipe" {
    const source =
        \\task build:
        \\    echo "step 1"
        \\    echo "step 2"
    ;
    var lex = Lexer.init(source);

    try std.testing.expectEqual(Token.Tag.kw_task, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.colon, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.indent, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.string, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.newline, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.indent, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.ident, lex.next().tag);
    try std.testing.expectEqual(Token.Tag.string, lex.next().tag);
}

// --- Line/Column Tracking Tests ---

test "lexer line tracking across newlines" {
    const source = "a\nb\nc";
    var lex = Lexer.init(source);

    const t1 = lex.next();
    try std.testing.expectEqual(@as(usize, 1), t1.loc.line);
    _ = lex.next(); // newline

    const t2 = lex.next();
    try std.testing.expectEqual(@as(usize, 2), t2.loc.line);
    _ = lex.next(); // newline

    const t3 = lex.next();
    try std.testing.expectEqual(@as(usize, 3), t3.loc.line);
}

test "lexer eof location" {
    const source = "abc";
    var lex = Lexer.init(source);

    _ = lex.next(); // abc
    const eof = lex.next();
    try std.testing.expectEqual(Token.Tag.eof, eof.tag);
    try std.testing.expectEqual(@as(usize, 3), eof.loc.start);
    try std.testing.expectEqual(@as(usize, 3), eof.loc.end);
}
