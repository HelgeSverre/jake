# Jake Development Progress

## Implementation Status Overview

### Phase 1: Foundation (COMPLETE)
| Feature | Status | Tests | Notes |
|---------|--------|-------|-------|
| Glob Pattern Matching | ✅ Complete | 10 tests | `src/glob.zig` - *, **, ?, [abc], [a-z] |
| Better Error Messages | ✅ Complete | - | Line/column tracking in lexer/parser |
| Recipe Documentation | ✅ Complete | - | Doc comments parsed, shown in help |

### Phase 2: Core Enhancements (COMPLETE)
| Feature | Status | Tests | Notes |
|---------|--------|-------|-------|
| Watch Mode | ✅ Complete | 1 test | `src/watch.zig` - FSEvents/inotify support |
| Parallel Execution | ✅ Complete | 3 tests | `src/parallel.zig` - Thread pool, topological sort |
| Dotenv Loading | ✅ Complete | 10 tests | `src/env.zig` - Variable expansion, escape sequences |
| Required Env Vars | ✅ Complete | - | @require directive in parser |

### Phase 3: Logic & Modularity (COMPLETE)
| Feature | Status | Tests | Notes |
|---------|--------|-------|-------|
| Conditional Logic | ✅ Complete | 17 tests | @if/@elif/@else/@end in conditions.zig |
| Import System | ✅ Complete | 2 tests | `src/import.zig` - Namespaced imports |

### Phase 4: Advanced Features (COMPLETE)
| Feature | Status | Tests | Notes |
|---------|--------|-------|-------|
| Hooks (@pre/@post) | ✅ Complete | 3 tests | `src/hooks.zig` - Global and recipe hooks |
| String Functions | ✅ Complete | 6 tests | `src/functions.zig` - uppercase, dirname, etc. |

### Recent Feature Additions (COMPLETE)
| Feature | Status | Tests | Notes |
|---------|--------|-------|-------|
| @cd directive | ✅ Complete | 3 tests | Working directory per recipe |
| @shell directive | ✅ Complete | 3 tests | Custom shell per recipe |
| @ignore directive | ✅ Complete | 4 tests | Continue on command failure |
| @group/@description | ✅ Complete | 6 tests | Recipe organization |
| @only-os guards | ✅ Complete | 6 tests | Platform-specific recipes |
| Recipe aliases | ✅ Complete | 6 tests | Alternative recipe names |
| @ output suppression | ✅ Complete | 2 tests | Silent command execution |
| Private recipes (_) | ✅ Complete | 2 tests | Hidden from listing |
| Positional arguments | ✅ Complete | 7 tests | $1, $2, $@ in recipes |

---

## Test Coverage Summary

| File | Test Count | Coverage |
|------|------------|----------|
| executor.zig | 132 | Excellent |
| parser.zig | 83 | Excellent |
| lexer.zig | 64 | Excellent |
| conditions.zig | 17 | Good |
| cache.zig | 16 | Good |
| functions.zig | 16 | Good |
| glob.zig | 10 | Good |
| env.zig | 10 | Good |
| import.zig | 9 | Good |
| watch.zig | 8 | Good |
| prompt.zig | 8 | Good |
| hooks.zig | 8 | Good |
| parallel.zig | 4 | Basic |
| main.zig | 1 | Minimal |
| root.zig | 1 | Minimal |
| **TOTAL** | **387** | |

**E2E Tests:** 47 tests in `tests/e2e_test.sh`

---

## TDD Implementation Checklist

### Step 1: Cleanup & Infrastructure
- [x] Delete test artifacts (`test_*` files in root)
- [x] Add `test_*` to `.gitignore`
- [x] Update TODO.md with TDD tasks

### Step 2: @require - Environment Variable Validation (8 tests) ✅
- [x] `test "@require validates single env var exists"`
- [x] `test "@require fails with clear error when env var missing"`
- [x] `test "@require checks multiple variables in single directive"`
- [x] `test "@require checks multiple @require directives"`
- [x] `test "@require skips validation in dry-run mode"`
- [x] `test "@require error message includes variable name"`
- [x] `test "@require error suggests checking .env file"`
- [x] `test "@require with empty value still passes (var exists but empty)"`
- [x] Implement `validateRequiredEnv()` in executor.zig

### Step 3: @needs - Command Existence Check (7 tests) ✅
- [x] `test "@needs verifies command exists in PATH"`
- [x] `test "@needs fails with helpful error when command missing"`
- [x] `test "@needs checks multiple space-separated commands"`
- [x] `test "@needs works with full path to binary"`
- [x] `test "@needs with non-existent command in middle of list fails"`
- [x] `test "@needs with comma-separated commands"`
- [x] `test "@needs only checks once per command"`
- [x] Implement `checkNeedsDirective()` in executor.zig

### Step 4: @confirm - Interactive Prompts (11 tests) ✅
- [x] `test "@confirm returns true for 'y' input"`
- [x] `test "@confirm returns true for 'Y' input"`
- [x] `test "@confirm returns true for 'yes' input"`
- [x] `test "@confirm returns true for 'YES' input"`
- [x] `test "@confirm returns false for 'n' input"`
- [x] `test "@confirm returns false for 'no' input"`
- [x] `test "@confirm returns false for empty input"`
- [x] `test "@confirm returns false for whitespace-only input"`
- [x] `test "@confirm with --yes flag auto-confirms"`
- [x] `test "@confirm in dry-run mode shows message but doesn't prompt"`
- [x] `test "@confirm with default message"`
- [x] Create `src/prompt.zig`
- [x] Add `--yes` flag to main.zig

### Step 5: @each - Loop Iteration (7 tests) ✅
- [x] `test "@each iterates over space-separated items"`
- [x] `test "@each expands {{item}} variable in command"`
- [x] `test "@each with empty list executes zero times"`
- [x] `test "@each nested in conditional block respects condition"`
- [x] `test "@each with comma-separated items"`
- [x] `test "@each with single item"`
- [x] `test "@each with multiple commands"`
- [x] Implement loop mechanism in executeCommands()

### Step 6: @import Integration (2 tests) ✅
- [x] `test "import resolver init"` (in import.zig)
- [x] `test "prefixed name creation"` (in import.zig)
- [x] ImportResolver implementation complete in `src/import.zig`
- [x] Wire ImportResolver in main.zig (already done - lines 210-225)
- [x] Export `resolveImports` in root.zig (line 26)

### Step 7: @before/@after Hooks (3 tests) ✅
- [x] `test "hook context basic"` (in hooks.zig)
- [x] `test "hook runner init"` (in hooks.zig)
- [x] `test "hook variable expansion"` (in hooks.zig)
- [x] HookRunner implementation complete in `src/hooks.zig`
- [x] Pre/post hooks wired in executor.zig (lines 451-476)
- [x] Global hooks loaded from jakefile during init (lines 99-106)

### Step 8: @cache - Command Caching (7 tests) ✅
- [x] `test "@cache first run always executes"`
- [x] `test "@cache with existing file updates cache"`
- [x] `test "@cache skips command when inputs unchanged"`
- [x] `test "@cache with multiple files"`
- [x] `test "@cache with comma-separated files"`
- [x] `test "@cache with empty deps always runs"`
- [x] `test "parseCachePatterns parses space-separated patterns"`
- [x] Implement `.cache =>` case in executeCommands()
- [x] Implement `parseCachePatterns()` helper

### Step 9: @watch Inline (6 tests) ✅
- [x] `test "@watch in dry-run mode shows what would be watched"`
- [x] `test "@watch is informational in normal mode"`
- [x] `test "@watch with multiple patterns"`
- [x] `test "@watch continues to next command"`
- [x] `test "parseCachePatterns works for watch patterns"`
- [x] `test "@watch with empty pattern is no-op"`
- [x] Implement `.watch =>` case in executeCommands()

### Step 10: Edge Cases & Error Handling (15 tests) ✅
- [x] `test "deeply nested @if blocks (5 levels)"`
- [x] `test "@ignore with command that doesn't exist still continues"`
- [x] `test "empty recipe with only directives executes without error"`
- [x] `test "@each inside @if only runs when condition true"`
- [x] `test "@each inside @if false is skipped"`
- [x] `test "recipe with all directives combined"`
- [x] `test "multiple @if/@else chains"`
- [x] `test "executor returns RecipeNotFound for missing recipe"`
- [x] `test "executor returns CyclicDependency for self-referencing recipe"`
- [x] `test "executor returns CyclicDependency for indirect cycle"`
- [x] `test "@needs continues checking after first found command"`
- [x] `test "variable expansion in commands works with special chars"`
- [x] `test "environment variable expansion with default fallback"`
- [x] `test "recipe with only comments parses correctly"`
- [x] `test "executor handles recipe with spaces in command"`

### Step 11: Test Coverage Improvements (Planned)

#### Functions Module (functions.zig) - Currently 16 tests

**Path Function Edge Cases:**
- [ ] `test "dirname of root returns root"` - `dirname("/")` → `"/"`
- [ ] `test "dirname with no slashes returns dot"` - `dirname("file.txt")` → `"."`
- [ ] `test "basename with trailing slash"` - `basename("dir/")` → `"dir"` (follow PHP/Go/Ruby, strip slash first)
- [ ] `test "basename of empty string"` - `basename("")` → `""`
- [ ] `test "basename of root"` - `basename("/")` → `""` (follow PHP)
- [ ] `test "extension of dotfile returns empty"` - `extension(".bashrc")` → `""` (follow Python behavior)
- [ ] `test "extension of file without extension"` - `extension("README")` → `""`
- [ ] `test "without_extension with multiple dots"` - `without_extension("file.tar.gz")` → `"file.tar"`

**New Function: without_extensions (Haskell-style, plural for consistency):**
- [ ] Implement `without_extensions(p)` - strips ALL extensions
- [ ] `test "without_extensions removes all extensions"` - `without_extensions("file.tar.gz")` → `"file"`
- [ ] `test "without_extensions on single extension"` - `without_extensions("file.txt")` → `"file"`
- [ ] `test "without_extensions on dotfile"` - `without_extensions(".bashrc")` → `".bashrc"`

**System Function Edge Cases:**
- [ ] `test "home returns error when HOME unset"` - Should fail explicitly
- [ ] `test "shell_config with unknown shell falls back to profile"` - `$SHELL=/bin/unknown` → `~/.profile`
- [ ] `test "local_bin constructs correct path"` - `local_bin("jake")` → `$HOME/.local/bin/jake`

**String Function Edge Cases:**
- [ ] `test "uppercase with non-ASCII"` - `uppercase("café")` → behavior TBD
- [ ] `test "trim with only whitespace"` - `trim("   ")` → `""`
- [ ] `test "lowercase preserves numbers and symbols"` - `lowercase("Hello123!")` → `"hello123!"`

#### Conditions Module (conditions.zig) - Currently 17 tests

**Edge Cases:**
- [ ] `test "env with empty variable name returns error"` - `env()` → error (missing argument)
- [ ] `test "exists with empty path"` - `exists("")` → false
- [ ] `test "exists with path containing spaces"` - `exists("/path with spaces")`
- [ ] `test "eq with empty strings"` - `eq("", "")` → true
- [ ] `test "eq is case sensitive"` - `eq("Hello", "hello")` → false
- [ ] `test "eq with too many arguments returns error"` - `eq(a, b, c)` → error (invalid syntax)
- [ ] `test "neq with empty strings"` - `neq("", "")` → false

#### Env/Dotenv Module (env.zig) - Currently 10 tests

**Parsing Edge Cases:**
- [ ] `test "key with equals in value"` - `MY=VAR=value` → key=`MY`, value=`VAR=value`
- [ ] `test "empty key is ignored"` - `=value` → skip line
- [ ] `test "empty value returns empty string"` - `KEY=` → `""`
- [ ] `test "recursive expansion has depth limit"` - `A=$B`, `B=$A` → prevent infinite loop
- [ ] `test "quote mismatch treated as literal"` - `KEY="value'` → include quote in value

#### Parser Edge Cases (parser.zig) - Currently 83 tests

**Dependency List:**
- [ ] `test "empty dependency list parses"` - `task build: []`
- [ ] `test "trailing comma in deps"` - `build: [a, b,]` → `[a, b]`
- [ ] `test "dependency with hyphens"` - `build: [my-dep, test-runner]`

**Parameter Parsing:**
Parameter syntax: `task name param="default":` or `task name param:` (required)
- [ ] `test "parameter with empty quoted default"` - `task build a="":` → param `a` defaults to `""`
- [ ] `test "parameter with no value after equals"` - `task build a=:` → syntax error (require explicit `""`)
- [ ] `test "parameter default with spaces"` - `task build a="hello world":` → param `a` defaults to `"hello world"`
- [ ] `test "required parameter no default"` - `task build a:` → param `a` is required, error if not provided
- [ ] `test "multiple parameters mixed"` - `task deploy env target="prod":` → `env` required, `target` optional

#### Glob Pattern Edge Cases (glob.zig) - Currently 10 tests

**Character Classes:**
- [ ] `test "character range boundaries"` - `[a-z]` matches `a` and `z`
- [ ] `test "negated character class"` - `[!a-z]` matches `A` but not `a`
- [ ] `test "multiple ranges in class"` - `[a-zA-Z0-9]`

**Pattern Edge Cases:**
- [ ] `test "double asterisk at end"` - `src/**` matches all under src
- [ ] `test "empty pattern matches nothing"` - `""` → no matches

---

### Upcoming Features

1. **Shell Completions** ⬅️ IN PROGRESS
   - [ ] Generate bash completions (`jake --completions bash`)
   - [ ] Generate zsh completions (`jake --completions zsh`)
   - [ ] Generate fish completions (`jake --completions fish`)
   - [ ] Auto-install command (`jake --install-completions`)
   - [ ] Complete recipe names dynamically from Jakefile
   - [ ] Complete flags and options

### Future Features (Detailed Design)

#### 1. Remote Cache Support

**Problem**: Local cache (`.jake/cache`) means CI/CD rebuilds from scratch every time.

**Proposed Syntax**:
```jake
# HTTP backend (recommended - simple PUT/GET)
@cache-backend http "https://cache.example.com"
@cache-auth env(JAKE_CACHE_TOKEN)

# S3-compatible backend
@cache-backend s3 bucket="jake-cache" region="us-east-1"

# Fallback chain
@cache-fallback local

# Per-recipe opt-in
file dist/bundle.js: src/**/*.ts
    @remote-cache
    esbuild src/index.ts --bundle -o dist/bundle.js
```

**Implementation Notes**:
- New files: `src/cache_backend.zig`, `src/http_client.zig`
- Cache key: `sha256(recipe_name + sorted_input_hashes + command_text)`
- Store outputs as compressed tarball
- Fallback: remote → local → execute
- CLI: `jake --purge-cache`

**Design Decisions**:
- Support both HTTP and S3 backends
- Content-addressable storage for deduplication
- Auth via headers or env vars

---

#### 2. Container Execution (@container)

**Problem**: Recipes need specific tool versions or isolated environments.

**Proposed Syntax**:
```jake
# Basic - all commands run in container
task build:
    @container node:20-alpine
    npm install
    npm run build

# Advanced options
task build:
    @container image="rust:1.75" mount="./src:/src:ro" env="CARGO_HOME=/cache"
    @container volumes="cache-vol:/cache"
    @container network=host
    cargo build --release

# Named container definitions
@define-container rust-builder
    image: rust:1.75
    mount: ./:/work
    mount: cargo-cache:/usr/local/cargo
    workdir: /work

task build:
    @container rust-builder
    cargo build --release
```

**Implementation Notes**:
- New file: `src/container.zig`
- Runtime detection: podman → docker → nerdctl (auto-detect)
- Auto-mount pwd as `/work`
- Forward @export variables to container
- Support named volumes for caching (node_modules, cargo)

**Edge Cases**:
- Nested containers → error
- Interactive prompts → pass-through TTY
- Exit codes → propagate from container
- Signals → forward SIGINT/SIGTERM

---

#### 3. Workspace/Monorepo Support

**Problem**: Multi-package projects need coordinated builds.

**Proposed Syntax**:
```jake
# Root Jakefile
@workspace packages/*
@workspace apps/*
@workspace-order topological

# Shared variables
version = "2.0.0"

# Run across all packages
task build:
    @workspace-run build

task test:
    @workspace-run test --parallel

task lint:
    @workspace-run lint --parallel --continue-on-error
```

```jake
# packages/core/Jakefile
@package-deps utils, common

task build:
    echo "Building core v{{version}}"
    npm run build
```

**CLI Commands**:
```bash
jake build                    # Build all in order
jake build --package=core     # Specific package
jake build --changed          # Git diff changed only
jake build --since=main       # Changed since branch
jake --list-packages          # Show discovered
```

**Implementation Notes**:
- New file: `src/workspace.zig`
- Reuse topological sort from `parallel.zig`
- Git-based change detection
- Shared variables inherited by packages

---

#### 4. Built-in Recipes

**Problem**: Common tasks require boilerplate.

**Proposed Syntax**:
```jake
@builtin docker
@builtin npm
@builtin git

# Now available: docker:build, docker:push, npm:install, npm:test, git:commit, etc.
```

**Customization**:
```jake
@builtin docker
    registry = "ghcr.io/myorg"
    image_name = "myapp"

# Override specific recipe
task docker:build:
    @description "Custom build"
    docker build --build-arg VERSION={{version}} -t {{image_name}} .
```

**Built-in Catalog**:
- `@builtin docker`: build, push, run
- `@builtin npm`: install, build, test, lint
- `@builtin git`: commit, release, changelog
- `@builtin go`: build, test, lint
- `@builtin rust`: build, test, clippy

**Implementation Notes**:
- New files: `src/builtins.zig`, `src/builtin_loader.zig`
- Embedded in binary + user `~/.jake/builtins/*.jake`
- CLI: `jake --list-builtins`, `jake --show-builtin docker`
- User recipes override built-ins

**Priority Order** (when implementing):
1. Built-in Recipes (simplest, immediate value)
2. Remote Cache (high CI/CD value)
3. Container Execution (reproducible builds)
4. Workspace Support (most complex)

5. **CLI Commands**
   - [ ] `jake init` - Scaffold Jakefile from templates
     - [ ] Store templates in `templates/*.jake`, compile into binary
     - [ ] Auto-detect project type (Node, Go, Rust, Python, etc.)
     - [ ] `jake init --template=node` for explicit selection
     - [ ] Future: Support `github:user/repo` syntax like degit/tiged
   - [ ] `jake fmt` - Auto-format Jakefile
     - [ ] Consistent indentation (4 spaces)
     - [ ] Align `=` in variable definitions
     - [ ] Sort imports alphabetically
     - [ ] `--check` flag for CI

6. **Editor & Syntax Highlighting** (prioritized for adoption)

   **Phase 1: TextMate Grammar + VS Code Extension** (highest leverage)
   - [ ] Create TextMate grammar (`jake.tmLanguage.json`)
     - File associations: `Jakefile` (basename) + `*.jake` (extension)
     - Recipe headers (`task build:`, `file output: deps`)
     - Variable assigns (`FOO := bar`, `FOO = bar`)
     - Directives (`@if`, `@each`, `@cache`, `@require`, etc.)
     - Recipe bodies (shell-like context, handle `#` comments)
     - Modifiers/prefixes (`@`, `-` for silent/ignore)
   - [ ] VS Code extension (`vscode-jake`)
     - Language config (comments, brackets, indentation)
     - Bundle TextMate grammar
     - File icon for Jakefile
     - Publish to VS Code Marketplace
   - [ ] "Run Recipe" UX in VS Code
     - CodeLens above recipe headers
     - Command palette entries
     - Basic completion (recipe names, variable names)

   **Phase 2: GitHub Syntax Highlighting**
   - [ ] Document `.gitattributes` snippet for users (`*.jake linguist-language=Jake`)
   - [ ] Upstream to Linguist (grammar + language definition)
     - Follow [Linguist contribution guide](https://github.com/github-linguist/linguist/blob/main/CONTRIBUTING.md)

   **Phase 3: Tree-sitter Grammar** (powers Zed + Neovim)
   - [ ] Create `tree-sitter-jake` grammar
   - [ ] Write `highlights.scm` queries
   - [ ] Zed extension (uses tree-sitter + highlights.scm)
   - [ ] Neovim plugin (lua, tree-sitter integration)

   **Phase 4: JetBrains Plugin** (IntelliJ/PyCharm/WebStorm/GoLand/etc.)
   - [ ] File type registration
   - [ ] Lexer + basic parser (or lexer-only for minimal highlighting)
   - [ ] Syntax highlighting + brace matching
   - [ ] Gutter run icons for recipes
   - [ ] Publish to JetBrains Marketplace

   **Phase 5: Long Tail Editors**
   - [ ] Vim: `syntax/jake.vim` + `ftdetect/jake.vim`
   - [ ] Sublime Text: `.sublime-syntax` (or reuse TextMate grammar)
   - [ ] Emacs major mode (`jake-mode.el`)
   - [ ] Notepad++: UDL (User Defined Language)

   **Phase 6: Web Syntax Highlighting**
   - [ ] Separate repo: `jakefile-highlight` for highlight.js/prism.js

7. **New Directives**
   - [ ] `@timeout 30s` - Kill recipe if exceeds time limit
   - [ ] `@retry 3` - Retry failed commands N times (with optional delay)
   - [ ] `@env-file .env.local` - Load env file for specific recipe only
   - [ ] `@workdir ./subdir` - Persistent working directory for recipe
   - [ ] `@silent` - Suppress all output (vs `@quiet` which just hides command echo)
   - [ ] `@parallel` - Run commands within a single recipe in parallel

8. **New Functions**
   - [ ] `git_branch()` - Current git branch name
   - [ ] `git_hash()` - Short commit hash (7 chars)
   - [ ] `git_dirty()` - Returns "dirty" if uncommitted changes, else ""
   - [ ] `timestamp()` - Current Unix timestamp
   - [ ] `datetime(format)` - Formatted date/time string
   - [ ] `read_file(path)` - Read file contents into variable
   - [ ] `json(file, path)` - Extract JSON value (e.g., `json(package.json, .version)`)
   - [ ] `env_or(name, default)` - Get env var with fallback default

9. **New Conditions**
   - [ ] `command(name)` - True if command exists in PATH
   - [ ] `file_newer(a, b)` - True if file A is newer than file B
   - [ ] `contains(str, sub)` - True if string contains substring
   - [ ] `matches(str, pattern)` - True if string matches regex pattern
   - [ ] `is_file(path)` - True if path is a file (not directory)
   - [ ] `is_dir(path)` - True if path is a directory

10. **CI/CD & Distribution**
    - [ ] GitHub Actions matrix testing (Linux, macOS, Windows)
    - [ ] Automated release workflow (build binaries on git tag)
    - [ ] Homebrew formula (`brew install jake`)
    - [ ] AUR package for Arch Linux
    - [ ] Scoop manifest for Windows
    - [ ] Nix flake
    - [ ] Docker image (`docker run jake`)

11. **Quality & Testing**
    - [ ] Benchmarks suite (track parser/executor performance over time)
    - [ ] Test coverage reports (kcov or similar)
    - [ ] Property-based/generative tests (structured fuzzing)
    - [ ] Integration test suite with real-world Jakefiles
    - [ ] Regression test for each bug fix

12. **Documentation**
    - [ ] Cookbook: Common patterns (Docker, CI, monorepo, polyglot, etc.)
    - [ ] Migration guide: Makefile → Jakefile (with examples)
    - [ ] Migration guide: Justfile → Jakefile (with examples)
    - [ ] Video tutorial / screencast
    - [ ] Web playground (try Jake in browser via WASM?)
    - [ ] Man page (`man jake`)

---

## Architecture Notes

### File Structure
```
src/
├── main.zig        # CLI entry point (1 test)
├── lexer.zig       # Tokenizer (64 tests)
├── parser.zig      # AST builder (83 tests)
├── executor.zig    # Recipe execution (132 tests)
├── cache.zig       # Content hashing (16 tests)
├── conditions.zig  # @if evaluation (17 tests)
├── functions.zig   # String functions (16 tests)
├── glob.zig        # Pattern matching (10 tests)
├── env.zig         # Dotenv/environment (10 tests)
├── import.zig      # @import system (9 tests)
├── watch.zig       # File watching (8 tests)
├── prompt.zig      # @confirm prompts (8 tests)
├── hooks.zig       # @pre/@post hooks (8 tests)
├── parallel.zig    # Thread pool exec (4 tests)
├── compat.zig      # Zig 0.14/0.15 compatibility
├── fuzz_parse.zig  # Parser fuzz testing
├── root.zig        # Library exports (1 test)
└── completions.zig # Shell completions (planned)
```

### Key Data Structures

**Recipe** (parser.zig):
- `name`, `kind` (task/file/simple)
- `dependencies`, `file_deps`, `output`
- `params`, `commands`
- `aliases`, `group`, `description`
- `shell`, `working_dir`, `only_os`, `quiet`
- `pre_hooks`, `post_hooks`

**Executor** (executor.zig):
- Sequential and parallel execution modes
- Variable expansion ({{var}}, $VAR, ${VAR})
- Positional arguments ($1, $2, $@)
- Conditional block evaluation
- Hook execution (pre/post)
- OS-specific recipe skipping

---

## Next Steps

All TDD implementation steps are complete with 387 passing unit tests + 47 e2e tests.

**Cleanup tasks completed:**
- ✅ Added `--yes`/`-y` flag to main.zig
- ✅ Removed stale TODO comment about @ignore
- ✅ Removed dead Directive.Kind enum values
- ✅ Wired cache persistence (load/save on init/deinit)
- ✅ Implemented recipe.quiet field
- ✅ Wired recipe parameters (params) to variables in executor
- ✅ Wired functions module for `{{func(arg)}}` syntax
- ✅ Updated README example to be self-contained
- ✅ Added 18 new tests (7 params, 7 functions, 5 watch)

**Implementation gap fixes:**
- ✅ Fixed @require validation - now called before execute() in main.zig
- ✅ Fixed @quiet directive parsing - now properly parsed and applied to recipes

**v0.2.1 new features:**
- ✅ Added @each glob expansion - glob patterns in @each are now expanded
- ✅ Added @before/@after targeted hooks - target specific recipes
- ✅ Added @on_error hook - runs when a recipe fails
- ✅ Added 6 new import system tests
- ✅ Added 4 new @each glob expansion tests
- ✅ Added 6 new parser tests for targeted hooks
- ✅ Added 5 new hooks.zig tests
- ✅ Added test for @quiet directive behavior
- ✅ Wired @watch inline directive to watcher for automatic pattern detection
- ✅ Implemented doc_comment parsing from `# comment` before recipes
- ✅ doc_comment now displayed in recipe listings (if different from @description)

**Error handling review (68 catch {} blocks analyzed):**
- 3 `catch {}` converted to `catch return ExecuteError.OutOfMemory` for execution tracking
- ~27 stdout/stderr writes - intentional (can't recover from output failures)
- ~13 defer chdir restores - intentional (best-effort cleanup)
- ~10 init() OOM operations - commented as unrecoverable
- ~15 best-effort operations - commented with failure behavior

**Known Issues (Bugs to Fix):**

1. **Parallel executor doesn't handle directives** - When using `-j` flag for parallel execution, recipes containing directives like `@each`, `@if`, `@else`, etc. don't work correctly. The parallel executor in `parallel.zig` passes directive lines directly to the shell instead of processing them. Fix requires refactoring `executeNode()` to use the same command execution logic as the sequential executor.

2. **@export directive not working** - Variables marked with `@export` aren't being exported to the shell environment. Jake variable syntax (`{{VAR}}`) works correctly, but shell environment variables (`$VAR`) are not populated. The directive is parsed but the export mechanism in the executor isn't wiring variables to the child process environment.

**Recent Bug Fixes (v0.2.2):**

1. **Fixed nested conditionals** - `@if`/`@else`/`@end` blocks inside outer `@if` blocks now work correctly. Previously, the inner `@end` would reset state and cause the outer `@else` to execute incorrectly. Fixed by implementing a conditional state stack in `executeCommands()`.

2. **Fixed @if inside @each loops** - Directives like `@if`, `@else`, `@elif`, `@end` inside `@each` loops now work correctly. Previously they were passed to the shell as commands. Fixed by rewriting `executeEachBody()` to handle directives properly.

3. **Fixed memory leak in hooks** - `expandHookVariables()` returned allocated memory that wasn't freed. Fixed by adding defer cleanup in `executeHook()`.

4. **Fixed @on_error parsing** - The first word after `@on_error` was incorrectly treated as a recipe name. Fixed by making `@on_error` always global (no recipe targeting).

**Future work:**
1. **Short-term**: Shell completions (bash/zsh/fish), fix parallel executor directive handling, fix @export
2. **Medium-term**: See "Future Features (Detailed Design)" section for:
   - Remote Cache Support (HTTP/S3 backends)
   - Built-in Recipes (@builtin docker/npm/git)
3. **Long-term**: Container execution (@container) and workspace/monorepo support

---

## Build & Test Commands

```bash
# Build
zig build

# Run all tests
zig build test

# Run jake with a Jakefile
./zig-out/bin/jake

# Dry run
./zig-out/bin/jake build --dry-run

# Parallel execution
./zig-out/bin/jake build -j4

# Verbose output
./zig-out/bin/jake build -v

# Shell completions (planned)
./zig-out/bin/jake --completions bash > jake.bash
./zig-out/bin/jake --completions zsh > _jake
./zig-out/bin/jake --completions fish > jake.fish
./zig-out/bin/jake --install-completions  # Auto-detect shell and install
```

---

## Future Ideas

### @needs Enhancements

- **Shell alias detection**: Currently `@needs` only checks PATH executables.
  Could optionally detect shell aliases via `type -t cmd` or `alias cmd`.
  Note: Aliases don't work in subprocesses, so this would be informational only.

- **Shell function detection**: Similar to aliases, could detect shell functions.
  Would require spawning a shell to check `type -t cmd` output.

- **Version checking**: `@needs node>=18` to verify minimum versions.
  Would need to run `cmd --version` and parse output.
