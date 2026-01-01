# Jake CLI Design v4 Specification

This document defines the v4 CLI output design for jake, based on patterns from Nx, Turborepo, and Cargo.

## Design Principles

1. **Animated feedback** — Spinners during task execution
2. **Nx-style summaries** — Individual task timings + summary at end
3. **Box-drawing for parallel** — Visual grouping of concurrent tasks
4. **Consistent symbols** — Same meaning everywhere
5. **Verbose with prefix** — All debug output uses `jake:` prefix

## Symbol Vocabulary

### Status Symbols

| Symbol | Color         | Meaning        | Usage                  |
| ------ | ------------- | -------------- | ---------------------- |
| `✓`    | Success Green | Task completed | After task finishes    |
| `✗`    | Error Red     | Task failed    | After task fails       |
| `—`    | Muted Gray    | Skipped        | Up to date, not for OS |

### Activity Symbols

| Symbol | Color          | Meaning            | Usage                 |
| ------ | -------------- | ------------------ | --------------------- |
| `⠋⠙⠹`  | Jake Rose      | Running (animated) | During task execution |
| `◉`    | Info Blue      | Watching           | Watch mode active     |
| `⟳`    | Warning Yellow | Changed            | File modification     |
| `○`    | Muted Gray     | Would run          | Dry-run pending tasks |

### UI Symbols

| Symbol | Color          | Meaning        | Usage                  |
| ------ | -------------- | -------------- | ---------------------- |
| `?`    | Warning Yellow | Prompt         | Confirmation required  |
| `▷`    | Info Blue      | Mode indicator | Dry-run header         |
| `│┌└`  | Muted Gray     | Box drawing    | Parallel task grouping |
| `{j}`  | Jake Rose      | Logo           | Version, help, errors  |

## Output Formats

### Version Output

```
$ jake --version
{j} jake 0.3.0
```

### Single Task Execution

```
$ jake build
   ⠋ build                    ← animated spinner
   ✓ build     1.82s          ← completion with timing

   Successfully ran 1 task
   Total time: 1.82s
```

### Sequential Tasks (with dependencies)

```
$ jake dev.ci
   ✓ lint      0.12s
   ✓ test      3.40s
   ✓ build     2.10s
   ✓ e2e       4.70s

   Successfully ran 4 tasks
   Total time: 10.3s
```

### Parallel Execution

```
$ jake -j4 release.all
   ┌─────────────────────────────────────────────────────┐
   │ ⠋ release.linux │ ⠋ release.macos │ ⠋ release.windows │  ← animated
   │ ✓ release.linux │ ✓ release.macos │ ⠋ release.windows │  ← as they finish
   │ ✓ release.linux │ ✓ release.macos │ ✓ release.windows │
   └─────────────────────────────────────────────────────┘

   ✓ release.linux     3.8s
   ✓ release.macos     3.2s
   ✓ release.windows   4.1s

   ✓ release.checksums 0.02s

   Successfully ran 4 tasks
   Total time: 4.2s
```

### Task Failure

```
$ jake test
   ✗ test

   src/parser.zig:142:25
   error: expected ')' after argument

   Failed to run 1 task
   Total time: 2.3s
```

### Watch Mode

```
$ jake -w dev
   ◉ watching src/**/*.zig

   ✓ dev       1.82s

   ⟳ changed src/parser.zig
   ✓ dev       0.34s

   watching for changes (ctrl+c to stop)
```

### Dry Run

```
$ jake -n release.all
   ▷ dry-run (no commands executed)

   ○ release.linux
     zig build -Dtarget=x86_64-linux
   ○ release.macos
     zig build -Dtarget=aarch64-macos
   ○ release.windows
     zig build -Dtarget=x86_64-windows

   4 tasks would run
```

### Cache Hit

```
$ jake build
   ✓ build [cached]     0.02s

   Successfully ran 1 task [1 cached]
   Total time: 0.02s
```

### Recipe List

```
$ jake -l
{j} jake 98 recipes • 14 groups

build
  build           Compile jake binary
  build-release   Optimized release build
  clean           Remove build artifacts

test
  test            Run all tests
  lint            Check code formatting
  e2e             End-to-end tests

... 88 more recipes (jake -la for all)
```

### Confirmation Prompt

```
$ jake editors.vscode-publish
   ✓ editors.vscode-package 1.2s

   ? Publish jake-lang 0.3.0 to marketplace? [y/N]
```

With `--yes`:

```
   ✓ editors.vscode-package 1.2s
   auto-confirmed: Publish jake-lang 0.3.0 to marketplace?
   ✓ editors.vscode-publish 3.4s
```

## Error Messages

### Recipe Not Found

```
$ jake biuld
error: recipe 'biuld' not found

   did you mean: build
```

### Missing Dependency

```
$ jake perf.tracy
error: required command not found: tracy

   hint: brew install tracy
```

### Parse Error

```
$ jake build
error: parse error in Jakefile

   ┌── Jakefile:24
   │
23 │ task build
24 │     zig build
   │     ^ expected ':' after task name
   │
```

### No Jakefile

```
$ jake build
{j} error: no Jakefile found

   Searched: Jakefile, jakefile, Jakefile.jake
   hint: run jake init to create one
```

## Verbose Output Format

All verbose messages use the `jake:` prefix in muted gray color.

### Categories

| Category     | Example                                         |
| ------------ | ----------------------------------------------- |
| Import       | `jake: importing 'build.jake'`                  |
|              | `jake: imported 12 recipes from 'build.jake'`   |
| Environment  | `jake: loading .env from '/project/.env'`       |
|              | `jake: loaded 5 variables from .env`            |
| Directory    | `jake: changing directory to '/project/src'`    |
| Variables    | `jake: expanding {{name}} → 'value'`            |
|              | `jake: calling {{env(HOME)}} → '/Users/dev'`    |
| Glob         | `jake: expanding 'src/*.zig' → 12 files`        |
| Cache        | `jake: cache hit for 'build' (up to date)`      |
|              | `jake: cache miss for 'build' (needs rebuild)`  |
|              | `jake: dependency 'lib.zig' changed`            |
| Dependencies | `jake: resolving dependencies for 'deploy'`     |
|              | `jake: dependency order: build → test → deploy` |
|              | `jake: parallel execution: 4 threads`           |
| Watch        | `jake: watching 24 files for changes`           |
|              | `jake: detected change in 'src/parser.zig'`     |
| Hooks        | `jake: running @pre hook for 'deploy'`          |
|              | `jake: hook exited with code 0`                 |
| Validation   | `jake: checking @require 'docker'`              |
|              | `jake: @require 'docker' satisfied`             |
|              | `jake: detected platform 'macos-aarch64'`       |
| Conditions   | `jake: evaluating 'env_exists(CI)' → true`      |
|              | `jake: @if block taken`                         |

### Example Verbose Execution

```
$ jake -v dev.ci
   jake: loading .env from /project/.env
   jake: loaded 3 variables from .env
   jake: importing 'jake/build.jake'
   jake: imported 12 recipes from 'jake/build.jake'
   jake: resolving dependencies for 'dev.ci'
   jake: dependency order: lint → test → build → e2e

   ✓ lint      0.12s
   jake: executing 'zig fmt --check src/'

   ✓ test      3.40s
   jake: executing 'zig build test'

   ✓ build     2.10s
   jake: executing 'zig build -Doptimize=ReleaseFast'
   jake: cache updated for 'build'

   ✓ e2e       4.70s
   jake: executing './zig-out/bin/jake -f tests/e2e/Jakefile'

   Successfully ran 4 tasks
   Total time: 10.3s
```

## Implementation Guide

### Files to Modify

| File               | Changes                                                                    |
| ------------------ | -------------------------------------------------------------------------- |
| `src/color.zig`    | Add new symbols: `◉`, `⟳`, `○`, `—`, `▷`. Add spinner frames constant.     |
| `src/executor.zig` | Recipe headers → spinner. Completion → timing. Nx summary. Verbose prefix. |
| `src/parallel.zig` | Box-drawing for parallel. Synchronized spinner. Per-thread updates.        |
| `src/main.zig`     | Version with `{j}`. Error formatting. No-Jakefile with `{j}`.              |
| `src/watch.zig`    | `◉` watching. `⟳` changed.                                                 |
| `src/args.zig`     | Help text with `{j}`.                                                      |
| `src/prompt.zig`   | `?` symbol. Auto-confirm format.                                           |

### Color Codes (from color.zig)

```zig
pub const symbols = struct {
    pub const arrow = "→";       // Keep for compatibility
    pub const success = "✓";
    pub const failure = "✗";
    pub const warning = "~";
    pub const logo = "{j}";

    // New v4 symbols
    pub const skipped = "—";
    pub const watching = "◉";
    pub const changed = "⟳";
    pub const pending = "○";
    pub const prompt = "?";
    pub const mode = "▷";

    // Spinner frames
    pub const spinner = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
};
```

### Verbose Logging Pattern

```zig
fn verboseLog(self: *Executor, comptime fmt: []const u8, args: anytype) void {
    if (self.verbose) {
        self.print("{s}jake: " ++ fmt ++ "{s}\n", .{
            self.color.muted(),
        } ++ args ++ .{
            self.color.reset(),
        });
    }
}
```

## Summary

The v4 design provides:

1. **Clear visual feedback** — Animated spinners show progress
2. **Parallel visibility** — Box-drawing groups concurrent tasks
3. **Actionable information** — Nx-style summaries with timing
4. **Debug capability** — Verbose mode with consistent prefix
5. **Brand identity** — `{j}` logo in key locations
