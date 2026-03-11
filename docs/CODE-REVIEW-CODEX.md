# Codex Code Review Report

Date: 2026-03-10

## Scope

This review covered:

- `TODO.md`
- `CHANGELOG.md`
- recent `git log`
- the core execution pipeline (`main`, parser, executor, parallel execution, watch mode, external integration, cache, conditions, web UI)
- the current test and documentation surface

I also ran `zig build test` in this workspace. Most module tests ran, but the overall command failed in this environment, and the run exposed at least one real semantic issue in parallel `@each` handling.

## Executive Summary

Jake has a good top-level shape: lexer/parser/executor separation is reasonable, the project already has a substantial feature surface, and the codebase shows active work on UX and tooling. The main problem is not lack of features. It is semantic drift.

There are now multiple execution engines with different behavior:

- `Executor` for normal execution
- `ParallelExecutor` for `-j`
- `Watcher` for `--watch`
- `WebUIServer` execution path for `--web`

Those paths no longer preserve the same contract. Today, `-j`, `--watch`, and parts of `--web` are not just alternate frontends for the same behavior. They each change correctness, directive behavior, environment handling, or cancellation semantics.

That architectural split is the highest-risk issue in the repository.

## What Is Strong

- The core pipeline is understandable. `main.zig` -> parser -> executor is a sensible structure.
- `JakefileIndex` and runtime/context separation are useful building blocks.
- The repository has broad ambitions and decent test breadth for a work-in-progress system.
- The codebase already contains many targeted fixes, which is a good sign that problems are being found and addressed quickly.

## Highest-Priority Findings

### 1. Parallel execution is a different runtime, not just a scheduler

Files: `src/executor.zig`, `src/parallel.zig`

Observed problems:

- The sequential path applies recipe-level behavior such as hooks, `@cd`, `@shell`, env/runtime setup, timeout handling, and external recipe delegation.
- The parallel path executes `recipe.commands` directly and maintains its own directive handling.
- `@needs` is skipped in parallel mode.
- `@confirm` is auto-approved in parallel mode.
- `@cache` and `@watch` are skipped in parallel mode.
- `@each` parsing in parallel mode is wrong; it tokenizes the raw line and includes `each` as an item.
- `@if/@elif` logic in parallel mode uses raw directive text differently from the sequential path.
- File-target producer resolution in the sequential path is not mirrored in the parallel DAG builder.
- External Make/Just recipes are delegated only by the sequential executor.

Impact:

- `-j` changes behavior, not only performance.
- Recipes can succeed sequentially and behave differently under parallel execution.
- Several documented directives are unreliable or silently disabled under `-j`.

Recommended fix:

- Collapse execution semantics into one shared per-recipe runner.
- Keep `ParallelExecutor` responsible only for dependency scheduling and worker orchestration.
- Remove directive parsing and shell launching from `src/parallel.zig`.

### 2. Parallel execution has a real shared-state race

Files: `src/parallel.zig`

Observed problems:

- Workers share `self.variables`.
- `@each` mutates that shared map by writing and removing `item`.
- There is no synchronization around variable-map mutation.

Impact:

- This is a real data race.
- Parallel recipes can overwrite each other's loop state or corrupt map internals.

Recommended fix:

- Use per-recipe variable scopes.
- Do not store loop-local state in executor-global mutable structures.

### 3. Watch mode reruns stale configuration and loses CLI/runtime semantics

Files: `src/main.zig`, `src/watch.zig`

Observed problems:

- `main.zig` explicitly watches the Jakefile.
- `Watcher.executeRecipe()` reuses the already parsed `self.jakefile` instead of reloading it from disk.
- The watch executor path recreates an executor with `Executor.init(...)` and only copies a small subset of flags.
- `jobs`, runtime state, and other context are not preserved.

Impact:

- Editing the Jakefile during `--watch` reruns stale commands and dependencies until the process is restarted.
- `jake -w -j4 ...` is not trustworthy even though the docs present it as normal usage.

Recommended fix:

- Reparse and rebuild the index/runtime when the Jakefile or imported files change.
- Reuse the same execution context model as normal execution.

### 4. Watch mode dependency collection is not robust

Files: `src/watch.zig`

Observed problems:

- Recursive dependency collection in `addRecipeDeps()` has no visited set.
- Missing files are ignored during change detection instead of being treated as change events.

Impact:

- Cycles can recurse until stack overflow before the normal executor gets to reject them.
- Deleting a watched file can fail to retrigger the recipe.

Recommended fix:

- Add cycle-safe traversal with a visited set.
- Treat `FileNotFound` for previously tracked files as a change.

### 5. `@cache` glob support is broken after the command runs

Files: `src/executor.zig`, `src/cache.zig`

Observed problems:

- `@cache` parsing accepts glob-like patterns.
- Staleness checks use glob-aware logic.
- After execution, the cache update path calls `cache.update(pattern)` on the literal pattern.
- `cache.update()` opens the path as a concrete file.

Impact:

- Glob-based cache directives do not update correctly.
- The feature is partially implemented and therefore misleading.

Recommended fix:

- Split cache APIs into explicit file-update and glob-refresh operations.
- Do not feed raw glob strings into file-open code.

### 6. `jake init` is documented as more complete than the CLI actually is

Files: `src/main.zig`, `src/init.zig`, `TODO.md`

Observed problems:

- `TODO.md` marks language templates and `--yes` as done.
- The init help text documents `node`, `go`, `rust`, `python`, and `zig` templates.
- The actual CLI parser only accepts `starter` and `blank`.
- `--yes` exists in the init options struct/help text but is not parsed in `main.zig`.

Impact:

- Users are told features exist when the command line rejects them.
- `TODO.md` is overstating delivery status.

Recommended fix:

- Either implement the documented behavior immediately or mark the feature incomplete everywhere until it is real.

### 7. External build integration has correctness gaps

Files: `src/executor.zig`, `src/external.zig`

Observed problems:

- External recipe execution does not pass through positional arguments to `make` or `just`.
- External file detection returns bare filenames, which can resolve relative to the wrong directory when using nested `-f` paths.
- `parseMakefile()` and related paths can return `&.{}` and later that slice is freed through the allocator.

Impact:

- Documented external delegation behavior is incomplete.
- Running Jakefiles outside the process cwd can load the wrong external file or fail unexpectedly.
- There is a real memory-handling hazard around freeing non-allocated empty slices.

Recommended fix:

- Pass `ctx.positional_args` through to the delegated child process.
- Resolve external files relative to the Jakefile directory, not the process cwd.
- Never call `allocator.free()` on static empty slices; return owned empty slices or track ownership explicitly.

### 8. The parser is too forgiving for a build tool

Files: `src/parser.zig`

Observed problems:

- Invalid top-level tokens are skipped.
- Unknown directives can be ignored.
- Invalid `@import` forms can be skipped.
- Bare identifiers not followed by `=` or `:` are dropped.
- `@on_error` uses a token-shape heuristic that misclassifies valid global commands like `@on_error git status`.

Impact:

- Typos become partial parses and confusing runtime behavior instead of actionable errors.
- Hook commands can be attached to the wrong target and truncated.

Recommended fix:

- Convert these silent fallthroughs into real parse errors with location information.
- Replace the `@on_error` heuristic with explicit syntax or a second-stage validation against actual recipe names.

### 9. Cross-platform support is weaker than the docs and changelog imply

Files: `src/conditions.zig`, `src/executor.zig`, `src/hooks.zig`, `src/parallel.zig`

Observed problems:

- `env()` returns `null` on Windows.
- PATH scanning is split on `:`.
- Several paths hard-code `/bin/sh`.
- Path joining uses POSIX assumptions in core execution code.

Impact:

- Conditionals, command lookup, hooks, and shell execution are not reliably cross-platform.
- The repository is over-claiming Windows readiness.

Recommended fix:

- Add one platform abstraction for shell selection, PATH splitting, and environment lookup.
- Remove duplicated POSIX assumptions from the execution modules.

## Medium-Priority Findings

### 10. Memory and error handling are weaker than they should be for Zig

Files: `src/parser.zig`, `src/executor.zig`, `src/external.zig`, `src/args.zig`

Observed problems:

- Parser helper functions allocate local `ArrayListUnmanaged` values without local `errdefer` cleanup on parse failure.
- Core executor initialization swallows errors with `catch {}` while loading variables, hooks, dotenv/export state, and cache data.
- `Args.parse()` silently drops positional arguments on allocation failure.

Impact:

- Some failure modes degrade into partial state instead of explicit failure.
- Parse-error and OOM paths are under-defended.

Recommended fix:

- Add `errdefer` cleanup to local parser accumulators.
- Treat allocator failures as fatal.
- Downgrade only truly optional IO failures to warnings, and surface them clearly.

### 11. Timeout reporting is incorrect for ordinary failures

Files: `src/executor.zig`

Observed problems:

- The timeout flag is used both to stop the watchdog and to report whether a timeout actually occurred.

Impact:

- A normal command failure can be reported as a timeout.

Recommended fix:

- Separate “watchdog stop requested” from “timeout fired”.

### 12. CLI/help behavior is internally inconsistent

Files: `src/main.zig`, `src/args.zig`, `tests/completions_test.sh`

Observed problems:

- The “no Jakefile found” error says it searched `Jakefile`, `jakefile`, and `Jakefile.jake`, but the search code only checks `Jakefile`.
- `args.zig` hardcodes ANSI in help and error output instead of consistently going through the color layer.
- The completions test harness expects invalid shell names to fall back to zsh, while the CLI currently errors for invalid shells.

Impact:

- Error output can mislead users.
- Color behavior is inconsistent.
- The completion test harness is drifting from actual behavior.

Recommended fix:

- Make the search message match reality or expand the search logic.
- Route help/error styling through one color policy.
- Align completion behavior and tests.

### 13. The test suite is broad, but it is not yet protecting the riskiest behavior

Files: `tests/e2e/Jakefile`, `.github/workflows/ci.yml`, module tests in `src/parallel.zig`

Observed problems:

- Parallel tests mostly assert non-failure rather than semantic equivalence.
- The e2e suite does not cover `init`, external integration, formatter flows, web mode, or timeout behavior in a meaningful way.
- CI does not run the shell completion test harness.
- CI uses Zig `0.15.0` in some jobs while repository docs say `0.15.2+`.

Impact:

- The most fragile features can regress without a failing gate.
- Documentation and CI are communicating different compatibility stories.

Recommended fix:

- Add behavior-level tests for parallel/watch/web/external execution.
- Add completion tests to CI.
- Use one minimum Zig version story everywhere.

### 14. Web UI execution still looks brittle

Files: `src/webui.zig`, `src/executor.zig`

Observed problems:

- Execution thread state is mutated from multiple contexts.
- Web UI execution hardcodes `.verbose = false`.
- Cancellation depends on child PID tracking that does not cover all execution paths, including external delegation.

Impact:

- Web UI behavior can diverge from CLI behavior.
- Stop/cancel semantics are incomplete.

Recommended fix:

- Reuse the same execution core as CLI execution.
- Treat Web UI as a transport and presentation layer, not a separate executor.

## Documentation and Release-Discipline Findings

### 15. `TODO.md`, changelog, docs, and runtime behavior are out of sync

Files: `TODO.md`, `CHANGELOG.md`, top-level docs and site docs

Observed problems:

- `TODO.md` marks incomplete `init` work as done.
- `CHANGELOG.md` advertises `jake --webui`, but the CLI flag is `--web`.
- The formatter changelog entry describes `jake --check` and `jake --dump` as if they are standalone, while the current CLI requires `--fmt` with them.
- Some tests and docs still describe behavior that the CLI no longer has.

Impact:

- The repository cannot currently use docs/TODO/changelog as a trustworthy source of truth.

Recommended fix:

- Add a release checklist item that verifies user-facing flags and examples against the built binary.
- Do not mark TODO items done until a test and a docs pass are both merged.

## Likely User-Visible Bugs Present Today

- `jake -j ...` can execute `@each` loops with `item = "each"` in the iteration stream.
- `jake -j ...` can skip `@needs`, auto-approve `@confirm`, and ignore recipe-level behavior such as `@shell`, `@cd`, hooks, timeouts, and external delegation.
- `jake -w ...` can notice Jakefile edits but rerun the old AST.
- `@cache` with globs does not refresh correctly after command execution.
- `jake init --yes` is documented but not accepted.
- `jake init --template=node` and related templates are documented but rejected by the parser.
- External recipes can lose positional arguments and resolve files from the wrong base directory.

## Architectural Assessment

The repository would benefit from one structural change more than any other:

Build a single recipe-execution core and make every frontend call into it.

Recommended target split:

1. `Parser` and `JakefileIndex`
2. `ExecutionPlan` or DAG builder
3. `RecipeRunner`
4. thin frontends:
   - CLI sequential
   - CLI parallel scheduler
   - watch loop
   - web UI transport

The key rule should be:

- scheduling may vary
- presentation may vary
- recipe semantics may not vary

Right now that rule is not being enforced.

## Concrete Action Plan

### Phase 1: Stop semantic drift

- Extract a shared `RecipeRunner` from `Executor` and move directive handling, shell spawning, env expansion, hooks, timeout logic, cancellation, and external delegation into it.
- Make `ParallelExecutor` schedule recipes but call the same shared runner.
- Give each recipe execution its own variable scope and runtime state.
- Temporarily document `-j`, `--watch`, and `--web` as experimental if the refactor will take time.

Exit criteria:

- A recipe behaves the same sequentially, in parallel, in watch mode, and via the web UI.

### Phase 2: Repair watch mode

- Reparse the Jakefile and imports on Jakefile-related changes.
- Preserve the original context instead of reconstructing a partial one.
- Add cycle-safe dependency traversal.
- Treat deleted watched files as change events.

Exit criteria:

- Editing the Jakefile while watching reruns the new behavior without restarting.

### Phase 3: Fix correctness bugs already known

- Fix `@cache` glob updates.
- Fix `@on_error` targeted/global parsing.
- Fix timeout reporting.
- Pass positional args through external delegation.
- Resolve external build files relative to the selected Jakefile.
- Remove invalid free patterns around static empty slices.

Exit criteria:

- The user-visible bugs listed above have direct regression tests.

### Phase 4: Tighten parser and memory discipline

- Replace silent parser fallthrough with explicit diagnostics.
- Add `errdefer` cleanup to parser-local accumulators.
- Replace `catch {}` in core initialization with explicit handling.
- Make OOM in the parallel scheduler fatal instead of silently dropping work.

Exit criteria:

- Parse errors fail loudly and allocator failures do not degrade into partial behavior.

Status update (2026-03-11):

- Completed. Jakefile parse failures now print source-context diagnostics with the failing line and caret location.
- Completed. Parser handling for unknown directives, malformed imports, missing targeted-hook names, missing `@default` targets, and invalid top-level declarations now fails explicitly instead of skipping forward.
- Completed. Parser-local accumulators and owned-slice assembly now use `errdefer` cleanup so allocation failures do not leak partial state.
- Completed. `RuntimeContext.configure(...)` and executor initialization now propagate dotenv/export/hook/cache setup failures instead of silently continuing with partial configuration.
- Completed. Formatter round-trips were tightened to emit parseable canonical variable values and directive lines, with regression tests to keep the stricter parser contract stable.

### Phase 5: Rebuild the test contract

- Add semantic equivalence tests for sequential vs parallel execution.
- Add watch-mode tests for Jakefile edits, dependency cycles, and file deletion.
- Add external integration tests with positional args and nested Jakefile paths.
- Add Windows-specific tests for env lookup, shell selection, and command discovery.
- Run completion tests in CI.
- Align the entire repository on one minimum Zig version.

Exit criteria:

- CI fails when documentation-backed behavior regresses.

### Phase 6: Clean up documentation and release process

- Reconcile `TODO.md`, `CHANGELOG.md`, README, guide docs, and site docs with the built binary.
- Add a release gate that checks flag names and documented examples against the current executable.
- Require every user-facing feature to land with docs and tests before it is marked done.

Exit criteria:

- The docs become a reliable contract again.

## Suggested Order of Work

If only a few items are going to be addressed immediately, the order should be:

1. Unify execution semantics between sequential, parallel, watch, and web paths.
2. Fix the known correctness bugs in `@cache`, external delegation, and `init`.
3. Tighten parser diagnostics and memory/error handling.
4. Expand CI to lock the behavior down.
5. Reconcile docs and changelog after the behavior is real.

## Handoff Update (2026-03-11)

This section captures work completed after the initial review so the next agent can continue from the current state instead of re-auditing the same areas.

### Completed since the initial review

- The parallel execution path now uses the shared per-recipe runner instead of its own directive interpreter.
- `Executor.executeParallel()` now passes the real `Context` into `ParallelExecutor`.
- `ParallelExecutor` now runs each recipe through `Executor.executeRecipeBody()`, so parallel mode inherits sequential behavior for:
  - hooks
  - `@cd`
  - `@shell`
  - `@confirm`
  - timeout handling
  - external Make/Just delegation
  - command-level `@cache`
- The old duplicate interpreter code in `src/parallel.zig` has been removed to reduce future semantic drift.
- Parallel graph construction now includes recipes that produce file dependencies of file targets.
- Parallel command-level `@needs` validation is fixed.
- Parallel `@if/@elif` handling was fixed before the duplicate interpreter was removed.
- The shared mutable `item` variable race in parallel `@each` execution was eliminated as part of the shared-runner refactor.
- Ready-queue enqueue OOM in the parallel scheduler now fails the run instead of silently dropping work.
- `@cache` glob refresh is fixed via a glob-aware cache update path.
- `glob.expandGlob()` was fixed to iterate correctly from the current directory on Darwin.
- Old docs were archived rather than deleted:
  - `docs/archived/CLI_DESIGN.md`
  - `docs/archived/CLI_DESIGN_V4.md`
  - `docs/archived/SYSTEM_REVIEW.md`

### Important bug found and fixed during implementation

- Parallel cache state was being updated inside `ParallelExecutor`, then overwritten on teardown by the parent `Executor` saving its stale cache.
- This is now fixed by merging the parallel cache back into the parent executor before returning from `executeParallel()`.

### Current verification status

The following passed after the parallel cleanup:

- `zig test src/executor.zig`
- `zig test src/parallel.zig`

Additional regression coverage was added for parallel execution of:

- `@confirm`
- `@cd`
- `@shell`
- hooks
- `@cache`
- timeout handling
- external recipe delegation

### Recommended next step

Start with watch mode. That is still the highest-value open area after the parallel work.

Files to inspect first:

- `src/watch.zig`
- `src/main.zig`

Concrete watch-mode goals:

- Reparse the Jakefile and imports when the Jakefile changes.
- Stop reusing a stale AST after edits.
- Preserve the original execution context instead of reconstructing a partial one.
- Keep `jobs` / runtime behavior aligned with normal execution.
- Add a visited set to dependency collection to avoid recursive cycle blowups.
- Treat deleted watched files as changes.

### Remaining open items after parallel work

- `jake init` / `TODO.md` / `CHANGELOG.md` / docs are still out of sync.
- Parser diagnostics and silent fallthrough behavior are still too permissive.
- Windows-specific behavior remains under-tested.

### Worktree notes for handoff

There were unrelated in-progress edits already present in the worktree while this work was being done. They were left untouched:

- `src/external.zig`
- `src/import.zig`
- `src/main.zig`
- `tests/e2e/Jakefile`

## Handoff Update (2026-03-11, watch mode)

Watch mode has now been repaired enough to move it out of the top open slot from this review.

Completed:

- Jakefile loading was extracted into `src/jakefile_loader.zig` so normal CLI execution and watch-mode reloads use the same parse/import/external/runtime setup path.
- `Watcher` now owns the loaded Jakefile state for watch runs and reuses `Executor.initWithIndexAndContext(...)` instead of rebuilding a partial executor context.
- Automatic watch mode now tracks the main Jakefile, imported Jakefiles, and detected external build files in addition to recipe file dependencies and `@watch` patterns.
- Editing watched configuration files now reloads the Jakefile before rerunning the recipe, so watch mode no longer executes against a stale AST.
- Deleted watched files now register as a single change event and retrigger again if the file is recreated.
- Recipe dependency discovery in watch mode now uses a visited set, so cyclic recipe graphs no longer recurse indefinitely during watch-pattern collection.

Verification now includes:

- `zig test src/watch.zig`
- `zig build test`

Recommended next step:

- Move to the remaining external-integration issues from the original review, especially positional-argument propagation and path-resolution correctness relative to the selected Jakefile.

## Handoff Update (2026-03-11, external integration)

The main external-integration issues from the original review have now been addressed.

Completed:

- External Makefile/Justfile parsing now resolves files relative to the selected Jakefile directory instead of assuming the process cwd.
- Delegated external execution now forwards CLI positional arguments to the underlying `make` or `just` process.
- Delegated external execution now runs from the external file's directory, which restores relative-path behavior for nested `-f` Jakefiles.
- Empty external parse results are now allocator-owned, so cleanup no longer depends on freeing static empty slices.
- Added focused unit coverage in `src/external.zig` and `src/executor.zig` for nested external loading, delegated args, and delegated cwd behavior.
- Added E2E coverage in `tests/e2e/Jakefile` for nested external discovery via `-f` and delegated argument forwarding.

Verification now includes:

- `zig test src/external.zig`
- `zig test src/executor.zig`

Recommended next step:

- Move to the remaining frontend/runtime parity items, starting with `src/webui.zig`, output/cancellation behavior, and Web UI execution-context drift.

## Handoff Update (2026-03-11, Web UI)

The main Web UI parity items identified in this review are now closed.

Completed:

- Web-triggered recipe execution now starts from the real CLI context instead of hardcoding `.verbose = false`, `.jobs = 0`, and an empty positional-argument set.
- Browser-supplied recipe parameters are now parsed from the WebSocket payload and forwarded as normal `name=value` arguments.
- Web UI runs now validate `@require` directives before execution, matching the normal CLI path.
- WebSocket frame-handler threads are now explicitly detached, which removes an obvious background-thread ownership bug.
- Web UI execution threads are now joined cleanly between runs instead of losing the thread handle from inside the worker thread.
- Added focused unit coverage in `src/webui.zig` for command parsing and execution-context construction.
- Web-triggered execution now emits task, command, output, and summary events through the shared executor/event-emitter path instead of a separate partial reporting path.
- Browser-side `@confirm` transport is now implemented, so Web UI runs no longer auto-approve confirmation prompts.
- Stop/cancel now terminates running captured commands cleanly and reports cancellation back through the normal task/output/summary event flow.
- Added browser-level WebSocket E2E coverage for `@confirm`, dependency execution, streamed output, and cancel/stop behavior.

Still open:

- No additional Web UI-specific correctness gaps from this review remain open.

Verification now includes:

- `zig test src/webui.zig`
- `zig test src/executor.zig`
- `../../zig-out/bin/jake test-web` (from `tests/e2e`)
- `zig build test`

Recommended next step:

- Move to the next robustness pass around diagnostics, explicit error handling, and parser/context cleanup.

## Handoff Update (2026-03-11, parser and init error handling)

The main diagnostics and explicit-init-error items from this review are now closed.

Completed:

- Jakefile parse failures now print detailed source-context diagnostics through the shared loader path, including the failing line and caret location.
- Top-level parser fallthrough was removed for unknown directives, malformed imports, missing targeted-hook names, missing `@default` targets, and bare identifiers that are neither assignments nor recipe declarations.
- Parser-local array accumulators and final `Jakefile` assembly now use `errdefer` cleanup so allocation failures do not leak partially-owned state.
- `RuntimeContext.configure(...)` now propagates dotenv, export, and hook setup failures instead of silently downgrading behavior.
- Executor initialization now propagates variable-map, dotenv, export, hook, and cache setup failures instead of continuing with a partially initialized runtime.
- Parallel executor setup now treats worker-init failures explicitly, and the earlier ready-queue OOM fix remains in place.
- Formatter round-trips were updated to keep the stricter parser contract stable by serializing canonical quoted variable values and directive lines without duplicated keywords.
- Added focused regression coverage in `src/parser.zig`, `src/context.zig`, and `src/formatter.zig` for the new diagnostics and failure propagation paths.

Still open:

- The next remaining review items are no longer parser/runtime correctness. They are Phase 5 test-contract and CI work, especially Windows coverage, completion tests in CI, and aligning the repository on one Zig minimum version.

Verification now includes:

- `zig test src/parser.zig`
- `zig test src/context.zig`
- `zig test src/executor.zig`
- `zig test src/formatter.zig`
- `zig build test`

Recommended next step:

- Move to Phase 5 and tighten the test/CI contract, starting with completion coverage in CI, Windows-specific behavior coverage, and Zig-version alignment.

## Final Verdict

Request changes.

Jake has a workable architecture at the top level, but the current implementation is carrying too many runtime variants with subtly different behavior. The main opportunity is not adding more features. It is consolidating semantics, making failure modes explicit, and turning the documented behavior back into an enforceable contract.
