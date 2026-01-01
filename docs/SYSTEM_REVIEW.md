# System Review

## Feedback

**Architecture Review**

- `src/main.zig:37-313` cleanly stages CLI handling, formatter/completions shortcuts, Jakefile loading, and then
  instantiates `Executor`/`Watcher`, so the top-level flow is easy to reason about. However, nearly all runtime
  concerns (dry-run, verbosity, watch flags, shell selection) live on `Executor` itself instead of the shared `Context`
  type defined in `src/context.zig:8-36`, so modules below `main` still depend directly on CLI wiring.
- Recipes, directives, imports, and hooks are parsed into flat slices (`src/parser.zig:10-191`), and runtime modules (
  `executor`, `parallel`, `watch`, `hooks`, `conditions`) each traverse those slices independently. This keeps parsing
  simple but means downstream consumers repeatedly linearly scan for recipes, variables, and directives. The executor
  stack therefore couples tightly to the exact `Jakefile` representation instead of working with higher-level query
  interfaces.
- Parallel execution is implemented as a separate subsystem (`src/parallel.zig:1-312`) that rebuilds dependency graphs,
  caches, variable maps, color themes, and `@needs` handling on its own. Because `Executor` (`src/executor.zig:39-315`)
  contains similar logic (cache lookups, hook orchestration, environment validation, `@needs/@watch` parsing), the two
  modules are effectively forked copies, raising maintenance cost whenever behavior changes in one but not the other.
- Watch mode (`src/watch.zig:25-146`) re-parses recipes and their command lists to discover patterns, duplicating logic
  already present in executor directives (e.g., `@watch`, file deps). This module accesses the parser structs directly
  and repeats tree walks, which tightens coupling to AST details.

**Data Structures & Coupling**

- `Jakefile.getRecipe`, `.getVariable`, and related helpers iterate over arrays every time (`src/parser.zig:118-190`).
  With imports and aliases, listing or executing recipes now scales linearly with the total number of declarations. The
  executor partially compensates by mirroring variables into a `StringHashMap` (`src/executor.zig:62-150`), but other
  modules (watcher, formatter, suggest) still pay the O(N) cost.
- `Executor` keeps several hash maps (`executed`, `in_progress`, `variables`) plus arrays for expanded strings and hook
  state (`src/executor.zig:39-150`). `ParallelExecutor` initializes its own copies (`src/parallel.zig:89-155`) instead
  of delegating to shared services, so there’s no single source for caching, hook policy, or environment resolution.
- The cache layer uses SHA-256 hashes stored in `.jake/cache` (`src/cache.zig:6-188`). It works, but file and glob
  freshness checks are invoked from both executor paths and parallel workers separately, and there’s no reference
  counting for paths shared between recipes, leading to duplicated hashing effort when `@cache` is specified on multiple
  tasks.

**Build System Review**

- `build.zig:67-275` wires options (git versioning, Tracy flag) and defines executables for CLI, tests, fuzzing, and
  benchmarks. Tests are run via two custom `std.Build.Step.Run` instances to avoid the Zig `--listen` issue—this is
  pragmatic but duplicated (module/exe). There’s no top-level step for formatting or linting even though the Jakefile
  expects `zig fmt` to run before Prettier (`jake/build.jake:3-108`).
- Version metadata is gathered by shelling out to git/date for every `zig build`, which slows non-release workflows and
  fails when the source tree is distributed without `.git`. The build falls back to `"0.0.0-unknown"` but still invokes
  external commands each run.
- The Jakefile tasks provide richer workflows (coverage, packaging, editors), yet none are exposed through `zig build`
  aliases; contributors must learn two parallel build entry points. Coverage tasks rely on GNU `find`, `head`, and
  `sed` (`jake/build.jake:70-96`), which can misbehave on macOS without BSD/GNU compatibility layers.

**Recommendations**

- Introduce indexed views of the Jakefile (e.g., `StringHashMap` for recipes/aliases, variable lookup tables) right
  after parsing, so modules consume an interface like `JakefileIndex`. This removes repeated linear scans and decouples
  consumers from the raw slices (`src/parser.zig:10-191`). It also makes alias/default resolution deterministic for
  large Jakefiles.
- Make `Executor`, `ParallelExecutor`, and `Watcher` consume a shared `Context` + service layer (cache manager, hook
  runner, env loader). Instead of each struct holding its own state copies (`src/executor.zig:39-150`,
  `src/parallel.zig:89-155`, `src/watch.zig:25-146`), push that into reusable components. This would cut coupling to
  CLI-specific flags, ensure directives (`@needs`, `@watch`, `@confirm`) behave identically in sequential/parallel/watch
  modes, and lower the risk of drift.
- Factor the parallel scheduler into a strategy used by `Executor` (e.g., `Executor.run(target, strategy)` where
  strategy decides single-threaded vs. parallel). Today `parallel.zig` reimplements command execution, cache updates,
  and output formatting; unifying these paths would centralize hook handling, error reporting, and caching policy while
  letting the scheduler focus solely on dependency ordering.
- Extend `build.zig` with explicit `fmt`, `lint`, and `e2e` steps that shell out to existing Jake tasks or native Zig
  equivalents (`build.zig:67-275`, `jake/build.jake:3-108`). This gives contributors a consistent `zig build <step>`
  interface and reduces the need to memorize Jake commands when they only need formatting or tests.
- Cache git metadata at configure time or behind an env flag so `zig build` in clean/exported trees doesn’t incur
  unavoidable subprocess calls. For example, guard `getGitVersion`/`getGitHash` behind `if (b.enableReleaseMode())` or
  persist last-known values in `zig-cache`, reducing overhead for rapid-dev loops (`build.zig:3-45`, `67-90`).
- Harden Jakefile coverage/packaging tasks by replacing platform-specific `find/head/sed` chains with Zig or Jake-native
  helpers, or at least gate them per OS (`jake/build.jake:70-96`). That lowers hidden dependencies on GNU coreutils and
  makes the automation usable on default macOS setups.

----

## Action Plan

### 1. Build `JakefileIndex` for Fast Lookups

**Tasks**

1. Create `src/jakefile_index.zig` defining `JakefileIndex` with hash maps for recipes (including aliases), variables,
   and directives populated immediately after parsing.
2. Update `parser.parseJakefile()` to return both `Jakefile` and `JakefileIndex`, or expose a helper that builds the
   index from an existing AST.
3. Refactor consumers (`executor`, `parallel`, `watch`, `formatter`, `suggest`) to query the index instead of walking
   arrays.
4. Add unit tests ensuring alias lookup, default recipe resolution, and variable retrieval remain correct with the index
   in place.

**Before**

```zig
pub fn getRecipe(self: *const Jakefile, name: []const u8) ?*const Recipe {
    for (self.recipes) |*recipe| {
        if (std.mem.eql(u8, recipe.name, name)) return recipe;
        for (recipe.aliases) |alias| {
            if (std.mem.eql(u8, alias, name)) return recipe;
        }
    }
    return null;
}
```

**After**

```zig
pub fn getRecipe(self: *const JakefileIndex, name: []const u8) ?*const Recipe {
    if (self.recipes.get(name)) |entry| {
        return entry;
    }
    return null;
}
```

**Reasoning**
Hash-based access removes repeated O(N) scans, keeps alias/default behavior centralized, and lets future modules (like
tooling or language servers) reuse the same indexed representation without duplicating traversal logic.

### 2. Share Runtime Context and Services

**Tasks**

1. Expand `Context` (`src/context.zig`) into a `RuntimeContext` that owns allocator references, color theme, environment
   loader, hook runner, cache handle, and CLI flags.
2. Update `Executor`, `ParallelExecutor`, and `Watcher` initializers to accept the shared context rather than
   duplicating fields.
3. Move directive handlers (`@needs`, `@watch`, `@confirm`) and hook execution helpers into reusable components
   referenced by all execution modes.
4. Add regression tests covering dry-run, verbose, and auto-yes behavior to confirm parity between
   sequential/parallel/watch code paths.

**Before**

```zig
var executor = jake.Executor.init(allocator, &jakefile_data.jakefile);
executor.dry_run = args.dry_run;
executor.verbose = args.verbose;
executor.watch_mode = args.watch_enabled;
```

**After**

```zig
var ctx = RuntimeContext.init(allocator, args);
var executor = jake.Executor.init(&ctx, &jakefile_data.jakefile);
// Executor reads ctx.flags.dry_run, ctx.services.cache, etc.
```

**Reasoning**
Centralizing runtime state prevents drift between modules, simplifies testing, and makes it possible to inject mocked
services (cache, hooks, env) for unit tests or future plugins without editing every executor variant.

### 3. Unify Parallel Scheduling with Command Execution

**Tasks**

1. Extract command execution (hook invocation, directive handling, cache updates) from `Executor` into a `CommandRunner`
   component.
2. Change `Executor.execute()` to accept a scheduling strategy that either runs sequentially or delegates to a parallel
   scheduler.
3. Refactor `parallel.zig` to only build dependency graphs and feed ready recipes back into `CommandRunner`, removing
   duplicated env/cache logic.
4. Add integration tests that run the same Jakefile via sequential and parallel strategies to verify identical output
   and caching behavior.

**Before**

```zig
// parallel.zig
const success = self.executeNode(task_idx);
if (recipe.kind == .file) {
if (recipe.output) |output| {
self.cache.update(output) catch {};
}
}
```

**After**

```zig
// parallel scheduler hands nodes to shared runner
def success = command_runner.run(recipe);
if (!success) self.first_error = command_runner.lastError();
```

**Reasoning**
Having a single command execution engine ensures hooks, directives, and caching semantics stay consistent regardless of
scheduling mode, and dramatically reduces duplicate code.

### 4. Extend `zig build` Steps for Tooling Parity

**Tasks**

1. Add `fmt`, `lint`, and `e2e` top-level steps in `build.zig` that invoke `zig fmt`, `zig fmt --check`, and `tests/e2e`
   respectively (reusing existing Jake tasks where practical).
2. Document the new steps in `README.md` and `docs/SYNTAX.md` so contributors know they mirror the Jake tasks.
3. Update CI workflows to call the new steps, ensuring consistency between local Zig-based workflows and Jake
   automation.

**Before**

```bash
zig build           # builds binary
jake lint           # separate command for formatting
```

**After**

```bash
zig build fmt       # formats Zig sources
zig build lint      # checks formatting + docs
zig build e2e       # runs end-to-end fixtures
```

**Reasoning**
Providing equivalent Zig build steps removes the need to switch mental models between Zig and Jake for common
operations, simplifying onboarding and CI configuration.

### 5. Cache Git Metadata Lookups

**Tasks**

1. Introduce a `--cached-version` option or environment guard that reads version/hash info from `zig-cache` when `.git`
   is absent.
2. Modify `getGitVersion`/`getGitHash` to short-circuit when running outside release builds or when cached data is
   available.
3. Write a small helper script that records the current version info into `zig-cache/git-info` after successful
   `zig build` runs.
4. Add tests (or at least CI checks) that simulate builds in a git-less directory to ensure the fallback works without
   external commands.

**Before**

```zig
const result = b.runAllowFail(&.{ "git", "describe", "--tags", "--always" }, &code, .Ignore) catch {
    return "0.0.0-unknown";
};
```

**After**

```zig
if (gitInfoFromCache(b)) |cached| {
return cached.version;
}
if (!hasGitDir()) return "0.0.0-unknown";
return fetchGitVersion();
```

**Reasoning**
Avoiding unconditional subprocess calls speeds up iterative builds and keeps exported source archives functional without
requiring a git binary or repository metadata.

### 6. Harden Coverage & Packaging Tasks

**Tasks**

1. Replace GNU-specific `find/head/sed` pipelines in `jake/build.jake` coverage tasks with Zig helpers or portable Jake
   functions.
2. Add OS guards (`@only_os`) so tasks that truly need GNU tooling are clearly marked and provide hints for macOS users.
3. Provide Jake functions (e.g., `latest_test_binary()` or `coverage_report_path()`) to encapsulate filesystem traversal
   logic.
4. Document the portable approach in `GUIDE.md` to set expectations for contributors.

**Before**

```jake
kcov --include-pattern={{absolute_path("src")}}/ coverage-out $(find .zig-cache/o -name "test" -type f -perm +111 -size +2M 2>/dev/null | xargs ls -t | head -1)
```

**After**

```jake
set latest_test = {{latest_test_binary()}}
kcov --include-pattern={{absolute_path("src")}}/ coverage-out {{latest_test}}
```

**Reasoning**
Removing platform-specific shell idioms lowers surprise for macOS contributors and encapsulates tricky filesystem logic
inside Jake helpers that can be tested and evolved independently.
