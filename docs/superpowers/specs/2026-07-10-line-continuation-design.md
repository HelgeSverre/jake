# Line Continuation Design

## Goal

Make a trailing, unescaped `\` join indented recipe lines into one shell command, matching Jake's documented syntax and preserving multiline formatting.

```jake
task long-command:
    echo "This is a very long command" \
         "that spans multiple lines"
```

Jake must execute this as one shell invocation. Shell variables, argument fragments, and command chains must therefore remain in the same process.

## Semantics

- A backslash immediately before a line ending continues the command onto the next indented recipe line.
- An odd run of trailing backslashes continues the command. An even run is literal and does not continue it.
- Jake removes the continuation backslash, line ending, and indentation at the start of the next physical line before execution.
- Jake does not insert whitespace. Authors retain a separator by placing whitespace before the continuation backslash.
- A continuation can span more than two physical lines.
- CRLF and LF line endings behave identically.
- The continued physical lines form one `Recipe.Command` and one shell invocation.
- Silent commands such as `@echo ...` support continuation.
- Recipe metadata and hooks remain single-line: `@cd`, `@shell`, `@pre`, `@post`, and `@on_error` do not support continuation.

For example:

```jake
task concatenate:
    printf '%s\n' foo\
        bar
```

executes `printf '%s\n' foobar`. Jake adds no separator after removing the continuation.

## Architecture

The parser will group continued physical command lines into one logical command. The command's source slice will retain the original backslash, line ending, and indentation so the formatter can reproduce the multiline spelling without allocating a second representation.

Immediately before variable expansion, the executor will normalize that logical command into the string passed to the shell. Normalization removes each continuation sequence and its following indentation. All later execution stages—Jake variable expansion, environment expansion, silent-command handling, dry-run display, and process spawning—operate on the normalized string.

This split keeps responsibilities narrow:

- The parser decides command boundaries.
- The formatter renders the original logical command spelling.
- The executor produces the normalized shell command.

Lexer-level newline suppression was rejected because it would change indentation handling and source diagnostics across the language. Executor-only batching was rejected because the AST, formatter, and inspection output would retain incorrect command boundaries.

## Parser behavior

`parseRecipeBody` will detect continuation from the raw source text before advancing past a physical newline. When a command continues, it will consume the next newline and indentation tokens and keep scanning until it reaches a physical line without an unescaped trailing backslash.

The resulting `Recipe.Command.line` spans the complete source range from the first command byte through the last physical line. Existing source ownership remains unchanged, including imported Jakefiles whose source buffers are retained by the import resolver.

A continued line must still be indented as part of the recipe body. A non-indented next line ends the recipe and leaves the trailing backslash literal; Jake must not absorb a new top-level statement into a command.

## Executor behavior

A focused normalization helper will:

1. Scan a logical command for LF or CRLF line endings.
2. Count the consecutive backslashes immediately before each line ending.
3. Treat an odd count as continuation.
4. Copy all but the final continuation backslash.
5. Skip the line ending and subsequent spaces or tabs.
6. Preserve non-continuation line endings and literal backslashes unchanged.

The helper will return the original slice when no continuation exists and an allocated normalized slice otherwise. The executor will track the allocation with its existing expanded-string cleanup path.

Normalization happens before Jake variables and environment variables are expanded. This ensures expansions see the same command text the shell receives and dry-run output displays one normalized command.

## Formatting

The formatter will continue to render `Recipe.Command.line`. Because the parser stores the complete original logical-command slice, existing continuation breaks and their indentation remain visible after `jake --fmt`.

The formatter will add the normal four-space recipe indentation only before the first physical line. Continuation-line indentation comes from the retained source slice.

## Errors and edge cases

- A trailing backslash at end of file is literal because no following recipe line exists.
- A trailing backslash followed by spaces is literal because it is not immediately before the line ending.
- Two trailing backslashes are literal; three continue while preserving two.
- A blank line ends continuation because it has no indented command content.
- A continuation cannot consume the next recipe, variable, import, or directive at top level.

## Tests

Tests will cover:

- Parser: two physical lines become one `Recipe.Command`.
- Parser: three or more continued lines become one command.
- Parser: silent commands retain their leading `@`.
- Parser: even trailing backslashes do not continue.
- Parser: CRLF input matches LF behavior.
- Executor: shell variables survive across continued physical lines.
- Executor: argument fragments reach the command in one invocation.
- Executor: dry-run output contains one normalized command.
- Formatter: multiline continuation survives formatting and remains parseable.
- End to end: the example from the documentation prints the expected sentence.

The implementation will follow a red-green cycle: add the smallest failing parser or executor regression, verify the expected failure, implement only enough behavior to pass, then repeat for edge cases.

## Documentation

Update the user-facing syntax and examples in:

- `GUIDE.md`
- `docs/SYNTAX.md`
- `docs/TUTORIAL.md`
- `site/src/content/docs/docs/syntax.md`

The documentation will state the exact whitespace and escaping rules, not merely describe the feature as shell continuation.
