# Jake Grammar

This document defines the grammar for Jakefiles parsed by tree-sitter-jake.

## Tokens

```
IDENTIFIER        = [a-zA-Z_][a-zA-Z0-9_-]*
STRING            = "[^"]*"                    # with escape sequences
RAW_STRING        = '[^']*'
INDENTED_STRING   = """..."""                  # multi-line with escapes
INDENTED_RAW      = '''...'''                  # multi-line raw
NUMBER            = \d+
TIMEOUT_VALUE     = \d+[smh]                   # e.g., 30s, 5m, 1h
GLOB_PATTERN      = pattern containing * or **
COMMENT           = #.*
SHELL_VARIABLE    = $VAR | ${VAR} | $1 | $@
INTERPOLATION     = {{ expression }}
NEWLINE           = \n | \r\n
INDENT            = indentation increase
DEDENT            = indentation decrease
```

## Grammar Syntax

```
|   alternation
()  grouping
?   optional (0 or 1)
*   repetition (0 or more)
+   repetition (1 or more)
```

## Grammar

```
source_file     : shebang? item*

item            : recipe
                | assignment
                | import_statement
                | global_directive

assignment      : IDENTIFIER ('=' | ':=') expression NEWLINE

import_statement: '@import' STRING ('as' IDENTIFIER)? NEWLINE

global_directive: dotenv_directive
                | require_directive
                | export_directive
                | default_directive
                | global_hook

dotenv_directive: '@dotenv' (STRING | IDENTIFIER)? NEWLINE

require_directive: '@require' IDENTIFIER+ NEWLINE

export_directive: '@export' IDENTIFIER ('=' expression)? NEWLINE

default_directive: '@default' NEWLINE

global_hook     : ('@pre' | '@post' | '@on_error') hook_command NEWLINE
                | ('@before' | '@after') IDENTIFIER hook_command NEWLINE

hook_command    : (TEXT | INTERPOLATION)+

recipe          : recipe_attribute* recipe_header NEWLINE recipe_body?

recipe_attribute: '@group' (IDENTIFIER | STRING) NEWLINE
                | ('@desc' | '@description') STRING NEWLINE
                | '@alias' IDENTIFIER+ NEWLINE
                | '@quiet' NEWLINE
                | ('@only' | '@only-os' | '@platform') IDENTIFIER+ NEWLINE
                | '@needs' needs_spec+ NEWLINE

needs_spec      : IDENTIFIER '->' IDENTIFIER     # command -> install_task
                | IDENTIFIER STRING              # command "hint"
                | IDENTIFIER                     # just command

recipe_header   : ('task' | 'file')? IDENTIFIER parameters? ':' dependencies?

parameters      : parameter* (parameter | variadic_parameter)

parameter       : '$'? IDENTIFIER ('=' value)?

variadic_parameter: ('*' | '+') parameter

dependencies    : '[' (dependency (',' dependency)* ','?)? ']'

dependency      : IDENTIFIER | IDENTIFIER ':' IDENTIFIER  # namespace:recipe

recipe_body     : INDENT shebang? (body_line)* DEDENT

body_line       : body_directive NEWLINE
                | command_line NEWLINE
                | NEWLINE

body_directive  : if_directive
                | elif_directive
                | else_directive
                | end_directive
                | each_directive
                | cd_directive
                | cache_directive
                | watch_directive
                | confirm_directive
                | ignore_directive
                | shell_directive
                | timeout_directive
                | launch_directive
                | body_needs_directive
                | body_require_directive
                | body_export_directive
                | body_hook

if_directive    : '@if' condition_expression
elif_directive  : '@elif' condition_expression
else_directive  : '@else'
end_directive   : '@end'

each_directive  : '@each' (IDENTIFIER | INTERPOLATION | NUMBER)+

cd_directive    : '@cd' (STRING | IDENTIFIER | INTERPOLATION)

cache_directive : '@cache' (STRING | IDENTIFIER | GLOB_PATTERN)+

watch_directive : '@watch' (STRING | IDENTIFIER | GLOB_PATTERN)+

confirm_directive: '@confirm' (STRING | (TEXT | INTERPOLATION)+)?

ignore_directive: '@ignore'

shell_directive : '@shell' IDENTIFIER

timeout_directive: '@timeout' TIMEOUT_VALUE

launch_directive: '@launch' (STRING | IDENTIFIER | INTERPOLATION)

body_needs_directive: '@needs' needs_spec+

body_require_directive: '@require' IDENTIFIER+

body_export_directive: '@export' IDENTIFIER ('=' expression)?

body_hook       : ('@pre' | '@post') (TEXT | INTERPOLATION)+

condition_expression: condition_function | IDENTIFIER

condition_function: FUNC_NAME '(' sequence? ')'

FUNC_NAME       : 'env' | 'exists' | 'eq' | 'neq' | 'command'
                | 'is_watching' | 'is_dry_run' | 'is_verbose'
                | 'is_macos' | 'is_linux' | 'is_windows' | 'is_unix' | 'is_platform'

command_line    : command_prefix? (TEXT | INTERPOLATION)+

command_prefix  : '@' | '-' | '@-' | '-@'

expression      : '/'? expression_inner

expression_inner: if_expression
                | expression_inner '+' expression_inner
                | expression_inner '/' expression_inner
                | value

if_expression   : 'if' condition '{' expression '}' else_clause?

else_clause     : 'else' (if_expression | '{' expression '}')

condition       : expression ('==' | '!=' | '=~') expression
                | expression

value           : function_call
                | external_command
                | IDENTIFIER
                | string
                | SHELL_VARIABLE
                | '(' expression ')'

function_call   : IDENTIFIER '(' sequence? ')'

external_command: '`' command_body '`'
                | '```' command_body '```'

command_body    : (INTERPOLATION | .)+

sequence        : expression (',' expression)*

string          : STRING
                | RAW_STRING
                | INDENTED_STRING
                | INDENTED_RAW

interpolation   : '{{' expression '}}'

shebang         : '#!' path? ('env' flag*)? IDENTIFIER .*
```

## Condition Functions

Functions available in `@if` and `@elif` conditions:

| Function | Description |
|----------|-------------|
| `env(VAR)` | True if environment variable is set |
| `exists(path)` | True if file/directory exists |
| `eq(a, b)` | True if strings are equal |
| `neq(a, b)` | True if strings are not equal |
| `command(name)` | True if command exists in PATH |
| `is_watching()` | True if running in watch mode |
| `is_dry_run()` | True if running in dry-run mode |
| `is_verbose()` | True if verbose mode enabled |
| `is_macos()` | True on macOS |
| `is_linux()` | True on Linux |
| `is_windows()` | True on Windows |
| `is_unix()` | True on Unix-like systems |
| `is_platform(name)` | True if OS matches name |

## Built-in Functions

Functions available in `{{ ... }}` interpolations:

| Function | Description |
|----------|-------------|
| `uppercase(s)` | Convert to uppercase |
| `lowercase(s)` | Convert to lowercase |
| `trim(s)` | Remove leading/trailing whitespace |
| `dirname(path)` | Directory portion of path |
| `basename(path)` | Filename portion of path |
| `extension(path)` | File extension |
| `without_extension(path)` | Path without extension |
| `without_extensions(path)` | Path without all extensions |
| `absolute_path(path)` | Absolute path |
| `home()` | User's home directory |
| `local_bin(name)` | Path to ~/.local/bin/name |
| `shell_config()` | Path to shell config file |
| `launch(target)` | Platform-specific open command |

## Notes

- Dependencies use bracket syntax: `task build: [dep1, dep2]`
- Interpolation `{{...}}` is supported inside double-quoted strings
- Raw strings (`'...'` and `'''...'''`) do not process interpolation
- The `:=` assignment operator is supported for Just compatibility
- The `@needs` directive supports comma-separated values: `@needs zig, make`
- The `@needs` directive can combine hint and fallback: `@needs cmd "hint" -> fallback_task`

## Known Limitations

The tree-sitter grammar has some known parsing limitations compared to Jake's runtime:

1. **Unquoted paths in condition functions**: Paths containing `/` or `.` in `exists()`, `env()`, etc. should be quoted.
   - Works: `@if exists("path/to/file.txt")`
   - Fails to parse correctly: `@if exists(path/to/file.txt)`

2. **Multi-line strings in commands**: Embedded multi-line strings (e.g., Python heredocs) may not parse correctly as the grammar expects single-line commands.

3. **Dynamic expressions in conditions**: Complex expressions with the path operator `/` inside condition functions may be parsed as path concatenation rather than literal paths.
