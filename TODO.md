# Jake TODO

---

## NOW

### Args Library Improvements (`src/args.zig`)

Comprehensive overhaul inspired by Clap, Cobra, Click, Typer, Commander.js, Yargs, Picocli, zig-clap.

| #   | Feature                       | Complexity | Effort | Impact | Tests |
| --- | ----------------------------- | :--------: | :----: | :----: | :---: |
| 1   | "Did you mean?" suggestions   |    Low     |  2-3h  |  High  | 8-10  |
| 2   | Environment variable fallback |   Medium   |  4-6h  |  High  | 12-15 |
| 3   | Double-dash (`--`) separator  |    Low     |  1-2h  | Medium |  5-6  |
| 4   | Negatable flags (`--no-X`)    |   Medium   |  3-4h  | Medium | 10-12 |
| 5   | Repeatable flags (`-vvv`)     |    Low     |  2-3h  | Medium | 8-10  |
| 6   | Flag aliases                  |    Low     |  2-3h  |  Low   |  6-8  |
| 7   | Hidden flags                  |    Low     |   1h   |  Low   |  3-4  |
| 8   | Deprecated flag warnings      |    Low     |   2h   | Medium |  5-6  |
| 9   | Mutually exclusive groups     |   Medium   |  4-5h  | Medium | 10-12 |
| 10  | Required-together groups      |   Medium   |  4-5h  |  Low   | 8-10  |
| 11  | Default values in help        |    Low     |  1-2h  |  High  |  4-5  |
| 12  | Value validation callbacks    |   Medium   |  3-4h  | Medium | 8-10  |
| 13  | Enum/choice restrictions      |   Medium   |  3-4h  | Medium | 8-10  |
| 14  | Flag categories in help       |    Low     |  2-3h  |  High  |  4-5  |
| 15  | NO_COLOR/CLICOLOR support     |    Low     |  1-2h  | Medium |  4-6  |
| 16  | Compile-time validation       |    High    |  6-8h  |  High  |  6-8  |
| 17  | Streaming parser              |    High    | 8-12h  |  Low   | 15-20 |
| 18  | Better error messages         |   Medium   |  4-6h  |  High  | 10-12 |
| 19  | Short flag value (`-fVAL`)    |   Medium   |  3-4h  | Medium | 8-10  |
| 20  | Config file support           |    High    | 10-15h | Medium | 15-20 |

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

#### Phase 2 - High Impact (~12h, ~30 tests) ✓ DONE

- [x] **#1 "Did you mean?" suggestions** - Levenshtein for unknown flags (reuse suggest.zig)
  - `error: Unknown option: --vrsbose` → `Did you mean '--verbose'?`
  - Implemented in `args.zig` using `suggest.levenshteinDistance()`
  - Added 11 tests for flag suggestions
- [x] **#14 Flag categories in help** - Group flags by category
  - Categories: General, Output, Execution, File, Shell
  - Added `.category` field to Flag struct
  - Updated `printHelp()` to group flags by category
  - Added 5 tests for category headers
- [x] **#8 Deprecated flag warnings** - `.deprecated = "Use --new instead"`
  - Added `.deprecated` field to Flag struct
  - Prints warning to stderr when deprecated flag used
  - Infrastructure ready for future deprecations
- [x] **#5 Repeatable/countable flags** - `-vvv` → `verbose_level = 3`
  - Added `.countable` field to Flag struct
  - Added `verbose_level: u8` to Args struct
  - `-v`, `-vv`, `-vvv` increment verbose_level
  - Added 7 tests for counting behavior
- [x] **#4 Negatable boolean flags** - `--no-verbose` to explicitly disable
  - Added `.negatable` field to Flag struct
  - `--no-verbose` and `--no-yes` supported
  - Added 7 tests for negation behavior

---

#### Phase 3 - Medium Effort (~18h, ~45 tests) ✓ DONE

- [x] **#2 Environment variable fallback** - `.env = "JAKEFILE"` for flag defaults
  - Added `.env` field to Flag struct
  - Precedence: CLI arg → env var → default
  - `applyEnvFallbacks()` applies after parsing
  - Environment vars: JAKEFILE, JAKE_JOBS, JAKE_VERBOSE, JAKE_YES, JAKE_DRY_RUN
  - Help output shows `[env: VARNAME]` hint
  - Added 4 tests for env fallback behavior
- [x] **#6 Flag aliases** - `.aliases = &.{"dryrun", "simulate"}` for `--dry-run`
  - Added `.aliases` field to Flag struct
  - `matchLongFlag()` checks both primary name and aliases
  - Example: `--dryrun` works as alias for `--dry-run`
  - Added 5 tests for alias matching
- [x] **#19 Short flag value attachment** - `-fcustom.jake` (generalize `-j4`)
  - Generalized `-jN` to work with any short flag that takes a value
  - `-fcustom.jake`, `-sbuild`, `-j4` all work
  - Added 7 tests for short flag value attachment
- [x] **#18 Better error messages** - Rich context with usage hint
  - Added `ErrorContext` struct for rich error info
  - `printErrorWithContext()` shows value, expected type, usage hint
  - `printUsageHint()` shows flag-specific usage examples
  - Added 6 tests for enhanced error messages
- [x] **#13 Enum/choice restrictions** - `.choices = &.{"json", "yaml", "toml"}`
  - Added `.choices` field to Flag struct
  - `isValidChoice()` validates against allowed values
  - `--completions` now validates bash/zsh/fish
  - Added 4 tests for choice validation

---

#### Phase 4 - Advanced (~25h, ~45 tests) ✓ DONE

- [x] **#16 Compile-time validation** - Verify flags array at compile time
  - `validateNoDuplicateShortFlags()` - catch duplicate short flags
  - `validateNoDuplicateLongFlags()` - catch duplicate long flags
  - `validateAliasesUnique()` - ensure aliases don't conflict with primary names
  - `validateCategories()` - ensure all categories are valid
  - Validation runs automatically at compile time
- [x] **#9 Mutually exclusive groups** - `--list` and `--show` can't be used together
  - Added `.mutually_exclusive` field to Flag struct
  - `validateConstraints()` checks at parse time
  - Returns `error.MutuallyExclusive` on conflict
  - Added 4 tests for mutual exclusivity
- [x] **#10 Required-together groups** - `--check` requires `--fmt`
  - Added `.requires` field to Flag struct
  - `--check` and `--dump` require `--fmt`
  - Returns `error.RequiredTogether` when constraint violated
  - Added 5 tests for required-together constraints
- [x] **#12 Value validation callbacks** - Built-in validators
  - Added `Validator` enum: none, positive_integer, non_negative_integer, file_path, shell_name
  - Added `.validator` field to Flag struct
  - `runValidator()` executes validation
  - `getValidatorDescription()` provides human-readable error hints
  - Added 10 tests for validator functions
- [x] **#17 Streaming parser** - Quick scan for early exit
  - Added `QuickAction` enum: none, help, version
  - `quickScan()` scans for --help/-h/--version/-V without full parsing
  - Enables fast exit for common info-only invocations
  - Added 8 tests for quick scan functionality
- [ ] **#20 Config file support** - Load defaults from `.jakeconfig` (deferred)

---

## NEXT

### CLI Commands

- [x] `jake upgrade` - Self-update from GitHub releases
  - Check version against latest release tag
  - Detect OS/arch, download appropriate binary
  - SHA256 checksum verification
  - `--check` flag to only check for updates

---

- [x] `jake init` - Scaffold Jakefile from templates
  - [x] `--template=starter|blank` for explicit selection
  - [x] `--force` to overwrite existing Jakefile
  - [x] `--path=<PATH>` for custom filename

### `jake init` Enhancements (Phase 2) ✓ DONE

| Feature | Status | Notes |
|---------|--------|-------|
| Project detection | ✓ DONE | Detects via marker files |
| Language templates | ✓ DONE | node, go, rust, python, zig |
| Interactive mode | LATER | Prompt when TTY and no --template |
| `--yes` flag | ✓ DONE | Infrastructure ready |

#### Project Detection (marker files) ✓

Checks for these files in cwd (first match wins):

| Type | Marker File |
|------|-------------|
| Node | `package.json` |
| Rust | `Cargo.toml` |
| Go | `go.mod` |
| Python | `pyproject.toml`, `requirements.txt` |
| Zig | `build.zig` |

**Behavior:**
- Match found → auto-select template, print "Detected X project, using Y template"
- No match → use `starter` template

#### Language Templates ✓

| Template | Key Tasks |
|----------|-----------|
| `node` | setup, build, test, lint, dev, fmt |
| `go` | build, test, fmt, vet, run |
| `rust` | build, test, fmt, clippy, run, doc |
| `python` | setup (venv), test, fmt, lint, typecheck |
| `zig` | build, test, fmt, run |

---

- [x] `jake fmt` - Auto-format Jakefile
  - [x] Consistent 4-space indentation
  - [x] Align `=` in variable definitions
  - [x] `--check` flag for CI
  - [x] `--dump` flag for stdout output
  - Note: Import sorting intentionally NOT included - reordering imports can change
    behavior (later imports override earlier ones) making it unsafe for a formatter

---

- [x] `--json` flag for listing output
  - `--list --json` / `--summary --json` / `--groups --json` - machine-readable listing output
  - [ ] `--dry-run --json` - execution plan as JSON
  - [ ] `--vars --json` - resolved variables as JSON

---

### List Filtering

- [x] `--group GROUP` - Filter recipes to specified group (aka, show only "dev" commands with `jake --group dev`, etc.)
- [x] `--filter PATTERN` - Filter recipes by glob pattern: `jake --filter "test*"`
- [x] `--type TYPE` - Filter recipes by type: `jake --type file`, `jake --type task`, `jake --type simple`, or `jake --type external`
- [x] `--groups` - List available group names

---

### Remote commands (task runs on ssh server, ala laravel envoy)

```
task backup:
    @remote

```

---

### New Directives

- [x] `@timeout 30s` - Kill recipe if exceeds time limit (with proper process termination)
- [ ] `@retry 3` - Retry failed commands N times
- [ ] `@env-file .env.local` - Load env file for specific recipe
- [ ] `@silent` - Suppress all output (vs @quiet which hides command echo)
- [ ] `@parallel` - Run commands within recipe in parallel

---

### New Functions

- [ ] `git_branch()` - Current git branch name (e.g. `main`, `feature/x`)
- [ ] `git_hash()` - Short commit hash (7 chars), e.g. `a1b2c3d`
- [ ] `git_dirty()` - Returns "dirty" if uncommitted changes (or true/false?)
- [ ] `git_author_name()` - Current git author name
- [ ] `git_author_email()` - Current git author email
- [ ] `git_tag()` - Current git tag (or empty string)
- [ ] `uuid()` - Generate a random UUIDv4
- [ ] `unix()` - Shorthand/alias for `timestamp()`
- [ ] `kebab()` - Example Text -> example-text
- [ ] `snake()` - Example Text -> example_text
- [ ] `upper()` - Example Text -> EXAMPLE TEXT
- [ ] `lower()` - Example Text -> example text
- [ ] `timestamp()` - Current Unix timestamp (seconds since epoch, 1970-01-01 eg: `1700000000` ->
      `Tue Nov 14 2023 22:13:20 GMT+0000`)
- [ ] `datetime(format)` - Formatted date/time string (Which format patterns? PHP, JS, Python?)
- [ ] `read_file(path)` - Read file contents into variable
- [ ] `json(file, path)` - Extract JSON value
- [ ] `env_or(name, default)` - Get env var with fallback (maybe)

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

- [x] GitHub Actions matrix testing (Linux, macOS, Windows)
- [ ] Automated release workflow (build binaries on tag)

---

#### Install Script (macOS/Linux) ✓ DONE

Simple curl-to-shell installer covering ~90% of users.

**File:** `site/public/install.sh` (served at jakefile.dev/install.sh)

**Features:**

- Multi-platform: Linux, macOS, FreeBSD
- Multi-arch: x86_64, aarch64, armv7
- curl/wget fallback
- Colored terminal output
- Binary verification before install
- PATH detection with shell-specific suggestions (bash/zsh/fish)
- Configurable via `JAKE_VERSION` and `JAKE_INSTALL` env vars

**User installation:** `curl -fsSL jakefile.dev/install.sh | sh`

**Checklist:**

- [x] Create `install.sh`
- [x] Host at predictable URL (site/public/)
- [ ] Test on macOS (Intel + ARM) and Linux
- [x] Document in README

---

#### Homebrew Tap (macOS/Linux)

Custom tap - no popularity requirements.

**Repository:** `github.com/<user>/homebrew-tap`

**File:** `Formula/jake.rb`

```ruby

class Jake < Formula
  desc "Modern command runner/build system"
  homepage "https://github.com/<user>/jake"
  version "X.Y.Z"
  license "MIT"

  on_macos do
    on_intel do
      url "https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-macos-x86_64.tar.gz"
      sha256 "..."
    end
    on_arm do
      url "https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-macos-aarch64.tar.gz"
      sha256 "..."
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-linux-x86_64.tar.gz"
      sha256 "..."
    end
    on_arm do
      url "https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-linux-aarch64.tar.gz"
      sha256 "..."
    end
  end

  def install
    bin.install "jake"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/jake --version")
  end
end
```

**User installation:** `brew install <user>/tap/jake`

**Checklist:**

- [ ] Create `homebrew-tap` repository
- [ ] Add `Formula/jake.rb`
- [ ] Add GitHub Action to auto-update on release
- [ ] Document in README

---

#### Winget (Windows)

Microsoft's official package manager. No popularity requirements - just submit PR.

**Repository:** Submit to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs)

**File:** `manifests/j/Jake/Jake/X.Y.Z/Jake.Jake.yaml`

```yaml
PackageIdentifier: Jake.Jake
PackageVersion: X.Y.Z
PackageLocale: en-US
Publisher: Jake
PackageName: Jake
License: MIT
ShortDescription: Modern command runner/build system
PackageUrl: https://github.com/<user>/jake
Installers:
  - Architecture: x64
    InstallerType: zip
    NestedInstallerType: portable
    NestedInstallerFiles:
      - RelativeFilePath: jake.exe
        PortableCommandAlias: jake
    InstallerUrl: https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-windows-x86_64.zip
    InstallerSha256: ...
  - Architecture: arm64
    InstallerType: zip
    NestedInstallerType: portable
    NestedInstallerFiles:
      - RelativeFilePath: jake.exe
        PortableCommandAlias: jake
    InstallerUrl: https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-windows-aarch64.zip
    InstallerSha256: ...
ManifestType: singleton
ManifestVersion: 1.6.0
```

**User installation:** `winget install Jake.Jake`

**Checklist:**

- [ ] Create manifest YAML
- [ ] Submit PR to microsoft/winget-pkgs
- [ ] Set up [winget-create](https://github.com/microsoft/winget-create) for updates
- [ ] Document in README

---

#### Docker (Deferred)

For edge cases requiring containerized builds.

- [ ] Create minimal Dockerfile
- [ ] Publish to GitHub Container Registry
- [ ] Auto-build on release

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

- [x] Parse errors with source context (show line with caret)
- [ ] Dependency cycle visualization (`build -> test -> lint -> build`)
- [ ] `home()` failure hint when HOME unset

---


### Ability to add group level descriptions

```just
@group "build" "Build-related tasks"
task build:
  bun format
  bun run dev
  # etc etc
```

### Ability to hide modules from list output (or do i mean groups?)

sometimes you want to have helper modules that define common recipes or variables, but don't want them to show up in the
main `jake -l` output, (eg: profiling commands like in @jake/profiling.jake)

1. should it be:

- a: directive in the module (@hide in .jake)
- b: a modifier on import (@import "x.jake" hidden (would work for per-import hiding, or reuse "as name" syntax eg "
  import "debug.jake" as \_debug")) whick can still be called and referenced, but implicitly jsut wont show up in the
  listing

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

---

### Bug in zed-extension Runnable, does not honor the import aliasing

When importing a Jake module with an alias in Zed, the Runnable feature does not recognize the alias and fails to run
the recipes defined in that module.

```jake
# file. Jakefile

@import "jake/stats.jake" as stats
```

```jake

# file: jake/stats.jake
@import "utils.jake" as utils

@group stats
@desc "Find TODO:/FIXME:/HACK: comments in source"
task todos: # '<-- click here in zed'
    @ignore
    grep -rn "TODO:\|FIXME:\|HACK:\|XXX:" src/ || echo "No TODOs found!"
```

```
error: Recipe 'todos' not found
Run 'jake --list' to see available recipes.

⏵ Task `jake todos` finished with non-zero error code: 1
⏵ Command: /bin/zsh -i -c 'jake'
```

because it was imported as `stats`, the correct way to reference it would be `stats.todos`, but Zed's Runnable does not
know that (yet)

---

### ~~SHIKI, prismjs and highlijs - overengineering~~ ✅

~~SHIKI, prismjs and highlijs distribtion abstraction "Jakefile.register()" is overly complicated, jsut provide the data
and instructions on how to use the grammar/language definition tailored for each library, dont overengineer it.~~

**COMPLETED**: Simplified all three packages to just export the grammar/language definition directly:

- `prism-jake`: Exports grammar object, users do `Prism.languages.jake = jake`
- `highlightjs-jake`: Exports language function, users do `hljs.registerLanguage('jake', jake)`
- `shiki-jake`: Exports TextMate grammar, users pass to `langs: [jake]`

Removed the `Jakefile.register()` abstraction and updated:

- All three package READMEs with clear standard usage patterns
- Website documentation at `site/src/content/docs/guides/js-syntax-highlighters.mdx`
- `SyntaxDemo.astro` component to use standard APIs
- Created `SIMPLIFICATION.md` and `BEFORE_AFTER.md` docs explaining the changes

**Fixed browser compatibility** by implementing UMD pattern:

- Files now work in browser `<script>` tags, CommonJS, and ES modules
- Built minified files with `jake editors.build-highlighters`
- Created `UMD_FIX.md` documenting the solution

**Made grammars more consistent** across all three libraries:

- Added built-in function highlighting to Prism and highlight.js (19 functions)
- Changed highlight.js to use generic directive pattern (matches any `@directive`)
- Ensured pattern order prioritizes built-ins before generic patterns
- Created `CONSISTENCY_IMPROVEMENTS.md` and `GRAMMAR_COMPARISON.md`
- All three now highlight the same elements while respecting each library's architecture

---

## Concept Review Feedback (pre-1.0)

External review of Jake as a concept/product. Captured for later evaluation —
not all of these are necessarily right, but each is worth a deliberate
yes/no before 1.0.

### Pitch & positioning

- [ ] Reframe README from "best of Make and Just" to lead with the actual
      wedge: *Make's correctness model (file targets, stale rebuilds) with
      Just's ergonomics, in a fast single binary*. Current framing puts Jake
      directly in Just's competitive frame where Just wins on maturity.
- [ ] "Smart rebuilds" oversells what is `mtime`-based file targets. Either
      back it with content hashing or rename it to be honest about the
      mechanism.
- [ ] Decide the audience: solo devs who want Just + rebuilds (small
      surface, polish path), or teams replacing Make in real build pipelines
      (correctness, hermeticity, caching primitives). Current feature set
      straddles. Straddling is expensive.

### Surface area / scope creep

- [ ] Inventory all `@directives` and cut or merge before 1.0. Current
      count (~30+) is well past Just's "deliberately small" stance.
- [x] Resolve directive aliases — kept `@desc` (dropped `@description`) and
      `@platform` (dropped `@only` and `@only-os`). Lexer, parser, formatter,
      docs, examples, and editor grammars all updated.
- [x] Audit hook system. Final design: `@pre`/`@post`/`@on_error` are
      available at both global (top-level, no name) and recipe-body
      (indented inside recipe) scope. `@before recipe` / `@after recipe`
      remain as the cross-cutting form for attaching hooks to recipes
      defined elsewhere (e.g., imported). Top-level targeted `@on_error`
      removed (had no real users; was the source of POTENTIAL_ISSUES #3).
- [ ] Decide whether the web UI (`webui.zig`, ~1700 lines) belongs pre-1.0
      or should be feature-gated / extracted until core is stable.
- [x] `parser.zig` Tier 1 structural pass: extracted 13 per-directive
      handlers from the 375-line `parseDirective` chain, and unified recipe
      finalization into a single `finalizeRecipe` helper used by all 3
      recipe parsers. Tier 2 (data-driven dispatch table, collapse
      `pending_X` cluster, unify recipe body parsing) deferred until the
      directive surface is pruned.

### Correctness items already known (cross-ref POTENTIAL_ISSUES.md)

- [x] Fix `@on_error` parsing heuristic. Top-level `@on_error` is now
      always global; body-level `@on_error` (inside recipe) is the
      recipe-specific form, mirroring `@pre`/`@post`. The heuristic is
      gone. (POTENTIAL_ISSUES #3)
- [ ] Remove global `chdir()` from Jakefile loading — process-wide side
      effect from a load operation breaks embedders and concurrent loads.
      (POTENTIAL_ISSUES #1)
- [ ] Route hooks through the same shell-selection abstraction as the rest
      of the codebase — hard-coded `/bin/sh` breaks Windows.
      (POTENTIAL_ISSUES #2)

### Open questions to resolve before 1.0

- [ ] What is Jake's *one-line* differentiator vs Just for a developer who
      already uses Just happily? File targets is the answer; make sure the
      docs and landing page make this immediately obvious.
- [ ] Lock the directive surface — every `@thing` shipped in 1.0 is a
      forever-API. Better to ship fewer.
- [ ] Decide whether parallel cache merge (POTENTIAL_ISSUES #4) is a 1.0
      blocker or a "fix when someone hits it" item. Depends on target user
      (small Jakefiles vs. real build pipelines).

---

# Stabilize v0.6.0

Ensure documents are up to date with coedbase, archive useless odl reports, remove old verisons of specs, remove
prototype sh scripts, cleanup and prepare for a stable release.
