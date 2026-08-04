# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Formatter: file-header and directive comments are no longer moved onto the first recipe (jake#29).** `jake --fmt` drained every standalone comment above the first recipe into one block glued to that recipe, so a file header, a comment documenting `@dotenv`/`@import`, and section separators were concatenated and the directive they documented was left bare. The 0.9.0 fix only stopped a *later* recipe from taking an *earlier* recipe's comment; the first recipe still absorbed everything above it, because imports and directives carried no source line to bound the drain against. `Directive` and `ImportDirective` now record their 1-based source line, and the formatter emits comments in source order against those lines: a comment block written directly above an element stays attached to it, a comment followed by a blank line keeps that blank line (so a file header stays at the top and a section separator stays a separator), and a comment block below the last import stays with the import list. Blank lines no longer double up, and the output ends with exactly one newline, so a second `--fmt` pass is a no-op. `jake --fmt` on jake's own `Jakefile` is now a no-op.

## [0.9.7] - 2026-08-02

### Added

- **Line continuation (jake#24) — trailing `\` joins recipe lines.** A physical line ending with an unescaped backslash continues onto the next line: the continuation backslash, the line ending, and the next line's indentation are removed, and the joined text runs as a single shell invocation. Odd runs of backslashes continue (an N-backslash run keeps N−1), even runs stay literal, CRLF behaves like LF, and a backslash before a non-indented line is left alone. `@cd`, `@shell`, `@pre`, `@post`, and `@on_error` stay single-line. The parser groups continued physical lines while retaining the original source spelling, so `jake --fmt` round-trips continuation breaks unchanged; the executor normalizes joins before variable expansion, so `{{var}}` expansions, dry-run output, and the shell all see the same text. The exact rules are documented in `GUIDE.md`, `docs/SYNTAX.md` §10.1, `docs/TUTORIAL.md` (Advanced Pattern 9), and the site syntax reference, with unit + e2e coverage (joined args, shared shell state, dry-run normalization, formatter round-trip).

- **Positional recipe parameters (jake#25).** Bare trailing arguments now bind to declared recipe parameters in declaration order — `jake ask "what is your name"` fills `task ask question:` — while `name=value` still binds by name and takes precedence over positional values. Unfilled declared parameters now expand to an empty string instead of leaking the literal `{{param}}` text into commands. `{{$1}}`/`{{$@}}` positional expansion is unchanged. Documented in `GUIDE.md`, `docs/CLI-ARGS.md`, and the site's positional-arguments reference, with unit tests for positional binding, named-over-positional precedence, and empty expansion.

### Fixed

- **Web UI: stopping a run no longer locks the UI.** The server's cancellation path (and mid-run execution errors) returned without emitting a `task_complete`/`summary`, so after clicking Stop the client waited forever — Run stayed disabled, the spinner and timer ran until reload. Both paths now emit a completion + summary ("Execution cancelled by user").
- **Web UI: request rejections are no longer broadcast to every client.** "A task is already running" / "Invalid command payload" errors were sent to all connected tabs, making an unrelated tab mark its own healthy run as failed. Rejections now go only to the requesting client.
- **Web UI keyboard fixes.** Escape inside the search/parameter inputs now just blurs the field instead of killing the running task; Enter on the Copy/Clear buttons activates them instead of running the selected recipe; clicking the confirm dialog's backdrop no longer drops focus behind the modal; a 0 ms duration now renders instead of showing nothing.

- **Web UI: results from a previous run no longer linger.** Finished-run state used to stick around indefinitely — old ✓/✗ icons stayed next to recipes after starting a different recipe, and the status pill kept reporting "1 completed" forever. Starting a new run now resets every other recipe's result to idle, and after ~15 seconds of inactivity the whole UI (icons, status pill, elapsed timer) drifts back to "Ready". Output history is preserved per recipe.
- **Web UI: a dropped WebSocket connection no longer locks the UI.** If the connection died mid-run, the Run button stayed disabled and the elapsed timer ticked forever, because the completion message that would clear them never arrived. Disconnects now reset local run state (with a "run state unknown" note in the output) while the auto-reconnect keeps retrying. A run started from another connected browser tab is now also reflected in this tab's status pill, timer, and Stop button.
- **Web UI: recipe names containing quotes no longer break the page.** Recipe/group names were interpolated into inline `onclick="…"` handler strings, where an apostrophe (already HTML-entity-decoded by the browser before JS parsing) corrupted the handler. All inline handlers were replaced with delegated event listeners keyed off `data-*` attributes.
- **`just test` (and other justfile recipes) no longer break when the default `zig` is 0.16.** The justfile called `zig` directly, so building/testing Jake via `just` failed on machines where PATH points at a newer Zig than the 0.15.x Jake targets. A `zig` variable now prefers the repo's `scripts/zig` toolchain resolver when present and falls back to `zig` on PATH, matching how Jake's own Jakefile recipes already worked.

### Changed

- **Web UI output pane is now incremental.** Each output line is appended as its own DOM node instead of rebuilding the entire pane's HTML on every message (previously O(n²) for chatty recipes). Auto-scroll only follows the tail when you're already at the bottom — scrolling up to read an error is no longer yanked away — and the buffer is capped at 5,000 lines per recipe.
- **Web UI remembers your state across reloads.** The filter text, collapsed groups, selected recipe, and entered parameter values persist in `localStorage`.
- **Web UI accessibility pass.** The recipe list is a proper `listbox`/`option` tree with `aria-selected`, the output pane is a live `log` region, and the `@confirm` dialog traps keyboard focus (initial focus on Cancel; Escape declines; Enter no longer globally approves).
- **Web UI assets split out of the binary-embedded single file.** `webui.html` (1,360 lines of HTML+CSS+JS) is now `src/webui/index.html`, `style.css`, and `app.js`, each embedded at compile time and served as separate routes — no runtime dependencies added.

### Internal

- **Dead-code sweep (~360 lines removed).** Removed the never-referenced style layer in `color.zig` (13 write/styled helpers, 11 unused `Theme` methods, unused magenta codes), the never-emitted `jakefile_loaded` event and its serializer, unused error sets (`InitError`, `UpgradeError`, `WatchError`), unused types (`WebRecipe`, `InstallResult`), unused functions (`args.printError`, `Executor.printCompletionStatus`, `Context.killCurrentChild`, `Spinner.pause`/`unpause`), stale import aliases, the pre-0.15 fallback branches in `compat.zig`, and unused CSS variables/rules in the web UI. `Executor`'s private `stripQuotes` now delegates to `parser.stripQuotes`.

- **`src/` reorganized into pipeline-stage folders.** The flat 30-file directory is now grouped as `cli/` (args, completions, suggest, init, upgrade, templates), `frontend/` (lexer, parser, import, loaders, external), `runtime/` (executor, parallel, cache, hooks, conditions, functions, env, context, watch), `output/` (color, formatter, progress, prompt, event_emitter), `webui/`, and `util/` (glob, system, tracy); `main.zig`, `jake.zig`, and `compat.zig` stay at the root. Moves were done with `git mv` so blame history follows. Docs (`CLAUDE.md`, `AGENTS.md`, `docs/`) were updated to match.

- **`--filter` now hints when a glob was eaten by the shell.** `jake --filter opencode*` could silently print `0 recipes` when the shell expanded the unquoted glob before jake ran (e.g. `opencode*` → a matching `opencode-sema/` directory, so jake filtered on `opencode-sema` and matched nothing). When `--filter` matches no recipes **and** the pattern arrives without any glob metacharacters (`*`, `?`, `[`) — the fingerprint of an already-expanded argument — jake now prints a reminder to quote the pattern. The hint appears only on the human-readable `--list` path; `--short`, `--summary`, and `--json` stay clean for scripting. A new "`--filter` Matches Nothing" troubleshooting entry documents the gotcha.

- **CI checks were synced with the intentional file-recipe hiding.** Since 0.9.4, `--groups`/`--json`/`--summary` intentionally hide `file` recipes (they're build artifacts, not commands), but the docs-contract and completion tests still asserted the old listing behavior, so CI's "Docs Contract" and "Completion Tests" jobs failed on every push. Both test suites now assert file recipes stay hidden, and the tree-sitter corpus tests were updated from the removed `@only-os` attribute to the current `@platform` spelling.

## [0.9.6] - 2026-07-07

### Fixed

- **Global flags now work in any position — `jake pkg.dev --show` shows the recipe instead of running it.** The CLI parser had two divergent code paths (one before the recipe name, a weaker one after it). Any value-taking flag placed after the recipe — `--show`/`-s`, `-f`, `--group`, `--filter`, `--type`, `--port` — was silently swallowed as a recipe argument, so `jake pkg.dev --show` _ran_ `pkg.dev` rather than showing it. The parser was rewritten as a single clap-style pass: jake's flags are recognized **anywhere** on the line, before or after the recipe, interspersed with recipe args. The first bare token is the recipe; later bare tokens are its arguments; `--` forwards everything after it to the recipe literally; unknown flags after the recipe are forwarded to the recipe (unknown flags before it remain an error with a suggestion). An allocation-failure path that could silently drop positional arguments was also fixed. See the new `docs/CLI-ARGS.md` for the full grammar.
- **Parse errors now name the offending argument, not the first one.** `jake --list --frobnicate` reported _"Unknown option: --list"_; it now correctly names `--frobnicate`. The same fix applies to invalid-value and missing-value errors that follow the recipe name.
- **A memory leak on the constraint-error path was fixed** — a mutual-exclusivity or requires-together violation with non-empty positional arguments (e.g. `jake --list deploy prod --show`) leaked the positional buffer.

### Changed

- **`-s`/`--show` is now recipe-derived.** `jake --show RECIPE`, `jake -s RECIPE`, and `jake RECIPE --show` are all equivalent; an explicit value still works via `--show=RECIPE`. `jake --show` with no recipe now reports a clear error instead of demanding a value inline. Invalid values for choice-restricted flags (`--type`, `--external`, `--completions`) now report `InvalidChoice` (listing the valid options) rather than a generic `InvalidValue`.
- **A value-less flag given an inline value is now an error.** `--yes=false` and `--verbose=3` previously ignored the `=value` silently (so `--yes=false` meant `yes=true`); they now report _"Option … does not take a value"_. Use `--no-yes` / `--no-verbose` to negate and `-vvv` for verbosity levels.
- **Invalid-value errors now list the valid options and expected type.** `jake --completions elvish` now prints _"Must be one of: bash, zsh, fish"_, and `jake --jobs 0` prints _"Expected: a positive integer"_, instead of a bare message.

## [0.9.5] - 2026-07-07

### Fixed

- **Reserved keywords are now accepted as task parameter names (jake#23).** Param names that collide with a directive keyword (`file`, `cd`, `needs`, `confirm`, `import`, `group`, `desc`, `task`, …) aborted parsing with `expected ':' after task name (… found 'kw_file')`, breaking common headers like `task trace file="traces.jsonl":`. A parameter name is an unambiguous position where a directive keyword can never appear, so the task-header parser now treats keywords as ordinary identifiers there (the same soft-keyword handling already used for recipe and dependency names). Their `{{…}}` interpolation works unchanged.
- **`jake install` (and the other build recipes) no longer break when the default `zig` is 0.16.** Jake targets Zig 0.15.x, but Zig 0.16 renamed large parts of `std` (the process-args and Writer/Reader I/O layers), so a 0.16 `zig` on `PATH` failed the build. The project's own recipes now invoke a small resolver shim (`scripts/zig`) that transparently selects a compatible 0.15.x toolchain — honoring a `ZIG=…` override, then a compatible `zig`/`zig-0.15` on `PATH`, then a Homebrew `zig@0.15` keg — and prints an actionable install hint if none is found. This only affects building Jake itself; it does not change Jakefile behavior. (Building Jake on Zig 0.16 is not yet supported; that requires a full source port.)

## [0.9.4] - 2026-07-07

### Fixed

- **Directives now work inside `file` and simple recipes (jake#21).** `@`-directives (`@needs`, `@cache`, `@if`, `@each`, `@ignore`, …) inside a `file` recipe body were passed to the shell verbatim, so `@needs echo` became a literal `needs` command and failed with `command not found`. Only `task` recipes parsed the full directive set; the command-body parser is now shared across all three recipe kinds, so directives behave identically everywhere. A plain `@cmd` (e.g. `@echo`) still means "silent command".
- **Makefile parser no longer invents targets from recipe command lines (jake#22).** Tab-indented recipe body/continuation lines that happen to contain a colon (e.g. `curl -fsSL https://…` or `cd web && npm run og:check`) were mis-parsed as target definitions, producing bogus external recipes like `make.curl`, `make.https`, `make.cd`, and `make.@echo`. Indented lines are now correctly skipped — only column-0 target definitions are parsed.
- **Justfile recipe names no longer include parameters.** `just --list` prints parameters and defaults inline (`dev path="."`, `web port="3333"`), and jake was capturing the whole line up to the `#` as the recipe name — producing unusable names like `just.dev path="."` for the majority of real justfiles (56% of a 124-file sample). Only the leading token is now taken as the name; submodule markers (`mymod ...`) are skipped. The `just --list` output parser was extracted into a unit-tested helper (`parseJustListOutput`).
- **Direct Justfile parser rewritten to match `just`'s listing semantics.** The fallback used when `just` is not installed (or `just --list` fails) was a rough approximation that leaked parameters, dropped `@`-quiet recipes, showed `[private]` recipes, and mis-attributed descriptions. It now faithfully reproduces `just`'s visible recipe set: strips `@` quiet markers, hides `[private]` and `_`-prefixed recipes, reads descriptions from both leading `#` comments and `[doc('…')]`, captures `[group('…')]`, dedups platform-guarded variants (`[unix]`/`[windows]`), respects blank-line comment/attribute association, and excludes non-recipes (`:=` assignments, `set`, `mod`, `import`, `alias`). Attribute parsing respects quoted payloads so a keyword inside `[doc('… private …')]` isn't misread. Validated against a 124-file real-world corpus — the direct parser now produces an exact match with `just`'s own output on every file (zero malformed names, zero spurious or missing recipes).

### Changed

- **`file` recipes are hidden from `jake --list` / `-l` by default.** File targets are build artifacts rather than user-facing commands, so they no longer clutter the default listing (matching how private `_`/`@hidden` recipes are treated). Reveal them with `jake --list --all` (shown under `(hidden)`) or `jake --type file`. They remain runnable by name and usable as dependencies. `--short`, `--summary`, `--groups`, and `--json` listings follow the same default.

## [0.9.3] - 2026-07-04

### Added

- **Import-site `rooted` modifier.** An importer can now force a module to be rooted from its own side, without editing the imported file: `@import "vendored/tool/Jakefile" as tool rooted` (the `rooted` keyword is also valid without `as`, e.g. `@import "sub/Jakefile" rooted`). This is the primary internal-workspace case — vendored sub-projects or git submodules whose `Jakefile`s you don't own. Rooting is **monotonic / additive-only**: a module is rooted if _either_ its file declares `@rooted` _or_ an import directive says `rooted` (both present is fine, no conflict); there is no `unrooted`, so a `@rooted` module can never be forced back to root-relative. Adds parser/import support, formatter round-trip, and unit + e2e coverage (a non-`@rooted` module forced rooted at the import site resolves its relative paths under the module dir).
- **Editor grammars now cover `@rooted` (0.9.2 catch-up).** The `@rooted` directive shipped in 0.9.2 with prose docs but was never added to the syntax-highlighting grammars. All editor grammars (TextMate/VS Code, Tree-sitter, Vim, Prism, highlight.js, and the derived Sublime/Shiki/IntelliJ/Zed/Helix/Lapce targets) now highlight both the `@rooted` directive and the `rooted` import modifier.

## [0.9.2] - 2026-07-04

### Added

- **`@rooted` directive — module-level base-dir resolution for imported Jakefiles.** A file can declare `@rooted` at the top to opt into resolving _its own_ recipes' relative paths (`@cd`, `file` targets, relative paths in command bodies) against _its own_ directory when imported from a parent. This unblocks composing independent sub-project Jakefiles — a `workspace` meta-repo whose sub-directories (or git submodules) are self-contained projects, each with its own `Jakefile`, imported into one root Jakefile. Default behaviour is unchanged and backward-compatible: without `@rooted`, imported recipes still resolve relative to the importer's directory (so `@import "jake/rust.jake"` keeps referencing repo-root paths like `crates/...`). Running a `@rooted` file directly as the root Jakefile is a no-op. Adds parser/import/executor support with unit + e2e coverage (rooted `@cd`/relative-path resolution, rooted `file`-target existence/mtime under the module dir, and a non-rooted regression check).

## [0.9.1] - 2026-07-04

### Changed

- **`@require` is now recipe-scoped.** A `@require FOO` placed before a recipe applies to _that_ recipe (validated before its dependencies run, so a missing var fails fast without a wasted build), instead of being validated globally for every execution. This matches how `@needs`/`@group`/`@desc` attach to the following recipe. Previously a single publish recipe's `@require VSCE_PAT` made _every_ invocation — even `jake build` — demand that var. A `@require` with no following recipe is still treated as global. Listing/show remain unaffected (from 0.9.0). Adds unit + e2e coverage (recipe-scoping, global fallback, fail-fast-before-deps) and formatter round-trip support.

## [0.9.0] - 2026-07-04

### Changed

- **BREAKING — directive aliases resolved.** Duplicate directive spellings were removed in favour of one canonical name each:
  - `@description` → use **`@desc`**
  - `@only` and `@only-os` → use **`@platform`**

  Jakefiles using a removed spelling now fail to parse with `unknown directive`. Lexer, parser, formatter, docs, examples, and every editor grammar were updated together.

- **BREAKING — top-level targeted `@on_error` removed.** Recipe-specific error handlers must use body-level `@on_error` inside the recipe (mirroring `@pre`/`@post`); top-level `@on_error` is now always the global handler. This removes a brittle parsing heuristic (was POTENTIAL_ISSUES #3). `@before <recipe>` / `@after <recipe>` remain the cross-cutting form for attaching hooks to recipes defined elsewhere.

### Internal

- **Parser**: extracted 13 per-directive handlers from the 375-line `parseDirective` chain and unified recipe finalization into a single `finalizeRecipe` helper shared by the task, file, and simple recipe parsers. No behaviour change.

### Fixed

- **`@require`**: no longer blocks read-only invocations. `jake -l` and `jake -s` validated global `@require` env vars even though they execute nothing, so a Jakefile that declared publish secrets (e.g. `@require VSCE_PAT`) couldn't even be listed without those vars set — breaking discovery, `--json`, and completions. Validation now runs only on the execution path (still enforced for real runs, still skipped in dry-run, still handled by watch mode). Adds an e2e assertion.
- **Formatter**: leading comments stay anchored to the recipe they document. Previously `jake --fmt` drained every standalone comment onto the first recipe (so a comment above `task rollback` was hoisted above `task deploy`, and later recipes lost their comment) whenever recipes carried `@group`/`@desc` directives. The per-recipe comment pass is now bounded by source line (`comment.line < recipe.loc.line`), with a trailing-comment pass so comments after the last recipe aren't dropped. Adds a regression test.
- **Imports**: a failed `@import` now names the offending file — `Import failed: Imported file not found: "jake/x.jake"` instead of the pathless `Imported file not found`. The failing import path (as written in the directive) is captured during resolution and included for not-found, circular, and parse failures. Adds an e2e assertion.
- **Incremental caching**: `file` recipes and the `@cache` directive now actually skip when inputs are unchanged. Two defects made caching a no-op in the normal CLI path: (1) `Executor.initWithIndexAndContext` copied the runtime cache **by value**, so cache writes during execution never reached the instance `RuntimeContext.deinit` persists — `.jake/cache` was always written empty; the executor now shares the cache by pointer (like `environment`/`hook_runner`). (2) The file-target success path recorded only the _output_, never the _dependencies_, so `checkFileTarget`'s `isStale(dep)` always returned true and targets rebuilt every run; dependencies are now recorded too (sequential and parallel paths). Added an e2e regression test (`test-files`) that runs a file target across three process invocations and asserts build → skip → rebuild-on-change. Unit tests missed this because they exercise only the resource-owning executor path, not the shared `RuntimeContext` path the CLI uses.
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
