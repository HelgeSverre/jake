# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **`@require`**: no longer blocks read-only invocations. `jake -l` and `jake -s` validated global `@require` env vars even though they execute nothing, so a Jakefile that declared publish secrets (e.g. `@require VSCE_PAT`) couldn't even be listed without those vars set — breaking discovery, `--json`, and completions. Validation now runs only on the execution path (still enforced for real runs, still skipped in dry-run, still handled by watch mode). Adds an e2e assertion.
- **Formatter**: leading comments stay anchored to the recipe they document. Previously `jake --fmt` drained every standalone comment onto the first recipe (so a comment above `task rollback` was hoisted above `task deploy`, and later recipes lost their comment) whenever recipes carried `@group`/`@desc` directives. The per-recipe comment pass is now bounded by source line (`comment.line < recipe.loc.line`), with a trailing-comment pass so comments after the last recipe aren't dropped. Adds a regression test.
- **Imports**: a failed `@import` now names the offending file — `Import failed: Imported file not found: "jake/x.jake"` instead of the pathless `Imported file not found`. The failing import path (as written in the directive) is captured during resolution and included for not-found, circular, and parse failures. Adds an e2e assertion.
- **Incremental caching**: `file` recipes and the `@cache` directive now actually skip when inputs are unchanged. Two defects made caching a no-op in the normal CLI path: (1) `Executor.initWithIndexAndContext` copied the runtime cache **by value**, so cache writes during execution never reached the instance `RuntimeContext.deinit` persists — `.jake/cache` was always written empty; the executor now shares the cache by pointer (like `environment`/`hook_runner`). (2) The file-target success path recorded only the *output*, never the *dependencies*, so `checkFileTarget`'s `isStale(dep)` always returned true and targets rebuilt every run; dependencies are now recorded too (sequential and parallel paths). Added an e2e regression test (`test-files`) that runs a file target across three process invocations and asserts build → skip → rebuild-on-change. Unit tests missed this because they exercise only the resource-owning executor path, not the shared `RuntimeContext` path the CLI uses.
- **Parser**: blank lines inside a recipe body no longer terminate the recipe. Previously `task t:` with `\n    cmd1\n\n    cmd2` failed to parse — the second indented line was treated as an unexpected top-level token. The body now continues across blank-line separators in `task`, `file`, and simple recipe forms.
- **WebUI**: output and command-preview panels preserve indentation. `tree`-style output, ASCII tables, and any leading spaces in commands now render with `white-space: pre-wrap` instead of collapsing.

## [0.8.1] - 2026-05-04

Windows fix-up release. Brings Windows CI from fully red to fully green and unblocks the build/parse pipeline on Windows checkouts.

### Fixed

- **Lexer**: accept CRLF line endings so Windows checkouts of Jakefiles parse correctly (previously a bare `\r` on a blank line emitted an invalid token)
- **Parser**: strip trailing `\r` from captured directive/command bodies so values like `@needs fake-tool` aren't matched as `fake-tool\r` on CRLF sources
- **Path lookup on Windows**: `commandExists` no longer panics on `OBJECT_NAME_INVALID` from `accessAbsolute` — uses `GetFileAttributesW` directly
- **Hooks**: `@pre`, `@post`, and `@on_error` execution now uses the platform-default shell (`cmd.exe /C` on Windows, `/bin/sh -c` elsewhere), fixing hooks on Windows
- **Recipe execution**: command spawning falls back to the platform-default shell when no `@shell` directive is set, fixing recipe execution on Windows where `/bin/sh` is unavailable
- **Conditions**: `exists("")` now returns false on all platforms (was returning true on Windows because `cwd().access("")` treats empty as the current directory)
- **Version**: `--version` stays semver-shaped on shallow checkouts that lack tags (e.g. CI with `fetch-depth: 1`); falls back to `0.0.0-dev-{hash}` instead of a bare commit SHA

### Internal

- Memory Check CI workflow now uses Zig 0.15.2 (was stuck on 0.14.0 and failing to compile current source)
- Skip Windows-specific PATHEXT test on non-Windows hosts so the Linux test job stays green
- Switch formatter and upgrade verifyChecksum tests from hardcoded `/tmp/...` paths to `std.testing.tmpDir` so they run on Windows
- Normalize path separators when comparing watch patterns in tests (Windows stores `\`, POSIX stores `/`)
- Sleep 20ms before rewriting the file in `cache detects content change` test so mtime moves forward (Windows mtime resolution can collapse fast consecutive writes)
- Skip the parallel `@confirm` parity test on Windows; the test asserts POSIX shell behavior that doesn't survive `cmd.exe`'s `echo` trailing-space quirk
- Rename the `Invoke-Jake -Args` parameter in the Windows smoke test wrapper to avoid PowerShell's `$Args` automatic-variable shadowing (the wrapper was silently passing zero args)

## [0.8.0] - 2026-03-12

### Documentation

- fix website examples to place `@description` before recipe definitions, matching actual Jake parsing behavior
- fix the open-source release example to use supported conditions and explain tag-derived release versioning
- clarify website docs for directive placement and completion Jakefile discovery behavior

### Added

- **Verbose Debugging**
  - Added verbose logging for variable expansion results and cache dependency invalidation reasons during recipe execution

- **Help & Completions**
  - Show `--[no-]` prefix for negatable flags in `--help` output (git-style), with `show_negatable` opt-out per flag
  - Shell completions now include `--no-X` variants for negatable flags (`--no-external`, `--no-verbose`, `--no-yes`)
  - Shell completions now include flag aliases (e.g., `--dryrun` for `--dry-run`)
  - Shell completions now include `--external` value choices (`make`, `just`)
  - Shell completions now include dynamic group completion for `--group` and type choices for `--type`
  - Shell completions now skip hidden and deprecated flags

- **Listing Output**
  - Added `--json` for machine-readable listing output
  - Added `--group`, `--filter`, `--type`, and `--groups` for recipe discovery and filtering
  - Added E2E coverage for JSON listing output and the new listing/filter flags

- **API Documentation**
  - Added `zig build docs` step to generate browsable HTML documentation via Zig's autodoc
  - Added `jake docs` recipe to build and serve docs locally (requires `npx serve`)
  - Added `//!` module doc comments to all core source files
  - Added `///` doc comments to key public types (Recipe, Jakefile, Parser, Lexer, Token, Executor, etc.)
  - Renamed `src/root.zig` → `src/jake.zig` so autodoc displays "jake" instead of "root"

- **Parallel Execution Regression Coverage**
  - Added focused tests to verify that parallel execution matches sequential behavior for `@confirm`, `@cd`, `@shell`, hooks, `@cache`, timeouts, and external recipe delegation
  - Added regression coverage for file-target producer resolution in the parallel dependency graph

- **External Integration Coverage**
  - Added unit and E2E coverage for external recipe discovery via `-f <Jakefile>` and delegated positional-argument forwarding

- **Web UI Coverage**
  - Added focused Web UI regression tests for command parsing and execution-context construction
  - Added browser-level WebSocket E2E coverage for `@confirm`, dependency execution, streamed output, and stop/cancel behavior

- **Parser and Initialization Regression Coverage**
  - Added focused tests for source-context parse diagnostics, malformed directives/imports, runtime dotenv failure propagation, and formatter round-trip stability with stricter parsing

- **Completion and CI Coverage**
  - Added CI coverage for the shell completion harness on Ubuntu with bash, zsh, and fish installed
  - Added focused argument-parser regression tests for invalid `--completions` and `--external` choice values
  - Added a Windows CLI smoke harness in CI for environment lookup, shell auto-detection, and `@needs` command discovery

### Changed

- **Args Module Refactor**
  - Moved `quickScan`, `parse`, and help/error formatting from module-level functions into the `Args` struct namespace
  - Added comptime validation for duplicate flags, alias conflicts, and unknown categories
  - Added `show_negatable` field to `Flag` for controlling `--[no-]` display in help output

- **Parallel Execution Architecture**
  - `ParallelExecutor` now schedules work but runs recipes through the shared executor recipe runner instead of maintaining a separate command interpreter
  - Parallel execution now preserves sequential recipe semantics for hooks, `@cd`, `@shell`, `@confirm`, timeout handling, external recipe delegation, and command-level `@cache`
  - Removed the duplicate directive/shell execution path from `src/parallel.zig` to reduce future semantic drift
  - Watch mode now reloads through the shared Jakefile loading pipeline so imports, external recipes, runtime configuration, and execution flags stay aligned with normal CLI execution

- **Web UI Execution Parity**
  - Web-triggered runs now inherit the CLI process' execution context for verbosity and parallel job settings instead of constructing a separate partial context
  - Web UI command handling now parses browser-supplied recipe parameters and forwards them as normal `name=value` arguments
  - Web UI execution now routes task, command, output, and summary updates through the shared event-emitter path used by the CLI executor

- **Parser and Runtime Error Handling**
  - Jakefile parse failures now print source-context diagnostics with the failing line and caret location instead of only returning a generic parse error
  - Parser handling for unknown directives and malformed top-level declarations now fails explicitly instead of silently skipping invalid input
  - Runtime and executor initialization now propagate dotenv, export, hook, and cache setup failures instead of continuing with partially configured state

- **Repository Build and CI Consistency**
  - CI now uses Zig `0.15.2` consistently across test, lint, E2E, and completion coverage jobs
  - Core runtime helpers now share one cross-platform abstraction for environment lookup, shell detection, home-directory resolution, and command discovery
  - Jake's own modular `jake/*.jake` task files were normalized to remain parseable under the stricter parser contract used by the CLI and CI

- **Documentation Cleanup**
  - Archived outdated design and review docs under `docs/archived/`
  - Expanded `docs/CODE-REVIEW-CODEX.md` with a continuation handoff and current implementation status
  - Reconciled active CLI docs, README snippets, install docs, and guide examples with the current binary and flag set
  - Added a docs-contract release gate that validates representative documented commands against fixture Jakefiles
  - Expanded the docs-contract gate to cover JSON listing output and the new recipe-filtering flags

### Fixed

- **Parallel Execution**
  - Fixed command-level `@needs` enforcement in parallel mode
  - Fixed file-target dependency graph construction so file recipes also depend on recipes that produce their file dependencies
  - Fixed a parallel cache synchronization bug where worker cache updates could be overwritten by the parent executor when the run finished
  - Fixed scheduler ready-queue OOM handling so dependency scheduling fails explicitly instead of silently dropping work

- **Caching and Glob Handling**
  - Fixed `@cache` glob refresh so glob patterns update the cache entries for matched files instead of treating the glob itself as a literal path
  - Fixed relative glob expansion from the current working directory on macOS/Darwin
  - Fixed read-only listing and `--show` flows to stop saving cache on teardown, avoiding spurious cache-permission warnings for non-mutating commands

- **Functions and Environment Detection**
  - Fixed `shell_config()` to fall back to `.profile` for unknown Unix shells instead of leaving the template literal unexpanded

- **Watch Mode**
  - Fixed `--watch` to reparse Jakefile/import/external-build changes instead of rerunning a stale AST
  - Fixed watch-mode execution to preserve the full CLI/runtime context, including parallel job settings and required-environment validation
  - Fixed recursive dependency collection in watch mode so cycles no longer recurse indefinitely during pattern discovery
  - Fixed deleted watched files to trigger exactly one change event and retrigger again when the file reappears
  - Added watch-mode regression coverage for automatic config watching, reload-on-edit, dependency cycles, and deleted-file handling

- **External Build System Integration**
  - Fixed external Makefile/Justfile loading to resolve relative to the selected Jakefile directory instead of the process cwd
  - Fixed delegated external execution to run from the external file's directory and forward CLI positional arguments to `make`/`just`
  - Fixed empty external parse results to remain allocator-owned so cleanup does not free static empty slices

- **Web UI**
  - Fixed Web UI execution to validate `@require` directives before running recipes, matching the normal CLI path
  - Fixed Web UI `@confirm` handling to prompt in the browser instead of auto-approving runs
  - Fixed Web UI stop/cancel handling so long-running captured commands terminate cleanly and report cancellation back over WebSocket
  - Fixed leaked WebSocket frame-handler thread ownership by detaching background connection threads explicitly
  - Fixed stale execution-thread ownership so completed Web UI runs are joined cleanly before the next run
  - Fixed automatic browser launch to skip headless/test contexts when `CI` or `JAKE_NO_BROWSER` is set
  - Styled the recipe-list scrollbar to better match the Web UI theme
  - Fixed browser-triggered runs to disable child-process stdin so terminal-only prompts fail instead of hanging indefinitely
  - Fixed process-group handling so stop/cancel signals reliably terminate child processes spawned beneath the active shell command
  - Fixed the Web UI E2E harness to use a per-run high port instead of relying on one fixed port for every test run

- **Tooling and Dependencies**
  - Updated `editors/tree-sitter-jake` lockfile dependencies to resolve dependabot-reported security alerts

- **Formatter**
  - Fixed formatter round-trips to keep variable values parseable by quoting canonicalized values and to avoid duplicating directive keywords like `@if`

- **Init Command**
  - Fixed `jake init --template=node|go|rust|python|zig` being rejected despite templates being fully implemented
  - Fixed `jake init --yes` / `-y` flag not being parsed by the CLI

- **Completions**
  - Fixed `--completions` and `--external` optional value parsing to reject invalid explicit values instead of silently falling back to auto-detection/default behavior
  - Fixed zsh completion installation fallback to treat `PermissionDenied` the same as `AccessDenied`, restoring fallback from system/Homebrew paths to the user completion directory
  - Fixed shell auto-detection to recognize Windows-style `SHELL` paths for bash, zsh, and fish completion generation

- **Windows Runtime Behavior**
  - Fixed `env(...)` and related system environment lookups to work on Windows instead of always reading as unset
  - Fixed command discovery and `@needs` on Windows to honor `;`-separated `PATH` entries and `PATHEXT`, including explicit relative command paths
  - Fixed `home()`, `local_bin()`, and `shell_config()` so they resolve meaningful paths on Windows instead of failing outright

### CI/CD

- Bumped actions/upload-artifact from 6 to 7
- Bumped actions/download-artifact from 7 to 8

## [0.7.0] - 2026-01-09

### Added

- **Web UI** - Interactive browser-based task runner (`jake --web`)
  - WebSocket streaming for real-time command output
  - Recipe listing with commands, dependencies, and metadata
  - Console tee for simultaneous terminal and browser output
  - Semantic CSS design tokens for consistent theming

- **External Build System Integration** - Parse and run Makefile/Justfile targets
  - Automatic detection of Makefile and Justfile in project directory
  - `--external` flag to show only external recipes (optionally filter by `make` or `just`)
  - `--no-external` to hide external recipes from listings
  - Recipes prefixed as `make.*` and `just.*` for clear distinction
  - Execute external recipes via delegation to `make` or `just` commands

- **Editor Plugin Improvements**
  - Tree-sitter grammar expanded to 93 tests with improved coverage
  - NeoVim-flavored query outputs for better integration
  - Sync automation for all editor plugins (Zed, VS Code, Vim, IntelliJ)
  - Added missing directives and functions to all syntax highlighters

- **Claude Code Integration**
  - `/release` command for automated release workflow
  - Structured command format with YAML frontmatter

### Changed

- `Recipe.isPrivate()` helper consolidates hidden/private recipe detection logic
- Improved completions test harness with better reporting, cleanup, and statistics
- WebUI skips private recipes (matches `--list` behavior)

### Fixed

- `ColoredText.format` compatibility with both Zig 0.14 and 0.15
- Colorize make/just recipes consistently with Jake recipes in listings
- Site styling fixes (divider colors, mobile-responsive navbar)

## [0.6.0] - 2026-01-05

### Added

- **Args Library Overhaul** - Comprehensive CLI argument parsing improvements
  - **Environment variable fallback** - Flags can specify `.env` for fallback values
    - JAKEFILE, JAKE_JOBS, JAKE_VERBOSE, JAKE_YES, JAKE_DRY_RUN supported
    - Help output shows `[env: VARNAME]` hints
  - **Flag aliases** - Alternative long flag names (e.g., `--dryrun` for `--dry-run`)
  - **Short flag value attachment** - `-fcustom.jake`, `-j4`, `-sbuild` syntax
  - **Better error messages** - Rich context with expected type and usage hints
  - **Enum/choice restrictions** - `.choices` field for value validation
  - **Compile-time validation** - Catch duplicate flags, invalid categories at compile time
  - **Mutually exclusive groups** - `--list` and `--show` cannot be used together
  - **Required-together groups** - `--check` and `--dump` require `--fmt`
  - **Value validators** - Built-in validators for positive integers, file paths, shell names
  - **Streaming parser** - `quickScan()` for fast `--help`/`--version` detection

### Changed

- Flag categories now group help output (General, Output, Execution, File, Shell)
- Countable flags (`-vvv`) now set `verbose_level`
- Negatable flags (`--no-verbose`) explicitly disable options

## [0.5.0] - 2026-01-01

### Added

- **CLI v4 Output Design**
  - Complete redesign of CLI output with brand colors
  - Consistent visual styling across all commands
  - Improved completion status with timing information

- **Jakefile Formatter**
  - `jake --fmt` to format Jakefiles with consistent style
  - `jake --fmt --check` for CI validation without modifying files
  - `jake --fmt --dump` to output formatted AST
  - Comment preservation during formatting

- **Self-Update Command**
  - `jake upgrade` to update jake to the latest version
  - Automatic version checking and installation

- **@timeout Directive**
  - Set maximum execution time for recipes
  - Automatic process termination when timeout exceeded
  - Extended fuzz testing for timeout handling

- **Color Module**
  - New `color.zig` module with ANSI color codes
  - `NO_COLOR` environment variable support
  - `ColoredText` helper for styled output
  - Themed output with brand colors

- **Zed Editor Extension**
  - Complete Zed extension with syntax highlighting
  - Custom themes and icons for Jakefiles

- **CLI Improvements**
  - `--all` flag to show all recipes including private ones
  - Double-dash separator (`--`) for passing arguments to recipes
  - Parent directory traversal to find Jakefile
  - `jake init` command to create new Jakefile
  - "Did you mean?" suggestions for unknown flags

- **Jake Modules**
  - Split Jakefile into reusable modules in `jake/` directory
  - Better organization for build, release, perf, web, and editor tasks

### Fixed

- Color.zig `Theme.init()` now correctly initializes color detection
- ColoredText format method updated for Zig 0.15 compatibility

### Changed

- Refactored executor, parallel, hooks, and watch modules to use Color module
- Simplified distribution strategy, removed `packaging/` directory
- Restructured syntax highlighters and consolidated demos

## [0.4.0] - 2025-12-30

### Added

- **@launch Directive**
  - Open files and URLs from Jakefiles with `@launch`
  - Built-in `launch()` function for use in commands
  - Cross-platform support using `open` (macOS), `xdg-open` (Linux), `start` (Windows)

- **Platform Detection Conditions**
  - `os()` condition: check `macos`, `linux`, `windows`
  - `arch()` condition: check `x86_64`, `aarch64`
  - Enables platform-specific recipe commands

- **CLI Improvements**
  - Global flags now work after recipe name (e.g., `jake build -v`)
  - More flexible argument ordering

- **Jake Modules**
  - Reusable Jakefile modules in `jake/` directory
  - `build.jake` - Core build, test, and install tasks
  - `release.jake` - Cross-platform release builds
  - `perf.jake` - Performance and profiling tasks
  - `web.jake` - Website-related tasks
  - `editors.jake` - Editor integration setup

- **Watch Mode Improvements**
  - Better pattern parsing with feedback
  - Improved watch mode testing fixtures

### Fixed

- `dirname("/")` edge case now returns "/" correctly
- Editor syntax highlighters updated for `launch()` function
- GitHub URLs updated to HelgeSverre organization
- Docker completions test uses Zig 0.15.2

### Changed

- Removed legacy corpus, lib modules, and fuzz tests
- Improved hook execution and error handling
- Refactored functions, glob, and lexer modules

## [0.3.0] - 2025-12-30

### Added

- **Shell Completions**
  - Generate shell completions for bash, zsh, and fish (`jake --completions <shell>`)
  - Auto-install/uninstall commands (`jake --completions --install`)
  - Smart zsh environment detection (Oh-My-Zsh, Homebrew, vanilla)
  - Machine-readable recipe list (`jake --summary`)

- **CLI Improvements**
  - `jake --list --short` for pipeable one-per-line recipe names
  - `jake --show <recipe>` to display recipe details (dependencies, commands, metadata)
  - Typo suggestions using Levenshtein distance ("Did you mean: build?")

- **Recipe-Level @needs Directive**
  - Check command/binary requirements before recipe execution
  - `@needs git npm docker` validates tools exist in PATH

- **Built-in Functions**
  - System path functions: `home()`, `local_bin()`, `shell_config()`
  - String functions: `uppercase()`, `lowercase()`, `trim()`
  - Path functions: `dirname()`, `basename()`, `extension()`, `without_extension()`, `without_extensions()`

- **Runtime Conditions**
  - `@if`, `@elif`, `@else`, `@end` with condition functions
  - Condition functions: `env()`, `exists()`, `eq()`, `neq()`, `os()`, `arch()`

- **Editor Support**
  - Vim syntax highlighting plugin (`editors/vim-jake/`)
  - IntelliJ Platform plugin with dynamic TextMate bundle (`editors/intellij-jake/`)

- **Recipe Metadata**
  - Location and origin tracking for recipes
  - Recipe source file tracking for imports

- **Documentation Website**
  - New documentation site built with Astro Starlight
  - Feature deep-dives and CLI branding guide

### Fixed

- Zsh completion syntax and array handling
- Private recipes with dot prefix now filtered from listings
- Zig 0.14/0.15 compatibility layer for CI

### Changed

- Migrated E2E tests to `tests/e2e/` directory
- Updated to ztracy library with new API
- Refactored argument parsing with dedicated args module

### CI/CD

- Bumped actions/upload-artifact from 4 to 6
- Bumped actions/download-artifact from 4 to 7
- Bumped mlugg/setup-zig from 1 to 2
- Bumped softprops/action-gh-release from 1 to 2
- Bumped actions/stale from 9 to 10

## [0.2.0] - 2025-12-28

### Added

- **@quiet Directive** - Suppress command echo for entire recipe
- **@confirm Directive** - Interactive confirmation prompts with `--yes` flag support
- **Environment Validation** - `@require` checks env vars exist before execution
- **Command Dependency Checking** - `@needs` validates commands exist in PATH

### Fixed

- Shell/working_dir assignment in parser
- Windows compatibility for environment variable access
- Zig 0.14-compatible std.io API calls

## [0.1.0] - 2025-12-28

### Added

- **Core Engine**
  - Lexer with tokenization for Jakefile syntax
  - Parser with AST generation and error reporting
  - Executor with dependency resolution and recipe execution
  - File hash cache for incremental builds

- **Task Features**
  - Task recipes with parameters and default values
  - File recipes with glob pattern support (`src/**/*.ts`)
  - Dependency tracking between tasks (`task build: [clean, compile]`)
  - Parallel execution with configurable job count (`-j N`)
  - Watch mode for automatic re-execution (`-w`)

- **Environment & Configuration**
  - `.env` file loading with `@dotenv` directive
  - Environment variable export with `@export`
  - Variable interpolation with `{{variable}}` syntax

- **Modularity**
  - Import system with `@import` directive
  - Namespaced imports with `@import "file.jake" as name`

- **Hooks & Conditionals**
  - Global and per-recipe `@pre` and `@post` hooks
  - Conditional execution with `@if`, `@else`, `@end`

- **CLI**
  - `jake` - Run default task
  - `jake <recipe>` - Run specific recipe
  - `jake -l` / `--list` - List available recipes
  - `jake -n` / `--dry-run` - Show what would run
  - `jake -v` / `--verbose` - Verbose output
  - `jake -f <file>` - Use alternate Jakefile
  - `jake -j N` - Parallel jobs
  - `jake -w` - Watch mode

- **Documentation**
  - Comprehensive user guide
  - Contributing guidelines
  - Example Jakefiles for common patterns

- **CI/CD**
  - GitHub Actions workflows for CI and releases
  - Multi-platform build support (Linux, macOS, Windows)
  - Cross-compilation for x86_64 and aarch64

[0.7.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.7.0
[0.6.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.6.0
[0.5.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.5.0
[0.4.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.4.0
[0.3.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.3.0
[0.2.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.2.0
[0.1.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.1.0
