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

### v0.2.2 Feature Additions (COMPLETE)
| Feature | Status | Tests | Notes |
|---------|--------|-------|-------|
| Recipe-level @needs | ✅ Complete | 17 tests | Check requirements before commands run |
| @platform directive | ✅ Complete | 3 tests | Alias for @only-os, preferred name |
| @description directive | ✅ Complete | 2 tests | Alias for @desc, both official |
| @on_error targeting | ✅ Complete | 3 tests | Target specific recipes with error hooks |
| without_extensions() | ✅ Complete | 9 tests | Strip all extensions from path |
| Parallel directives | ✅ Complete | 10 tests | @if/@each/@ignore work in -j mode |
| @export fix | ✅ Complete | 7 tests | Variables exported to shell environment |

---

## Test Coverage Summary

| File | Test Count | Coverage |
|------|------------|----------|
| executor.zig | 154 | Excellent |
| parser.zig | 100 | Excellent |
| lexer.zig | 64 | Excellent |
| args.zig | 45 | Excellent |
| functions.zig | 37 | Excellent |
| conditions.zig | 36 | Good |
| parallel.zig | 23 | Good |
| env.zig | 23 | Good |
| cache.zig | 16 | Good |
| suggest.zig | 13 | Good |
| import.zig | 12 | Good |
| hooks.zig | 12 | Good |
| watch.zig | 15 | Good |
| glob.zig | 10 | Good |
| completions.zig | 10 | Good |
| prompt.zig | 8 | Good |
| main.zig | 1 | Minimal |
| root.zig | 1 | Minimal |
| **TOTAL** | **580** | |

**E2E Tests:** `jake e2e` (tests/e2e/Jakefile)

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

**New Function: without_extensions ✅ COMPLETE:**
- [x] Implement `without_extensions(p)` - strips ALL extensions
- [x] `test "without_extensions removes all extensions"` - `without_extensions("file.tar.gz")` → `"file"`
- [x] `test "without_extensions on single extension"` - `without_extensions("file.txt")` → `"file"`
- [x] `test "without_extensions on dotfile"` - `without_extensions(".bashrc")` → `".bashrc"`

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

### Completed Features

1. **Shell Completions** ✅ COMPLETE
   - [x] Generate bash completions (`jake --completions bash`)
   - [x] Generate zsh completions (`jake --completions zsh`)
   - [x] Generate fish completions (`jake --completions fish`)
   - [x] Auto-install command (`jake --completions --install`)
   - [x] Auto-uninstall command (`jake --completions --uninstall`)
   - [x] Smart zsh environment detection (Oh-My-Zsh, Homebrew, vanilla)
   - [x] Idempotent .zshrc patching with marked config blocks
   - [x] Complete recipe names dynamically from Jakefile (via `jake --summary`)
   - [x] Complete flags and options
   - [x] Add `--summary` flag for machine-readable recipe list
   - [x] Shell script tests (`tests/completions_test.sh`)
   - [x] Docker-based isolated testing (`tests/Dockerfile.completions`)

### Upcoming Features

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

---

#### 5. Module-Level @group (Design Decision Pending)

**Problem**: In module files like `jake/web.jake`, every task repeats the same `@group` directive:

```jake
# Current: repetitive
@group web
@desc "Start website dev server"
task dev:
    npm run dev

@group web
@desc "Build website for production"
task build:
    npm run build

@group web
@desc "Deploy website to production"
task deploy:
    vc --prod --yes
```

**Goal**: Allow setting a default group for all recipes in a module file.

---

**Option A: Positional @group (Recommended)**

```jake
# At the very top, before any recipes - becomes file default
@group "web"

@desc "Start website dev server"
task dev:
    npm run dev

@desc "Build website for production"
task build:
    npm run build

# Per-recipe @group still works and overrides the default
@group "deploy"
task deploy:
    vc --prod --yes
```

| Pros | Cons |
|------|------|
| Zero new syntax - reuses existing `@group` | Position-dependent semantics |
| Intuitive placement (top of file = file-wide) | Same syntax, different meaning based on location |
| Minimal parser changes (~10 lines) | Could confuse users initially |
| Works for both imported and standalone modules | |

**Implementation**:
- Add `module_default_group: ?[]const u8` to Parser struct
- Track `has_seen_recipe: bool`
- When parsing @group before first recipe, set as module default
- In recipe creation: `.group = self.consumePendingGroup() orelse self.module_default_group`

---

**Option B: Inherit from Import Prefix**

```jake
# In main Jakefile - group is derived from namespace
@import "jake/web.jake" as web   # All recipes get group "web" automatically
```

| Pros | Cons |
|------|------|
| Zero changes to module files | Less control for module authors |
| Namespace and group naturally align | Doesn't help standalone modules |
| Flexible - importers control grouping | Group tied to import name |

**Implementation**:
- In `import.zig`: if `recipe.group` is null and prefix exists, set `group = prefix`

---

**Option C: Explicit @default Directive**

```jake
@default group: "web"

task dev:
    npm run dev
```

| Pros | Cons |
|------|------|
| Clear intent - explicitly about defaults | New keyword to learn |
| Extensible to other attributes (`quiet`, `shell`) | More parser work (~30 lines) |
| No position ambiguity | Heavier syntax for simple need |

---

**Option D: Implicit from Filename**

```
jake/web.jake      → group "web" (auto-derived)
jake/docker.jake   → group "docker"
```

| Pros | Cons |
|------|------|
| Zero syntax | Magic behavior, less explicit |
| Encourages good file naming | Filename might not match desired group |
| Automatic organization | Main Jakefile wouldn't have natural group |

---

**Recommendation**: **Option A (Positional @group)** or **Option A + B combined**

Option A because:
1. Module authors explicitly declare intent
2. Reuses existing syntax (nothing new to learn)
3. Minimal parser changes
4. Works for both imported and standalone modules

Optionally combine with Option B as automatic fallback for imports.

---

**Test Cases to Add (parser.zig)**:

```zig
// Module-level @group applies to all recipes
test "@group at top of file sets default for all recipes" {
    // @group "build"
    // task compile: ...
    // task link: ...
    // Both should have group = "build"
}

test "@group at top with per-recipe override" {
    // @group "build"
    // task compile: ...      <- group = "build"
    // @group "test"
    // task test: ...         <- group = "test" (override)
}

test "module @group with no recipes is valid" {
    // @group "utils"
    // (empty file or only variables)
}

test "module @group followed by import doesn't affect imported recipes" {
    // @group "local"
    // @import "other.jake"   <- imported recipes keep their own groups
}

test "@group after first recipe is per-recipe not module-level" {
    // task first: ...        <- group = null
    // @group "late"
    // task second: ...       <- group = "late" (per-recipe, not module)
}
```

**Test Cases to Add (import.zig)** - if Option B implemented:

```zig
test "imported recipes inherit group from prefix" {
    // @import "tools.jake" as build
    // recipes from tools.jake get group = "build" if they have no group
}

test "imported recipes with explicit group keep their group" {
    // @import "tools.jake" as build
    // if tools.jake has @group "custom", that takes precedence
}
```

**Test Cases to Add (executor.zig)**:

```zig
test "list command groups recipes by module-level group" {
    // Verify `jake --list` shows grouped output correctly
}
```

---

6. **CLI Commands**
   - [ ] `jake upgrade` / `jake --upgrade` - Self-update from GitHub releases
     - [ ] Check current version against latest GitHub release tag
     - [ ] Use GitHub API: `https://api.github.com/repos/<owner>/<repo>/releases/latest`
     - [ ] Alternative: Use `/releases/latest` redirect to avoid API rate limits
     - [ ] Detect current OS/arch (`builtin.os.tag`, `builtin.cpu.arch`)
     - [ ] Download appropriate binary asset (naming: `jake-{os}-{arch}.tar.gz`)
     - [ ] Optional: Verify signature with minisign (embed public key in binary)
     - [ ] Extract and replace binary in-place (works on macOS/Linux)
     - [ ] Use `curl` as child process for HTTP (smaller binary than std.http)
     - [ ] Handle edge cases: sudo required, read-only filesystem, network errors
     - [ ] `--check` flag to only check for updates without installing
     - [ ] Consider: zig-minisign library for signature verification
     - [ ] Reference implementations:
       - [go-github-selfupdate](https://github.com/rhysd/go-github-selfupdate) (Go patterns)
       - [Zig App Release via GitHub](https://dbushell.com/2025/03/18/zig-app-release-and-updates-via-github/)
       - [go-selfupdate](https://pkg.go.dev/github.com/creativeprojects/go-selfupdate)
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
   - [ ] `--json` flag - Machine-readable JSON output for tooling integration
     - [ ] `jake --list --json` - recipes as JSON array with metadata
     - [ ] `jake --dry-run --json` - execution plan as JSON
     - [ ] `jake <recipe> --json` - execution result/timing as JSON
     - [ ] `jake --vars --json` - resolved variables as JSON object
     - [ ] Consistent schema: `{ "success": bool, "data": ..., "error": ... }`

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
   - [x] Add `.gitattributes` with Makefile highlighting workaround (until native support)
   - [ ] Document `.gitattributes` snippet for users in README/docs
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

   **Phase 7: Language Server Protocol (LSP)**

   *Approach*: Built-in to jake binary (`jake --lsp`) - reuses existing parser, zero extra dependencies for users.

   *Useful features for a task runner* (vs full programming language):
   | Feature | Value | Notes |
   |---------|-------|-------|
   | Diagnostics | ★★★★★ | Parse errors, unknown recipes, undefined vars |
   | Completion | ★★★★★ | Recipe names, @directives, {{variables}}, functions |
   | Hover | ★★★★☆ | Recipe docs, resolved variable values, directive help |
   | Go to Definition | ★★★★☆ | Dependency → recipe, @import → file |
   | Document Symbols | ★★★★☆ | Recipe outline in sidebar |
   | Find References | ★★★☆☆ | "Who depends on this recipe?" |
   | Rename | ★★☆☆☆ | Recipe name refactoring |

   *Implementation tasks*:
   - [ ] Add `jake --lsp` flag (enters LSP stdio mode)
   - [ ] Core LSP handlers: `initialize`, `shutdown`, `textDocument/didOpen`, `didChange`
   - [ ] `textDocument/publishDiagnostics` - reuse existing parse errors + add:
     - Unknown recipe in dependency list
     - Undefined variable reference
     - Missing required parameter
     - Typo suggestions ("did you mean X?")
   - [ ] `textDocument/completion`
     - Recipe names (from parsed Jakefile)
     - @directives (static list with snippets)
     - {{variables}} (from parsed Jakefile + env)
     - Function names with signatures
   - [ ] `textDocument/hover`
     - Recipe: description, dependencies, parameters
     - Variable: resolved value
     - Directive: documentation
     - Function: signature + docs
   - [ ] `textDocument/definition`
     - Recipe dependency → jump to recipe definition
     - @import path → open imported file
     - Variable reference → variable definition
   - [ ] `textDocument/documentSymbol` - recipe list for outline view
   - [ ] `textDocument/references` - find all dependents of a recipe
   - [ ] Update VS Code extension to use LSP (`jake.lspPath` setting)
   - [ ] Document LSP setup for other editors (Neovim, Emacs, Helix, etc.)

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
   - [x] `command(name)` - True if command exists in PATH ✅ COMPLETE
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
    - [x] Test coverage reports with kcov (`jake coverage`, `jake coverage-open`)
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
├── args.zig        # Argument parsing (45 tests)
├── lexer.zig       # Tokenizer (64 tests)
├── parser.zig      # AST builder (100 tests)
├── executor.zig    # Recipe execution (154 tests)
├── cache.zig       # Content hashing (16 tests)
├── conditions.zig  # @if evaluation (28 tests)
├── functions.zig   # String functions (37 tests)
├── glob.zig        # Pattern matching (10 tests)
├── env.zig         # Dotenv/environment (23 tests)
├── import.zig      # @import system (12 tests)
├── watch.zig       # File watching (11 tests)
├── prompt.zig      # @confirm prompts (8 tests)
├── hooks.zig       # @pre/@post hooks (12 tests)
├── completions.zig # Shell completions (10 tests)
├── parallel.zig    # Thread pool exec (23 tests)
├── suggest.zig     # Typo suggestions (13 tests)
├── compat.zig      # Zig 0.14/0.15 compatibility
├── fuzz_parse.zig  # Parser fuzz testing
└── root.zig        # Library exports (1 test)
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

All TDD implementation steps are complete. Run `zig build test` for unit tests and `jake e2e` for E2E tests.

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

None currently! All known bugs have been fixed.

**Recent Bug Fixes (v0.2.2):**

1. **Fixed parallel executor directive handling** - The `-j` flag for parallel execution now correctly handles directives like `@if`, `@elif`, `@else`, `@end`, `@each`, and `@ignore`. Added `executeRecipeCommands()` with full conditional state stack support.

2. **Fixed @export directive** - Variables marked with `@export` are now properly exported to child process environment. Supports `@export KEY=value`, `@export KEY value`, and `@export KEY` (exports Jake variable).

3. **Fixed nested conditionals** - `@if`/`@else`/`@end` blocks inside outer `@if` blocks now work correctly. Previously, the inner `@end` would reset state and cause the outer `@else` to execute incorrectly. Fixed by implementing a conditional state stack in `executeCommands()`.

4. **Fixed @if inside @each loops** - Directives like `@if`, `@else`, `@elif`, `@end` inside `@each` loops now work correctly. Previously they were passed to the shell as commands. Fixed by rewriting `executeEachBody()` to handle directives properly.

5. **Fixed memory leak in hooks** - `expandHookVariables()` returned allocated memory that wasn't freed. Fixed by adding defer cleanup in `executeHook()`.

6. **Added @on_error targeting** - `@on_error` can now target specific recipes: `@on_error deploy echo "Deploy failed!"`. Uses heuristic to distinguish from global hooks.

---

## UX/DX Improvements

### CLI Improvements

1. **Recipe typo suggestions** ✅ COMPLETE
   - [x] Add Levenshtein distance matching for recipe names
   - [x] When recipe not found, suggest closest match: `Did you mean: build?`
   - [x] Implement in main.zig after `RecipeNotFound` error
   - [x] Created `src/suggest.zig` with 14 unit tests

2. **`jake --show <recipe>`** ✅ COMPLETE
   - [x] Display recipe definition, dependencies, commands, metadata
   - [x] Shows: type, group, description, aliases, params, commands, hooks, needs, platform, shell, working_dir
   - [x] Added `-s` shorthand

3. **`--list` improvements** ✅ COMPLETE
   - [x] Add `--list --short` for one recipe name per line (pipeable)
   - [ ] Consider tree-style output for grouped recipes (future)

4. **Watch mode feedback** ✅ COMPLETE
   - [x] Print what patterns are being watched when entering watch mode
   - [x] Example: `[watch] Patterns: src/**/*.ts, Jakefile`

5. **`--list` filtering** (Planned)
   - [ ] `--group GROUP` - Filter recipes to specified group
     - `jake --list --group build` shows only recipes in "build" group
     - Works with `--short`: `jake --list --group build --short`
     - Case-sensitive exact match on `recipe.group`
   - [ ] `--filter PATTERN` - Filter recipes by glob pattern
     - `jake --list --filter 'test*'` shows recipes starting with "test"
     - `jake --list --filter '*lint*'` shows recipes containing "lint"
     - Reuses existing `glob.zig` pattern matching
     - Matches against recipe name (not aliases)
   - [ ] `--groups` - List available group names
     - `jake --groups` outputs one group name per line
     - Sorted alphabetically, no duplicates
   - [ ] Combined filtering: `jake --list --group dev --filter '*test*'`
   - [ ] Error handling: `--group nonexistent` warns "No recipes in group 'nonexistent'"

   **Research**: [just](https://just.systems/man/en/listing-available-recipes.html) uses `--groups` to list groups. [Rake](https://batsov.com/articles/2012/03/08/ruby-tip-number-2-get-a-list-of-all-rake-tasks/) uses `rake -T pattern` for prefix filtering. [Taskfile](https://taskfile.dev/docs/reference/cli) relies on `--json` + external tools.

### Error Message Improvements

5. **Parse errors with source context**
   - [ ] Show the offending line with a caret pointing to the error
   - [ ] Example:
     ```
     error at line 5, column 12: expected ':', found 'ident'
       5 | task build name
         |            ^^^^
     ```

6. **Dependency cycle visualization**
   - [ ] Show the full cycle path: `build -> test -> lint -> build`
   - [ ] Currently only shows the recipe name where cycle was detected

7. **`home()` function failure**
   - [ ] Return explicit error when `$HOME` unset and no passwd fallback
   - [ ] Include hint: `Set HOME environment variable or ensure user entry exists in /etc/passwd`

### Documentation Improvements

8. **Document output suppression options**
   - [ ] Add comparison table: `@quiet` vs `@` prefix vs planned `@silent`
   - [ ] `@quiet` = suppress command echo for whole recipe
   - [ ] `@` prefix = suppress echo for single command
   - [ ] `@silent` = suppress all output including command output

9. **Variable scoping section**
   - [ ] Document when variables are available (global vs recipe vs shell)
   - [ ] Clarify `{{VAR}}` (Jake) vs `$VAR` (shell) vs `@export`
   - [ ] Note: `@export` is currently broken (see Known Issues)

10. **Recipe type decision tree**
    - [ ] Add guidance: When to use `task` vs `file` vs simple recipe
    - [ ] `file` = need dependency tracking, incremental builds
    - [ ] `task` = always runs, explicit intent
    - [ ] simple = quick Make-style syntax

11. **Parallel mode limitations warning**
    - [ ] Document that `-j` doesn't handle `@each`, `@if`, etc.
    - [ ] Add note in `--help` or warn when `-j` used with directive recipes

12. **Import conflict resolution**
    - [ ] Document what happens when two imports define same recipe name
    - [ ] Clarify precedence rules

### DSL Consistency

13. **Hook naming clarity**
    - [ ] Clarify `@pre`/`@post` vs `@before`/`@after` relationship
    - [ ] Document which is canonical, which is alias

14. **Directive naming consistency**
    - [ ] `@only-os` uses hyphen while others don't (`@dotenv`, `@require`)
    - [ ] Consider documenting rationale or adding `@onlyos` alias

**Recent completions:**
- ✅ CLI UX quick wins: `--list --short`, `--show`, typo suggestions (Levenshtein distance)
- ✅ Shell completions: bash, zsh, fish with `--completions` and `--completions --install`
- ✅ Machine-readable output: `--summary` for scripting/completion integration

**Future work:**
1. **Short-term**: Fix parallel executor directive handling, fix @export
2. **Medium-term**: See "Future Features (Detailed Design)" section for:
   - Remote Cache Support (HTTP/S3 backends)
   - Built-in Recipes (@builtin docker/npm/git)
3. **Long-term**: Container execution (@container) and workspace/monorepo support

**Deferred Refactoring:**
- [ ] **executor.zig modularization** - See `REFACTOR.md` for detailed plan
  - Extract `platform.zig` (OS detection, ~40 lines)
  - Extract `system.zig` (command existence checks, ~30 lines)
  - Extract `expansion.zig` (variable expansion, ~80 lines)
  - Extract `directive_parser.zig` (pure parsing, ~200 lines)
  - Extract `display.zig` (recipe listing/display, ~360 lines)
  - Deduplicate code shared with `parallel.zig`
  - Goal: Reduce executor.zig from ~1700 → ~1000 lines of code

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

# Shell completions
./zig-out/bin/jake --completions bash     # Print bash completion script
./zig-out/bin/jake --completions zsh      # Print zsh completion script
./zig-out/bin/jake --completions fish     # Print fish completion script
./zig-out/bin/jake --completions --install  # Auto-detect shell and install

# Machine-readable output for scripting
./zig-out/bin/jake --summary              # Print space-separated recipe names
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

---

## Editor Plugin Development Reference

This section documents the requirements and structure for building editor plugins/extensions for Jake syntax highlighting and language support.

### 1. VS Code Extension (Highest Priority)

**Official Docs**: [Syntax Highlight Guide](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide) | [Language Extensions Overview](https://code.visualstudio.com/api/language-extensions/overview)

**Prerequisites**:
- Node.js 18+
- npm or yarn
- `yo` and `generator-code` for scaffolding: `npm install -g yo generator-code`

**Scaffolding**:
```bash
yo code
# Choose "New Language Support"
# Language id: jake
# Language name: Jake
# File extensions: .jake
# Scope name: source.jake
```

**Extension Structure**:
```
vscode-jake/
├── package.json              # Extension manifest
├── language-configuration.json  # Comments, brackets, indentation
├── syntaxes/
│   └── jake.tmLanguage.json  # TextMate grammar (JSON format)
├── snippets/
│   └── jake.json             # Code snippets (optional)
├── icons/
│   └── jake-icon.png         # File icon (optional)
└── README.md
```

**package.json key fields**:
```json
{
  "contributes": {
    "languages": [{
      "id": "jake",
      "aliases": ["Jake", "Jakefile"],
      "extensions": [".jake"],
      "filenames": ["Jakefile"],
      "configuration": "./language-configuration.json"
    }],
    "grammars": [{
      "language": "jake",
      "scopeName": "source.jake",
      "path": "./syntaxes/jake.tmLanguage.json"
    }]
  }
}
```

**language-configuration.json**:
```json
{
  "comments": { "lineComment": "#" },
  "brackets": [["{", "}"], ["[", "]"], ["(", ")"]],
  "autoClosingPairs": [
    { "open": "{", "close": "}" },
    { "open": "[", "close": "]" },
    { "open": "(", "close": ")" },
    { "open": "\"", "close": "\"" },
    { "open": "'", "close": "'" }
  ],
  "surroundingPairs": [
    { "open": "{", "close": "}" },
    { "open": "[", "close": "]" },
    { "open": "(", "close": ")" },
    { "open": "\"", "close": "\"" },
    { "open": "'", "close": "'" }
  ],
  "indentationRules": {
    "increaseIndentPattern": "^\\s*(task|file)\\s+.*:\\s*$",
    "decreaseIndentPattern": "^\\s*$"
  }
}
```

**TextMate Grammar Structure** (jake.tmLanguage.json):
```json
{
  "scopeName": "source.jake",
  "patterns": [
    { "include": "#comments" },
    { "include": "#variables" },
    { "include": "#recipes" },
    { "include": "#directives" }
  ],
  "repository": {
    "comments": {
      "match": "#.*$",
      "name": "comment.line.number-sign.jake"
    },
    "variables": {
      "match": "^([a-zA-Z_][a-zA-Z0-9_]*)\\s*(=|:=)\\s*(.*)$",
      "captures": {
        "1": { "name": "variable.other.jake" },
        "2": { "name": "keyword.operator.assignment.jake" },
        "3": { "name": "string.unquoted.jake" }
      }
    },
    "recipes": {
      "begin": "^(task|file)\\s+([a-zA-Z_][a-zA-Z0-9_-]*)(.*):\\s*$",
      "beginCaptures": {
        "1": { "name": "keyword.control.jake" },
        "2": { "name": "entity.name.function.jake" },
        "3": { "name": "variable.parameter.jake" }
      },
      "end": "^(?=\\S)",
      "patterns": [{ "include": "#recipe-body" }]
    },
    "directives": {
      "match": "^\\s*(@[a-zA-Z_][a-zA-Z0-9_-]*)\\b",
      "name": "keyword.control.directive.jake"
    }
  }
}
```

**Publishing**:
```bash
npm install -g @vscode/vsce
vsce package          # Creates .vsix file
vsce publish          # Publishes to VS Code Marketplace (requires PAT)
```

**Testing locally**: Press F5 in VS Code to launch Extension Development Host.

---

### 2. IntelliJ Platform Plugin (High Priority)

**Official Docs**: [Custom Language Support Tutorial](https://plugins.jetbrains.com/docs/intellij/custom-language-support-tutorial.html) | [Custom Language Support Reference](https://plugins.jetbrains.com/docs/intellij/custom-language-support.html)

**Prerequisites**:
- IntelliJ IDEA (Community or Ultimate)
- Java 17+ (JBR 17 recommended)
- Gradle 8.x

**Project Setup**:
Use the IntelliJ Platform Plugin Template: https://github.com/JetBrains/intellij-platform-plugin-template

Or create manually with Gradle:
```kotlin
// build.gradle.kts
plugins {
    id("java")
    id("org.jetbrains.intellij") version "1.17.0"
}

intellij {
    version.set("2024.1")
    type.set("IC") // IntelliJ IDEA Community
}
```

**Plugin Structure**:
```
intellij-jake/
├── build.gradle.kts
├── settings.gradle.kts
├── src/main/
│   ├── java/com/jake/intellij/
│   │   ├── JakeLanguage.java         # Language definition
│   │   ├── JakeFileType.java         # File type registration
│   │   ├── JakeIcons.java            # Icons
│   │   ├── lexer/
│   │   │   ├── JakeLexerAdapter.java
│   │   │   └── Jake.flex             # JFlex lexer definition
│   │   ├── parser/
│   │   │   ├── JakeParser.java
│   │   │   └── Jake.bnf              # Grammar-Kit BNF grammar
│   │   ├── psi/                      # PSI element classes
│   │   └── highlighting/
│   │       └── JakeSyntaxHighlighter.java
│   └── resources/
│       ├── META-INF/plugin.xml       # Plugin descriptor
│       └── icons/
│           └── jake.svg
└── src/test/
```

**Minimum Implementation** (lexer-only highlighting):

1. **JakeLanguage.java**:
```java
public class JakeLanguage extends Language {
    public static final JakeLanguage INSTANCE = new JakeLanguage();
    private JakeLanguage() { super("Jake"); }
}
```

2. **JakeFileType.java**:
```java
public class JakeFileType extends LanguageFileType {
    public static final JakeFileType INSTANCE = new JakeFileType();
    private JakeFileType() { super(JakeLanguage.INSTANCE); }
    @Override public String getName() { return "Jake"; }
    @Override public String getDefaultExtension() { return "jake"; }
    @Override public Icon getIcon() { return JakeIcons.FILE; }
}
```

3. **plugin.xml**:
```xml
<idea-plugin>
    <id>com.jake.intellij</id>
    <name>Jake</name>
    <vendor>Jake</vendor>
    <extensions defaultExtensionNs="com.intellij">
        <fileType name="Jake" implementationClass="com.jake.intellij.JakeFileType"
                  fieldName="INSTANCE" language="Jake" extensions="jake"/>
        <lang.parserDefinition language="Jake"
                  implementationClass="com.jake.intellij.parser.JakeParserDefinition"/>
        <lang.syntaxHighlighterFactory language="Jake"
                  implementationClass="com.jake.intellij.highlighting.JakeSyntaxHighlighterFactory"/>
    </extensions>
</idea-plugin>
```

**Lexer Options**:
- **JFlex** (recommended): Write a `.flex` file, generates Java lexer
- **Grammar-Kit**: Write `.bnf` file, generates parser + PSI classes

**Publishing**: Upload to [JetBrains Marketplace](https://plugins.jetbrains.com/) via web interface or Gradle task.

---

### 3. Tree-sitter Grammar (Powers Zed + Neovim)

**Official Docs**: [Creating Parsers](https://tree-sitter.github.io/tree-sitter/creating-parsers/) | [Grammar DSL](https://tree-sitter.github.io/tree-sitter/creating-parsers/2-the-grammar-dsl.html)

**Prerequisites**:
- Node.js 18+
- C compiler (gcc/clang)
- tree-sitter CLI: `npm install -g tree-sitter-cli`

**Setup**:
```bash
mkdir tree-sitter-jake && cd tree-sitter-jake
npm init -y
npm install --save-dev tree-sitter-cli nan
```

**Project Structure**:
```
tree-sitter-jake/
├── grammar.js                 # Grammar definition
├── package.json
├── binding.gyp                # Node.js native binding
├── bindings/
│   ├── node/                  # Node.js bindings
│   └── rust/                  # Rust bindings (for Zed)
├── src/                       # Generated (don't edit)
│   ├── parser.c
│   ├── scanner.c              # External scanner (if needed)
│   └── tree_sitter/
├── queries/
│   ├── highlights.scm         # Syntax highlighting queries
│   ├── indents.scm            # Auto-indentation
│   ├── folds.scm              # Code folding
│   └── locals.scm             # Local variable tracking
└── test/corpus/               # Test cases
    └── recipes.txt
```

**grammar.js Example**:
```javascript
module.exports = grammar({
  name: 'jake',

  extras: $ => [/\s/, $.comment],

  rules: {
    source_file: $ => repeat($._definition),

    _definition: $ => choice(
      $.variable_definition,
      $.recipe
    ),

    comment: $ => /#.*/,

    variable_definition: $ => seq(
      field('name', $.identifier),
      choice('=', ':='),
      field('value', $.value)
    ),

    recipe: $ => seq(
      optional(choice('task', 'file')),
      field('name', $.identifier),
      optional($.parameters),
      ':',
      optional($.dependencies),
      $.recipe_body
    ),

    recipe_body: $ => repeat1($.command),

    command: $ => seq(
      /\t| {4}/,  // Indentation
      choice(
        $.directive,
        $.shell_command
      )
    ),

    directive: $ => seq(
      '@',
      $.identifier,
      optional($.directive_args)
    ),

    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_-]*/,
    value: $ => /.+/,
    shell_command: $ => /.+/,
  }
});
```

**Generate and Test**:
```bash
tree-sitter generate       # Generates src/parser.c
tree-sitter test           # Runs test corpus
tree-sitter parse file.jake  # Parse a file
```

**Query Files** (queries/highlights.scm):
```scheme
(comment) @comment

(variable_definition
  name: (identifier) @variable)

(recipe
  name: (identifier) @function)

(directive) @keyword

["task" "file"] @keyword
["=" ":="] @operator
```

---

### 4. Zed Extension

**Official Docs**: [Language Extensions](https://zed.dev/docs/extensions/languages)

Zed extensions use Tree-sitter grammars compiled to WebAssembly.

**Project Structure**:
```
zed-jake/
├── extension.toml            # Extension manifest
├── languages/
│   └── jake/
│       └── config.toml       # Language configuration
├── grammars/
│   └── jake.toml             # Points to tree-sitter grammar
└── queries/jake/             # Same as tree-sitter queries
    ├── highlights.scm
    ├── indents.scm
    ├── outline.scm           # For outline panel
    └── brackets.scm
```

**extension.toml**:
```toml
id = "jake"
name = "Jake"
version = "0.1.0"
description = "Jake task runner support"
authors = ["Your Name <you@example.com>"]
repository = "https://github.com/you/zed-jake"
```

**languages/jake/config.toml**:
```toml
name = "Jake"
grammar = "jake"
path_suffixes = ["jake"]
file_types = [{ glob = "Jakefile" }]
line_comments = ["# "]
```

**Publishing**: Submit PR to [zed-industries/extensions](https://github.com/zed-industries/extensions) as a submodule.

---

### 5. Neovim (nvim-treesitter)

**Official Docs**: [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)

Once you have a tree-sitter grammar, add Neovim support:

**Option A: Add to nvim-treesitter** (for widespread use):
Submit PR to nvim-treesitter with parser config in `lua/nvim-treesitter/parsers.lua`.

**Option B: Standalone plugin**:
```
nvim-jake/
├── lua/
│   └── nvim-jake/
│       └── init.lua          # Parser registration
├── queries/jake/
│   ├── highlights.scm
│   ├── indents.scm
│   └── folds.scm
├── ftdetect/
│   └── jake.lua              # Filetype detection
└── README.md
```

**lua/nvim-jake/init.lua**:
```lua
local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
parser_config.jake = {
  install_info = {
    url = "https://github.com/you/tree-sitter-jake",
    files = { "src/parser.c" },
    branch = "main",
  },
  filetype = "jake",
}

vim.filetype.add({
  filename = { ["Jakefile"] = "jake" },
  extension = { jake = "jake" },
})
```

---

### 6. Vim (Traditional)

**Reference**: [Writing Vim Syntax Plugins](https://thoughtbot.com/blog/writing-vim-syntax-plugins) | [Learn Vimscript the Hard Way](https://learnvimscriptthehardway.stevelosh.com/chapters/42.html)

**Project Structure**:
```
vim-jake/
├── ftdetect/
│   └── jake.vim              # Filetype detection
├── ftplugin/
│   └── jake.vim              # Filetype-specific settings
├── syntax/
│   └── jake.vim              # Syntax highlighting
├── indent/
│   └── jake.vim              # Indentation rules (optional)
└── README.md
```

**ftdetect/jake.vim**:
```vim
autocmd BufNewFile,BufRead Jakefile setfiletype jake
autocmd BufNewFile,BufRead *.jake setfiletype jake
```

**syntax/jake.vim**:
```vim
if exists("b:current_syntax")
  finish
endif

" Comments
syn match jakeComment "#.*$"

" Keywords
syn keyword jakeKeyword task file

" Directives
syn match jakeDirective "@[a-zA-Z_][a-zA-Z0-9_-]*"

" Variables
syn match jakeVariable "{{[^}]*}}"

" Recipe names
syn match jakeRecipe "^\s*\(task\|file\)\s\+\zs[a-zA-Z_][a-zA-Z0-9_-]*"

" Linking
hi def link jakeComment Comment
hi def link jakeKeyword Keyword
hi def link jakeDirective PreProc
hi def link jakeVariable Identifier
hi def link jakeRecipe Function

let b:current_syntax = "jake"
```

**ftplugin/jake.vim**:
```vim
setlocal commentstring=#\ %s
setlocal expandtab
setlocal shiftwidth=4
setlocal softtabstop=4
```

---

### 7. Sublime Text

**Official Docs**: [Syntax Definitions](https://www.sublimetext.com/docs/syntax.html)

**Project Structure**:
```
sublime-jake/
├── Jake.sublime-syntax
├── Comments.tmPreferences     # Comment key bindings
└── jake.sublime-settings      # Editor settings
```

**Jake.sublime-syntax**:
```yaml
%YAML 1.2
---
name: Jake
file_extensions: [jake]
first_line_match: '^#!.*\bjake\b'
scope: source.jake

contexts:
  main:
    - include: comments
    - include: variables
    - include: recipes
    - include: directives

  comments:
    - match: '#'
      scope: punctuation.definition.comment.jake
      push:
        - meta_scope: comment.line.number-sign.jake
        - match: $\n?
          pop: true

  variables:
    - match: '^([a-zA-Z_]\w*)\s*(=|:=)\s*'
      captures:
        1: variable.other.jake
        2: keyword.operator.assignment.jake

  recipes:
    - match: '^(task|file)\s+([a-zA-Z_][\w-]*)'
      captures:
        1: keyword.control.jake
        2: entity.name.function.jake
      push: recipe_body

  recipe_body:
    - match: '^(?=\S)'
      pop: true
    - include: directives
    - include: shell

  directives:
    - match: '^\s*(@[a-zA-Z_][\w-]*)'
      scope: keyword.control.directive.jake

  shell:
    - match: '^\s+.*$'
      scope: source.shell.embedded.jake
```

**Installation**: Place in `Packages/User/` or create a package for Package Control.

---

### 8. GitHub Linguist

**Official Docs**: [CONTRIBUTING.md](https://github.com/github-linguist/linguist/blob/master/CONTRIBUTING.md)

**Prerequisites**:
- Docker (for grammar testing)
- Ruby + Bundler
- An existing TextMate-compatible grammar

**Quick Win** (user-level .gitattributes):
```gitattributes
# In your repo's .gitattributes
Jakefile linguist-language=Jake
*.jake linguist-language=Jake
```

**Upstreaming to Linguist**:

1. Fork github-linguist/linguist
2. Add grammar using script:
   ```bash
   script/add-grammar https://github.com/you/jake-grammar
   ```
3. Add language to `lib/linguist/languages.yml`:
   ```yaml
   Jake:
     type: programming
     color: "#4a90d9"
     extensions:
       - ".jake"
     filenames:
       - Jakefile
     tm_scope: source.jake
     ace_mode: text
     language_id: 123456789  # Unique ID
   ```
4. Run tests: `script/test`
5. Submit PR

**Requirements for acceptance**:
- Language must have "minimum level of usage" (not just hobby projects)
- Grammar must have approved open-source license
- Grammar must pass Linguist's test suite

---

### Summary: Recommended Implementation Order

| Phase | Editor | Effort | Reusability |
|-------|--------|--------|-------------|
| 1 | VS Code (TextMate) | Medium | High (GitHub, Sublime) |
| 2 | GitHub Linguist | Low | Uses Phase 1 grammar |
| 3 | Tree-sitter | High | High (Zed, Neovim, Helix) |
| 4 | Zed | Low | Uses Phase 3 grammar |
| 5 | Neovim | Low | Uses Phase 3 grammar |
| 6 | Vim | Low | Standalone |
| 7 | IntelliJ | High | JetBrains family only |
| 8 | Sublime Text | Low | Can reuse TextMate or write .sublime-syntax |

**Key insight**: TextMate grammar (Phase 1) unlocks VS Code + GitHub + Sublime. Tree-sitter grammar (Phase 3) unlocks Zed + Neovim + Helix + Emacs. These two grammars provide ~80% of editor coverage.

---

### Tree-sitter Grammar Known Limitations

The tree-sitter grammar (`editors/tree-sitter-jake/`) has the following known limitations:

1. **Escaped quotes in interpolation**: When you have `"{{func(\"arg\")}}"`, the `\"` inside the interpolation conflicts with the outer string context.
   - **Workaround**: Use single quotes inside interpolation: `{{func('arg')}}`

2. **Multi-line command bodies with embedded quotes**: Python/shell scripts spanning multiple lines with embedded quotes aren't parsed correctly.
   - **Workaround**: Use shebangs for multi-line scripts:
     ```jake
     task generate:
         #!/usr/bin/env python3
         for i in range(10):
             print(f"Task {i}")
     ```

3. **File recipe names with paths**: Identifiers like `dist/app.js` containing `.` or `/` are not supported as recipe names.
   - **Workaround**: Use simple identifiers for file recipes or quote the path

These are complex parsing issues that would require significant grammar changes to fix.
