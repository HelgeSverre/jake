# Jake Syntax Specification

This document defines the official terminology and syntax highlighting standards for Jake files.

## File Types

| Extension | Description |
|-----------|-------------|
| `Jakefile` | Main project file (no extension) |
| `*.jake` | Module/library files |

---

## Syntax Components

### 1. Comments

Single-line comments starting with `#`.

```jake
# This is a comment
task build:  # Inline comment
    echo "hello"
```

**Scope Name:** `comment.line.number-sign.jake`

#### Doc Comments

Comments placed **immediately before** a recipe (no blank lines) are captured as documentation and displayed in `jake -l` output:

```jake
# Build the application binary
task build:
    zig build
```

This shows as:
```
  build [task]
    Build the application binary
```

**Important:** A blank line between the comment and recipe prevents capture:

```jake
# This comment is NOT captured (blank line follows)

task build:
    zig build
```

Use `@desc` for explicit descriptions that appear inline:

```jake
@desc "Build the application"
task build:
    zig build
```

Shows as: `build [task]  # Build the application`

---

### 2. Recipe Declarations

Recipes are the primary units of work in Jake. Three types exist:

#### 2.1 Task Recipe

Always executes when called. Introduced with the `task` keyword.

```jake
task build:
    cargo build --release
```

**Scope Names:**
- Keyword `task`: `keyword.control.recipe.jake`
- Recipe name: `entity.name.function.jake`

#### 2.2 File Recipe

Only executes if output file is stale relative to dependencies. Introduced with `file` keyword.

```jake
file dist/app.js: src/**/*.ts
    tsc --outDir dist
```

**Scope Names:**
- Keyword `file`: `keyword.control.recipe.jake`
- Output path: `entity.name.function.jake`
- Dependencies: `string.unquoted.dependency.jake`

#### 2.3 Simple Recipe

Make-style recipe without keyword prefix.

```jake
build:
    cargo build
```

**Scope Names:**
- Recipe name: `entity.name.function.jake`

---

### 3. Recipe Dependencies

Dependencies are specified in square brackets after the recipe name.

```jake
task deploy: [build, test, lint]
    ./deploy.sh
```

**Scope Name:** `entity.name.function.dependency.jake`

---

### 4. Recipe Parameters

Parameters are declared after the recipe name, optionally with defaults.

```jake
task greet name="World":
    echo "Hello, {{name}}!"

task build mode:  # Required parameter
    cargo build --{{mode}}
```

**Scope Names:**
- Parameter name: `variable.parameter.jake`
- Default value: `string.quoted.jake`

---

### 5. Variables

### 5.1 Variable Assignment

Top-level variable assignments.

```jake
VERSION = "1.0.0"
BUILD_DIR = dist
```

**Scope Names:**
- Variable name: `variable.other.jake`
- Operator `=`: `keyword.operator.assignment.jake`

### 5.2 Jake Variable Interpolation

Variables are interpolated using double-brace syntax.

```jake
echo "Version: {{VERSION}}"
echo "Build dir: {{BUILD_DIR}}"
```

**Scope Names:**
- Delimiters `{{` `}}`: `punctuation.definition.variable.begin/end.jake`
- Variable name: `variable.other.bracket.jake`

### 5.3 Environment Variable References

Shell-style environment variable references.

```jake
echo "Home: $HOME"
echo "Path: ${PATH}"
```

**Scope Name:** `variable.language.environment.jake`

### 5.4 Positional Variables

Shell positional parameters.

```jake
echo $1 $2 $@
```

**Scope Name:** `variable.language.positional.jake`

### 5.5 Variable Precedence

When the same variable name is defined in multiple places, the following precedence applies (highest to lowest):

1. **Recipe parameters** (passed via CLI: `jake build env=prod`)
2. **Environment variables** (loaded via `@dotenv` or from shell)
3. **Jakefile variables** (defined with `=` assignment)

This means `@dotenv` should appear **before** variable assignments to allow `.env` files to override defaults:

```jake
@dotenv                    # Load .env first
PORT = "3000"              # Default value (overridden by .env if PORT is set there)

task serve:
    echo "Running on port {{PORT}}"
```

With `.env` containing `PORT=8080`, the task outputs: `Running on port 8080`

Without `.env` or if `PORT` is not set, it uses the default: `Running on port 3000`

---

### 6. Directives

Directives are special commands prefixed with `@`. They fall into two categories:

### 6.1 Global Directives

Appear at the top level of a Jakefile (not indented).

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@import` | Import another Jakefile | `@import "jake/ci.jake" as ci` |
| `@dotenv` | Load environment file | `@dotenv .env.local` |
| `@require` | Require environment variables | `@require NODE_ENV API_KEY` |
| `@export` | Export variable to environment | `@export PATH = $PATH:./bin` |
| `@pre` | Global pre-hook | `@pre echo "Starting..."` |
| `@post` | Global post-hook | `@post echo "Done!"` |
| `@before` | Targeted pre-hook | `@before deploy echo "Deploying..."` |
| `@after` | Targeted post-hook | `@after deploy notify-slack` |
| `@on_error` | Error handler | `@on_error echo "Failed!"` |
| `@default` | Mark next recipe as default | `@default` |

**Scope Name:** `keyword.control.directive.jake`

### 6.2 Recipe Metadata Directives

Appear before a recipe definition to set metadata.

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@group` | Organize recipes into groups | `@group testing` |
| `@desc` / `@description` | Recipe description | `@desc "Build the project"` |
| `@alias` | Alternative recipe names | `@alias b` |
| `@quiet` | Suppress command echoing | `@quiet` |
| `@only` / `@only-os` / `@platform` | OS-specific recipe | `@platform macos linux` |
| `@needs` | Require commands (recipe-level) | `@needs docker kubectl` |

**Scope Names:**
- Directive keyword: `keyword.control.directive.jake`
- Group/description value: `string.quoted.jake` or `string.unquoted.group.jake`
- Platform names: `constant.language.platform.jake`

### 6.3 Recipe Body Directives

Appear inside recipe body (indented).

| Directive | Purpose | Example |
|-----------|---------|---------|
| `@if` | Conditional execution | `@if exists(Cargo.toml)` |
| `@elif` | Else-if branch | `@elif env(CI)` |
| `@else` | Else branch | `@else` |
| `@end` | End conditional/loop | `@end` |
| `@each` | Loop iteration | `@each {{files}}` |
| `@needs` | Require commands | `@needs npm "Install Node.js"` |
| `@confirm` | User confirmation prompt | `@confirm "Deploy to prod?"` |
| `@cache` | Cache based on file | `@cache package-lock.json` |
| `@watch` | Watch files for changes | `@watch src/**/*.ts` |
| `@cd` | Change working directory | `@cd src/app` |
| `@shell` | Set shell interpreter | `@shell bash` |
| `@ignore` | Ignore command failure | `@ignore` |
| `@launch` | Open file/URL cross-platform | `@launch https://example.com` |
| `@require` | Require environment variable | `@require API_KEY` |
| `@export` | Export to environment | `@export NODE_ENV = production` |
| `@pre` | Recipe pre-hook | `@pre echo "Starting..."` |
| `@post` | Recipe post-hook | `@post cleanup` |

**Scope Names:**
- Conditional keywords (`@if`, `@elif`, `@else`, `@end`): `keyword.control.conditional.jake`
- Loop keyword (`@each`): `keyword.control.loop.jake`
- Other directives: `keyword.control.directive.jake`

---

### 7. Condition Functions

Used in `@if` and `@elif` directives.

| Function | Purpose | Example |
|----------|---------|---------|
| `env(VAR)` | Check if env var is set | `@if env(CI)` |
| `exists(path)` | Check if file/dir exists | `@if exists(Cargo.toml)` |
| `eq(a, b)` | String equality | `@if eq({{mode}}, "release")` |
| `neq(a, b)` | String inequality | `@if neq({{OS}}, "windows")` |
| `command(name)` | Check if command exists in PATH | `@if command(docker)` |
| `is_watching()` | Check if in watch mode | `@if is_watching()` |
| `is_dry_run()` | Check if in dry-run mode | `@if is_dry_run()` |
| `is_verbose()` | Check if verbose mode | `@if is_verbose()` |
| `is_platform(name)` | Check OS by name | `@if is_platform(freebsd)` |
| `is_macos()` | Check if running on macOS | `@if is_macos()` |
| `is_linux()` | Check if running on Linux | `@if is_linux()` |
| `is_windows()` | Check if running on Windows | `@if is_windows()` |
| `is_unix()` | Check if running on Unix-like OS | `@if is_unix()` |

**Platform names for `is_platform()`:** `linux`, `macos`, `windows`, `freebsd`, `openbsd`, `netbsd`, `dragonfly`

**Scope Name:** `support.function.condition.jake`

---

### 8. Built-in Functions

Used in `{{...}}` interpolations.

| Function | Purpose | Example |
|----------|---------|---------|
| `uppercase(s)` | Convert to uppercase | `{{uppercase(name)}}` |
| `lowercase(s)` | Convert to lowercase | `{{lowercase(name)}}` |
| `trim(s)` | Trim whitespace | `{{trim(input)}}` |
| `dirname(path)` | Directory component | `{{dirname(/foo/bar.txt)}}` → `/foo` |
| `basename(path)` | Filename component | `{{basename(/foo/bar.txt)}}` → `bar.txt` |
| `extension(path)` | File extension | `{{extension(file.tar.gz)}}` → `.gz` |
| `without_extension(path)` | Remove last extension | `{{without_extension(file.tar.gz)}}` → `file.tar` |
| `without_extensions(path)` | Remove all extensions | `{{without_extensions(file.tar.gz)}}` → `file` |
| `absolute_path(path)` | Make path absolute | `{{absolute_path(./src)}}` |
| `home()` | Home directory | `{{home()}}` → `/Users/helge` |
| `local_bin(name)` | Local bin path | `{{local_bin(jake)}}` → `~/.local/bin/jake` |
| `shell_config()` | Shell config file | `{{shell_config()}}` → `~/.zshrc` |
| `launch(target)` | Platform open command | `{{launch(file.html)}}` → `open file.html` (macOS) |

**Scope Name:** `support.function.jake`

---

### 9. Strings

#### Double-quoted strings
Support escape sequences and variable interpolation.

```jake
echo "Hello, {{name}}!\nPath: $PATH"
```

**Scope Name:** `string.quoted.double.jake`

#### Single-quoted strings
Literal strings (limited escape support).

```jake
echo 'Hello, World!'
```

**Scope Name:** `string.quoted.single.jake`

#### Escape sequences

```
\n \r \t \" \' \\
```

**Scope Name:** `constant.character.escape.jake`

---

### 10. Shell Commands

Lines inside a recipe body that are not directives or comments are shell commands.

```jake
task build:
    echo "Building..."    # This is a shell command
    cargo build --release
    @ignore rm -rf tmp    # Directive followed by shell command
```

**Scope Name:** `meta.shell-line.jake` (container)

---

## Scope Name Summary

| Element | TextMate Scope |
|---------|----------------|
| Comment | `comment.line.number-sign.jake` |
| Recipe keywords (`task`, `file`) | `keyword.control.recipe.jake` |
| Recipe name | `entity.name.function.jake` |
| Dependency | `entity.name.function.dependency.jake` |
| Parameter | `variable.parameter.jake` |
| Variable (assignment) | `variable.other.jake` |
| Variable (interpolation) | `variable.other.bracket.jake` |
| Environment variable | `variable.language.environment.jake` |
| Positional variable | `variable.language.positional.jake` |
| Assignment operator | `keyword.operator.assignment.jake` |
| Global/metadata directive | `keyword.control.directive.jake` |
| Conditional directive | `keyword.control.conditional.jake` |
| Loop directive | `keyword.control.loop.jake` |
| Import keyword | `keyword.control.import.jake` |
| Import `as` keyword | `keyword.control.as.jake` |
| Namespace | `entity.name.namespace.jake` |
| Condition function | `support.function.condition.jake` |
| Built-in function | `support.function.jake` |
| String (double-quoted) | `string.quoted.double.jake` |
| String (single-quoted) | `string.quoted.single.jake` |
| Escape sequence | `constant.character.escape.jake` |
| Platform name | `constant.language.platform.jake` |

---

## Color Scheme Recommendations

For consistent highlighting across editors, map scopes to semantic colors:

| Semantic Role | Scope Pattern | Recommended Color |
|---------------|---------------|-------------------|
| **Comments** | `comment.*` | Gray/Muted |
| **Keywords** | `keyword.control.*` | Purple/Magenta |
| **Recipe/Function names** | `entity.name.function.*` | Blue |
| **Parameters** | `variable.parameter.*` | Orange |
| **Variables** | `variable.other.*`, `variable.language.*` | Cyan/Teal |
| **Strings** | `string.*` | Green |
| **Built-in functions** | `support.function.*` | Yellow/Gold |
| **Constants/Platforms** | `constant.*` | Red/Pink |
| **Operators** | `keyword.operator.*` | Foreground |
| **Namespaces** | `entity.name.namespace.*` | Light Blue |

---

## Token Tag Reference (Lexer)

For implementers, here are the raw token tags from Jake's lexer:

### Keywords
- `kw_task`, `kw_file`, `kw_default`
- `kw_if`, `kw_elif`, `kw_else`, `kw_end`
- `kw_import`, `kw_as`
- `kw_dotenv`, `kw_require`, `kw_watch`, `kw_cache`, `kw_needs`, `kw_confirm`, `kw_each`
- `kw_pre`, `kw_post`, `kw_before`, `kw_after`, `kw_on_error`
- `kw_export`, `kw_cd`, `kw_shell`, `kw_ignore`
- `kw_group`, `kw_desc`, `kw_description`
- `kw_only`, `kw_only_os`, `kw_platform`
- `kw_alias`, `kw_quiet`

### Literals
- `ident` - Identifiers
- `string` - Quoted strings
- `number` - Numeric literals
- `glob_pattern` - File patterns (e.g., `src/**/*.ts`)

### Symbols
- `equals` (=), `colon` (:), `comma` (,), `pipe` (|), `arrow` (->), `at` (@)
- `l_bracket` ([), `r_bracket` (]), `l_brace` ({), `r_brace` (}), `l_paren` ((), `r_paren` ())

### Whitespace
- `newline`, `indent`

### Other
- `comment`, `invalid`, `eof`

---

## References

Research on syntax highlighting approaches from similar tools.

### GNU Make / Makefile

Make has well-established TextMate grammars with the root scope `source.makefile`.

**Key scope conventions:**
| Element | Scope |
|---------|-------|
| Target names | `entity.name.function.target.makefile` |
| Special targets (.PHONY, etc.) | `support.function.target.$1.makefile` |
| User variables | `variable.other.makefile` |
| Built-in variables | `variable.language.makefile` |
| Variable expansions $(VAR) | `string.interpolated.makefile` |
| Built-in functions | `support.function.$1.makefile` |
| Comments | `comment.line.number-sign.makefile` |
| Recipe prefixes (@, -, +) | `keyword.control.$1.makefile` |
| Conditionals (ifdef, etc.) | `keyword.control.ifdef.makefile` |
| Assignment operators | `keyword.operator.assignment.makefile` |

**Sources:**
- [VS Code make.tmLanguage.json](https://github.com/microsoft/vscode/blob/main/extensions/make/syntaxes/make.tmLanguage.json)
- [fadeevab/make.tmbundle](https://github.com/fadeevab/make.tmbundle) (upstream for VS Code)
- [Sublime Text Scope Naming](http://www.sublimetext.com/docs/scope_naming.html)

---

### Just (Command Runner)

Just uses the root scope `source.just` with fine-grained hierarchical scopes.

**Key scope conventions:**
| Element | Scope |
|---------|-------|
| Recipe names | `entity.name.function.just` |
| Recipe parameters | `variable.parameter.recipe.just` |
| Recipe prefixes (@, _) | `keyword.other.recipe.prefix.just` |
| Recipe attributes [private] | `support.function.system.just` |
| Variables | `variable.other.just` |
| Built-in functions | `support.function.builtin.just` |
| Conditionals (if, else) | `keyword.control.conditional.just` |
| Reserved keywords | `keyword.other.reserved.just` |
| Assignment := | `keyword.operator.assignment.just` |
| Quiet operator @ | `keyword.operator.quiet.just` |
| String interpolation {{}} | `string.interpolated.escaping.just` |
| Comments | `comment.line.number-sign.just` |

**Notable patterns:**
- Dependencies use `entity.name.function.just` (same as recipe names, since they are references)
- Tree-sitter distinguishes `@function` (definition) vs `@function.call` (reference)
- Fine-grained operator scopes: `keyword.operator.and.just`, `keyword.operator.equality.just`

**Sources:**
- [nefrob/vscode-just](https://github.com/nefrob/vscode-just) (active TextMate grammar)
- [IndianBoy42/tree-sitter-just](https://github.com/IndianBoy42/tree-sitter-just) (tree-sitter for Neovim/Helix)
- [NoahTheDuke/vim-just](https://github.com/NoahTheDuke/vim-just) (Vim syntax)
- [casey/just GRAMMAR.md](https://github.com/casey/just/blob/master/GRAMMAR.md)

---

### Taskfile (go-task/task)

Taskfile is YAML-based and does **not** use custom TextMate grammars. Instead, it relies on:

1. **JSON Schema validation** via Red Hat YAML extension
2. **Generic YAML syntax highlighting** (keys as `entity.name.tag.yaml`, values as `string.*`)
3. **Third-party extensions** for embedded shell highlighting in command blocks

**Schema-based approach:**
```yaml
# yaml-language-server: $schema=https://taskfile.dev/schema.json
```

**Embedded language highlighting** (via extensions like [vscode-yaml-embedded-languages](https://github.com/harrydowning/vscode-yaml-embedded-languages)):
```yaml
cmds:
  - | # bash
    echo "This gets shell highlighting"
```

**Key insight:** YAML-based tools cannot provide semantic highlighting for task names/dependencies without custom TextMate grammars. Jake's dedicated DSL allows proper syntax highlighting that YAML-based tools cannot achieve.

**Sources:**
- [go-task/vscode-task](https://github.com/go-task/vscode-task) (official extension, no grammar)
- [Taskfile JSON Schema](https://taskfile.dev/schema.json)
- [harrydowning/vscode-yaml-embedded-languages](https://github.com/harrydowning/vscode-yaml-embedded-languages)
- [ruschaaf/extended-embedded-languages](https://github.com/ruschaaf/extended-embedded-languages)

---

### Scope Naming Philosophy

Based on [Sublime Text's scope naming guide](http://www.sublimetext.com/docs/scope_naming.html):

| Scope Category | Purpose | Jake Usage |
|----------------|---------|------------|
| `entity.name.*` | Names of data structures and uniquely-identifiable constructs | Recipe names, namespaces |
| `support.function.*` | Built-in functions from the language/runtime | `uppercase()`, `dirname()`, `env()` |
| `variable.parameter.*` | Function/method parameters | Recipe parameters |
| `variable.other.*` | User-defined variables | Variable assignments |
| `variable.language.*` | Reserved language variables | Environment variables |
| `keyword.control.*` | Control flow and directives | `@if`, `@import`, `task`, `file` |
| `keyword.operator.*` | Operators | `=`, `:=` |
| `meta.*` | Not styled - used by plugins | `meta.recipe.*`, `meta.shell-line.*` |
| `constant.language.*` | Language constants | Platform names, booleans |

---

### General Resources

- [VS Code Syntax Highlight Guide](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide)
- [TextMate Language Grammars Manual](https://macromates.com/manual/en/language_grammars)
- [Tree-sitter Documentation](https://tree-sitter.github.io/tree-sitter/)
- [Writing a TextMate Grammar: Lessons Learned](https://www.apeth.com/nonblog/stories/textmatebundle.html)

