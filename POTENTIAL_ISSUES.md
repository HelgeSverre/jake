# POTENTIAL_ISSUES

## 1. `loadJakefile()` changes the global process working directory

- **Files:** `src/jakefile_loader.zig`
- **Impact:** Correctness, reentrancy, embeddability, future concurrency
- **Summary:** `loadJakefile()` calls `std.posix.chdir(dir)` while resolving a Jakefile from a parent directory. That makes parsing/loading mutate global process state, which can silently affect later relative path handling across the process.
- **Why this matters:** A load/parse operation should not have process-wide side effects. This can break callers that expect cwd to remain stable, make nested loads harder to reason about, and create correctness hazards if more concurrent behavior is added later.
- **Suggested fix:** Stop using global `chdir()` during load. Resolve files relative to an explicit base directory and thread that base path through import/external/watch resolution.

## 2. Hook execution is still Unix-specific

- **Files:** `src/hooks.zig`
- **Impact:** Cross-platform correctness
- **Summary:** Hooks are executed through a hard-coded `"/bin/sh" -c ...` path.
- **Why this matters:** `@pre`, `@post`, and `@on_error` hooks will not work correctly on Windows, even though other parts of the codebase already have platform-aware shell/path handling.
- **Suggested fix:** Route hook execution through the same shell-selection abstraction used elsewhere, or centralize process launching behind `src/system.zig`.

## 3. `@on_error` parsing relies on a brittle heuristic — FIXED

- **Files:** `src/parser.zig`, `src/hooks.zig`, `src/executor.zig`
- **Resolution:** Top-level `@on_error` is now always global (no recipe target). Recipe-specific error handlers use body-level `@on_error` inside the recipe, mirroring `@pre`/`@post`. The heuristic is gone.
- **Migration:** any `@on_error recipe cmd` form must move into the recipe body as `@on_error cmd`.

## 4. Parallel execution snapshots and merges the full cache per worker

- **Files:** `src/parallel.zig`
- **Impact:** Performance, memory usage
- **Summary:** Each worker clones the shared cache, executes with the clone, then merges the entire result back under a lock.
- **Why this matters:** For larger projects or many parallel tasks, this adds avoidable O(cache-size × tasks) copy/merge overhead and memory churn directly on the hot path for `-j` execution.
- **Suggested fix:** Move to a more incremental cache-update model: shared read-only view plus narrow writeback, per-task delta tracking, or finer-grained synchronization around cache mutation.

## 5. Watch mode repeatedly re-expands globs and re-deduplicates the full file set

- **Files:** `src/watch.zig`
- **Impact:** Performance
- **Summary:** On each poll, watch mode re-expands glob patterns, appends matches again, then deduplicates the whole `resolved_files` list.
- **Why this matters:** This creates steady-state allocation and scanning overhead, especially for broad globs or larger repositories. Polling-based watch mode is already relatively expensive, so extra churn here matters.
- **Suggested fix:** Maintain a stable resolved-file set keyed by pattern and update incrementally, instead of append-then-deduplicate on every pass.

## Priority order

1. Fix hook shell selection.
2. Remove `chdir()` from Jakefile loading.
3. ~~Replace the `@on_error` parsing heuristic.~~ FIXED.
4. Rework parallel cache handling.
5. Make watch mode maintain stable resolved file state.
