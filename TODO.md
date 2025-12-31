# Jake TODO

---

## NOW

### Args Library Improvements (`src/args.zig`)

Comprehensive overhaul inspired by Clap, Cobra, Click, Typer, Commander.js, Yargs, Picocli, zig-clap.

| #  | Feature                       | Complexity | Effort | Impact | Tests |
|----|-------------------------------|:----------:|:------:|:------:|:-----:|
| 1  | "Did you mean?" suggestions   |    Low     |  2-3h  |  High  | 8-10  |
| 2  | Environment variable fallback |   Medium   |  4-6h  |  High  | 12-15 |
| 3  | Double-dash (`--`) separator  |    Low     |  1-2h  | Medium |  5-6  |
| 4  | Negatable flags (`--no-X`)    |   Medium   |  3-4h  | Medium | 10-12 |
| 5  | Repeatable flags (`-vvv`)     |    Low     |  2-3h  | Medium | 8-10  |
| 6  | Flag aliases                  |    Low     |  2-3h  |  Low   |  6-8  |
| 7  | Hidden flags                  |    Low     |   1h   |  Low   |  3-4  |
| 8  | Deprecated flag warnings      |    Low     |   2h   | Medium |  5-6  |
| 9  | Mutually exclusive groups     |   Medium   |  4-5h  | Medium | 10-12 |
| 10 | Required-together groups      |   Medium   |  4-5h  |  Low   | 8-10  |
| 11 | Default values in help        |    Low     |  1-2h  |  High  |  4-5  |
| 12 | Value validation callbacks    |   Medium   |  3-4h  | Medium | 8-10  |
| 13 | Enum/choice restrictions      |   Medium   |  3-4h  | Medium | 8-10  |
| 14 | Flag categories in help       |    Low     |  2-3h  |  High  |  4-5  |
| 15 | NO_COLOR/CLICOLOR support     |    Low     |  1-2h  | Medium |  4-6  |
| 16 | Compile-time validation       |    High    |  6-8h  |  High  |  6-8  |
| 17 | Streaming parser              |    High    | 8-12h  |  Low   | 15-20 |
| 18 | Better error messages         |   Medium   |  4-6h  |  High  | 10-12 |
| 19 | Short flag value (`-fVAL`)    |   Medium   |  3-4h  | Medium | 8-10  |
| 20 | Config file support           |    High    | 10-15h | Medium | 15-20 |

---

#### Phase 1 - Quick Wins (~6h, ~20 tests) ✓ DONE

- [x] **#11 Default values in help** - Show `(default: X)` in help text
- [x] **#3 Double-dash separator** - `--` stops flag parsing (POSIX standard)
- [x] **#7 Hidden flags** - `.hidden = true` excludes from help
- [x] **#15 NO_COLOR support** - Respect `NO_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE` env vars
    - Created `src/color.zig` with runtime Color struct and writer methods
    - Created `src/context.zig` for shared execution context
    - Replaced hardcoded ANSI codes in executor.zig, parallel.zig, hooks.zig, watch.zig
    - **Remaining:** Early error messages in `args.zig` and `main.zig` use comptime `ansi.err_prefix` - would need
      refactoring to use runtime color detection

---

#### Phase 2 - High Impact (~12h, ~30 tests)

- [ ] **#1 "Did you mean?" suggestions** - Levenshtein for unknown flags (reuse suggest.zig)
    - `error: Unknown option: --vrsbose` → `Did you mean '--verbose'?`
- [ ] **#14 Flag categories in help** - Group flags by category
  ```
  GENERAL OPTIONS:
      -h, --help          Show help
  EXECUTION OPTIONS:
      -n, --dry-run       Print without executing
  ```
- [ ] **#8 Deprecated flag warnings** - `.deprecated = "Use --new instead"`
- [ ] **#5 Repeatable/countable flags** - `-vvv` → `verbose_level = 3`

---

#### Phase 3 - Medium Effort (~18h, ~45 tests)

- [ ] **#2 Environment variable fallback** - `.env = "JAKEFILE"` for flag defaults
    - Precedence: CLI arg → env var → default
- [ ] **#18 Better error messages** - Rich context with usage hint
  ```
  error: Invalid value for --jobs: "abc"
         Expected a positive integer
  Usage: jake --jobs [N] [RECIPE]
  ```
- [ ] **#4 Negatable boolean flags** - `--no-verbose` to explicitly disable
- [ ] **#13 Enum/choice restrictions** - `.choices = &.{"json", "yaml", "toml"}`

---

#### Phase 4 - Advanced (~25h, ~45 tests)

- [ ] **#16 Compile-time validation** - Verify Args struct matches flags array
- [ ] **#9 Mutually exclusive groups** - `--list` and `--show` can't be used together
- [ ] **#10 Required-together groups** - If `--username`, must also have `--password`
- [ ] **#12 Value validation callbacks** - Custom validation functions
- [ ] **#6 Flag aliases** - `.aliases = &.{"dryrun", "simulate"}` for `--dry-run`
- [ ] **#19 Short flag value attachment** - `-fcustom.jake` (generalize `-j4`)
- [ ] **#17 Streaming parser** - Process args incrementally for early exit
- [ ] **#20 Config file support** - Load defaults from `.jakeconfig`

---

## NEXT

### CLI Commands

- [ ] `jake upgrade` - Self-update from GitHub releases
    - Check version against latest release tag
    - Detect OS/arch, download appropriate binary
    - Optional signature verification (minisign)
    - `--check` flag to only check for updates

---

- [ ] `jake init` - Scaffold Jakefile from templates
    - Auto-detect project type (Node, Go, Rust, Python)
    - `--template=node` for explicit selection

---

- [x] `jake fmt` - Auto-format Jakefile
    - [x] Consistent 4-space indentation
    - [x] Align `=` in variable definitions
    - [ ] Sort imports alphabetically (deferred to v2)
    - [x] `--check` flag for CI
    - [x] `--dump` flag for stdout output

---

- [ ] `--json` flag - Machine-readable output
    - `--list --json` - recipes as JSON array
    - `--dry-run --json` - execution plan as JSON
    - `--vars --json` - resolved variables as JSON

---

### List Filtering

- [ ] `--group GROUP` - Filter recipes to specified group
- [ ] `--filter PATTERN` - Filter recipes by glob pattern
- [ ] `--groups` - List available group names

---

### New Directives

- [ ] `@timeout 30s` - Kill recipe if exceeds time limit
- [ ] `@retry 3` - Retry failed commands N times
- [ ] `@env-file .env.local` - Load env file for specific recipe
- [ ] `@silent` - Suppress all output (vs @quiet which hides command echo)
- [ ] `@parallel` - Run commands within recipe in parallel

---

### New Functions

- [ ] `git_branch()` - Current git branch name
- [ ] `git_hash()` - Short commit hash (7 chars)
- [ ] `git_dirty()` - Returns "dirty" if uncommitted changes
- [ ] `timestamp()` - Current Unix timestamp
- [ ] `datetime(format)` - Formatted date/time string
- [ ] `read_file(path)` - Read file contents into variable
- [ ] `json(file, path)` - Extract JSON value
- [ ] `env_or(name, default)` - Get env var with fallback

---

### New Conditions

- [ ] `file_newer(a, b)` - True if file A newer than file B
- [ ] `contains(str, sub)` - True if string contains substring
- [ ] `matches(str, pattern)` - True if string matches regex
- [ ] `is_file(path)` - True if path is a file
- [ ] `is_dir(path)` - True if path is a directory

---

## LATER

### CI/CD & Distribution

- [ ] GitHub Actions matrix testing (Linux, macOS, Windows)
- [ ] Automated release workflow (build binaries on tag)
- [ ] Homebrew formula (`brew install jake`)
- [ ] AUR package for Arch Linux
- [ ] Scoop manifest for Windows
- [ ] Nix flake
- [ ] Docker image

---

### Quality & Testing

- [ ] Benchmarks suite (track performance over time)
- [ ] Property-based/generative tests (structured fuzzing)
- [ ] Integration test suite with real-world Jakefiles
- [ ] Regression test for each bug fix

---

### Documentation

- [x] Cookbook: Common patterns (Docker, CI, monorepo)
- [x] Migration guide: Makefile to Jakefile
- [x] Migration guide: Justfile to Jakefile
- [ ] Video tutorial / screencast
- [ ] Man page (`man jake`) (automatically generated from CLI docs)

---

### Error Message Improvements

- [ ] Parse errors with source context (show line with caret)
- [ ] Dependency cycle visualization (`build -> test -> lint -> build`)
- [ ] `home()` failure hint when HOME unset

---

### Deferred Refactoring

- [ ] executor.zig modularization (see REFACTOR.md)
    - Extract platform.zig (~40 lines)
    - Extract system.zig (~30 lines)
    - Extract expansion.zig (~80 lines)
    - Extract directive_parser.zig (~200 lines)
    - Extract display.zig (~360 lines)

---

## IDEA

### Remote Cache Support (unlikely to be useful)

HTTP/S3 backend for CI/CD cache sharing. Cache key = sha256(recipe + inputs + command).

```jake
@cache-backend http "https://cache.example.com"
@cache-auth env(JAKE_CACHE_TOKEN)

file dist/bundle.js: src/**/*.ts
    @remote-cache
    esbuild src/index.ts --bundle -o dist/bundle.js
```

---

### Container Execution

Run recipe commands in Docker/Podman containers.

```jake
task build:
    @container node:20-alpine
    npm install
    npm run build
```

Runtime detection: podman > docker > nerdctl. Auto-mount pwd (or a specified path), forward @export vars.

---

### Workspace/Monorepo Support

Multi-package coordination with dependency ordering.

```jake
@workspace packages/*
@workspace-order topological

task build:
    @workspace-run build --parallel
```

CLI: `jake build --package=core`, `jake build --changed`, `jake --list-packages`


> TODO: needs more details and though into how workflows would look like, what directives are needed, and how it differs
> from regular mode, what scopes and inheritance should be etc.

---

### Built-in Recipes

Common task templates embedded in binary.

```jake
@builtin docker
@builtin npm
@builtin git
```

Catalog: docker (build/push/run), npm (install/build/test), git (commit/release/changelog), go, rust.

---

### Module-Level @group

Default group for all recipes in a module file.

```jake
@group "web"

task dev:
    npm run dev
```

---

### Editor Support - Remaining

Editor integrations exist for: VS Code, Vim/Neovim, Sublime, IntelliJ, Zed, Tree-sitter, Highlight.js, Prism.js, Shiki.

**Blocked on repo being public:**

- [ ] Zed extension (uses `path` to tree-sitter grammar in monorepo)
- [x] GitHub Linguist upstream (submit PR to github-linguist/linguist)

**Publishing:**

- [ ] Publish VS Code extension to Marketplace
- [ ] Publish IntelliJ plugin to JetBrains Marketplace
- [ ] Publish tree-sitter-jake, shiki-jake, prism-jake, highlightjs-jake to npm

**Testing:**

- [ ] Zed isolated testing with `zed --user-data-dir /tmp/zed-test` for extension development

---

### Language Server Protocol

Built into binary: `jake --lsp`

- Diagnostics (parse errors, unknown recipes, undefined vars)
- Completion (recipe names, directives, variables, functions)
- Hover (recipe docs, resolved variable values)
- Go to definition (dependency -> recipe, @import -> file)
- Document symbols (recipe outline)

---

### @needs Enhancements

- Shell alias detection via `type -t cmd`
- Shell function detection
- Version checking: `@needs node>=18`

---

### Optional Telemetry

Opt-in anonymous usage telemetry via Sentry for crash reporting and usage analytics.

- Disabled by default, enable with `JAKE_TELEMETRY=1`
- Respect `DO_NOT_TRACK` env var
- Track: crash reports, feature usage counts, OS/arch distribution
- No PII, no Jakefile contents, no command arguments
