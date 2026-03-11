# Verbose Logging Opportunities

This document identifies locations where additional debug information should be printed when `--verbose` is provided.

## Current Verbose Logging

The verbose flag is currently used in these locations:

| File            | Line      | What's Logged                                          |
| --------------- | --------- | ------------------------------------------------------ |
| `executor.zig`  | 794-797   | Parallel execution thread count and stats              |
| `executor.zig`  | 866-868   | File target "is up to date" messages                   |
| `executor.zig`  | 1463-1466 | Command execution logging (`jake: executing '{cmd}'`)  |
| `hooks.zig`     | 191-193   | Hook type and command (`jake: running @{type} hook:`)  |
| `watch.zig`     | 327-336   | File not found warning during pattern resolution       |
| `watch.zig`     | 454-456   | Lists individual watched files                         |
| `parallel.zig`  | 429-430   | File target "is up to date" (parallel mode)            |

### Notable: `verbose_level` exists but is unused

`args.zig` parses `-v`, `-vv`, `-vvv` into a `verbose_level` (0-3), but this is **never propagated** to the `Context` struct. Only the boolean `verbose` flag reaches the execution layer. This could be used for tiered output (e.g., `-v` high-priority, `-vv` medium, `-vvv` low priority).

### Notable: `conditions.zig` has `is_verbose()` function

The `is_verbose()` condition function (line 49-50) reads `context.verbose` so Jakefile authors can write `@if(is_verbose)` blocks. This is a user-facing feature, not diagnostic logging.

## Proposed Additions

### High Priority

#### 1. @import Resolution (`import.zig`)

**Status**: NOT IMPLEMENTED
**Location**: `resolveImports()` function
**Currently**: No verbose flag passed to ImportResolver
**What to log**:

- `jake: importing '{path}'`
- `jake: importing '{path}' as '{namespace}'`
- `jake: imported {n} recipes, {n} variables from '{path}'`
- `jake: circular import detected: {path}` (before error)

#### 2. .env File Loading (`env.zig` / `executor.zig`)

**Status**: NOT IMPLEMENTED
**Location**: `loadDotenv()` function, called from executor.zig
**Currently**: Silent loading
**What to log**:

- `jake: loading .env from '{path}'`
- `jake: loaded {n} variables from .env`
- `jake: .env file not found (skipping)`

#### 3. @cd Directive (`executor.zig`)

**Status**: NOT IMPLEMENTED
**Location**: When `current_working_dir` is set/used
**Currently**: Silent directory changes
**What to log**:

- `jake: changing directory to '{path}'`
- `jake: recipe '{name}' running in '{path}'`

#### 4. Variable Expansion (`executor.zig`)

**Status**: NOT IMPLEMENTED
**Location**: `expandJakeVariables()` function
**Currently**: Silent expansion
**What to log**:

- `jake: expanding variable '{{name}}' -> '{value}'`
- `jake: variable '{{name}}' not found, keeping literal`
- `jake: calling function {{func(arg)}} -> '{result}'`

#### 5. Glob Pattern Matching (`glob.zig` / `executor.zig`)

**Status**: NOT IMPLEMENTED
**Location**: `expandGlob()` calls
**Currently**: Silent expansion
**What to log**:

- `jake: expanding glob '{pattern}' -> {n} files`
- `jake: glob '{pattern}' matched: {file1}, {file2}, ...` (if few files)

#### 6. Cache Operations (`cache.zig`)

**Status**: NOT IMPLEMENTED
**Location**: `isStale()`, `isGlobStale()`, `update()`, `load()`
**Currently**: Silent cache checks
**What to log**:

- `jake: loading cache from .jake/cache`
- `jake: cache hit for '{target}' - up to date`
- `jake: cache miss for '{target}' - needs rebuild`
- `jake: updating cache for '{target}'`
- `jake: dependency '{dep}' changed, rebuilding '{target}'`

### Medium Priority

#### 7. Dependency Resolution (`parallel.zig`)

**Status**: NOT IMPLEMENTED
**Location**: `buildGraph()` function
**Currently**: Only parallel stats logged (thread count, recipe count)
**What to log**:

- `jake: resolving dependencies for '{recipe}'`
- `jake: dependency order: {recipe1} -> {recipe2} -> {recipe3}`
- `jake: critical path: {recipe1} -> {recipe2} ({n} steps)`

#### 8. Watch Mode (`watch.zig`)

**Status**: PARTIALLY IMPLEMENTED
**Already done**: File not found warnings (lines 321-330), watched file listing (lines 448-450)
**Still needed**:

- `jake: watching {n} files for changes`
- `jake: watching pattern '{pattern}'`
- `jake: detected change in '{file}'`
- `jake: triggering rebuild due to '{file}' modification`

**Note**: Watch mode is flagged for refactoring in CODE-REVIEW-CODEX.md (reparse on Jakefile change, cycle-safe traversal, etc.). Verbose additions here should be coordinated with that work.

#### 9. Hook Details (`hooks.zig`)

**Status**: PARTIALLY IMPLEMENTED
**Already done**: Logs hook type and command (`jake: running @{type} hook: {cmd}`) at line 191-193
**Still needed**:

- `jake: running {pre|post|on_error} hook for '{recipe}'` (recipe-specific context)
- `jake: running global {pre|post|on_error} hook` (global vs recipe distinction)
- `jake: hook exited with code {n}`

#### 10. Recipe Parameter Binding (`executor.zig`)

**Status**: NOT IMPLEMENTED
**Location**: `bindRecipeParams()` function
**Currently**: Silent binding
**What to log**:

- `jake: binding parameter '{name}' = '{value}'`
- `jake: using default for parameter '{name}' = '{default}'`

#### 11. @shell Directive (`executor.zig`)

**Status**: NOT IMPLEMENTED
**Location**: When `current_shell` is set/used
**Currently**: Silent
**What to log**:

- `jake: using shell '{shell}' for recipe '{name}'`
- `jake: using default shell '/bin/sh'`

#### 12. Platform Filtering (`executor.zig`)

**Status**: EXISTS BUT NOT VERBOSE-GATED
**Location**: Line 833 prints unconditionally: `jake: skipping '{name}' (not for {os})`
**Also**: `parallel.zig` line 414 prints the same message unconditionally
**What to change**:

- Gate existing skip messages behind `verbose` (they currently always print)
- Add: `jake: detected platform '{os}'`

### Low Priority

#### 13. Condition Evaluation (`conditions.zig`)

**Status**: NOT IMPLEMENTED
**Location**: Condition function evaluation
**Currently**: Has verbose flag (for `is_verbose()` user function) but no diagnostic logging
**What to log**:

- `jake: evaluating condition '{condition}' -> {true|false}`
- `jake: @if block {taken|skipped}`

#### 14. Function Evaluation (`functions.zig`)

**Status**: NOT IMPLEMENTED
**Location**: Built-in function calls
**Currently**: Silent
**What to log**:

- `jake: {func}({arg}) -> '{result}'`

#### 15. @require Validation (`executor.zig`)

**Status**: NOT IMPLEMENTED
**Location**: Requirement checking during init
**Currently**: Only errors on failure
**What to log**:

- `jake: checking @require '{program}'`
- `jake: @require '{program}' satisfied`

#### 16. @export Directive (`executor.zig`)

**Status**: NOT IMPLEMENTED
**Location**: When variables are exported to environment
**Currently**: Silent
**What to log**:

- `jake: exporting '{name}={value}' to environment`

#### 17. @confirm Prompt (`prompt.zig` / `executor.zig`)

**Status**: NOT IMPLEMENTED
**Location**: When `-y` auto-confirms
**Currently**: Silent when using `-y`
**What to log**:

- `jake: auto-confirming '{message}' (--yes flag)`

#### 18. Timeout Handling (`executor.zig`)

**Status**: NOT IMPLEMENTED
**Location**: `executeCommandsWithTimeout()`
**Currently**: Silent setup, only logs on timeout exceeded (unconditional)
**What to log**:

- `jake: command timeout set to {n}s`
- `jake: command killed after {n}s timeout`

## Implementation Notes

### Verbose Flag Propagation

Several modules need the verbose flag passed to them:

| Module           | Currently Has Verbose | Needs Verbose | Notes                                    |
| ---------------- | --------------------- | ------------- | ---------------------------------------- |
| `executor.zig`   | Yes                   | -             | Primary verbose consumer                 |
| `parallel.zig`   | Yes                   | -             | Uses shared RecipeRunner now             |
| `watch.zig`      | Yes (via ctx)         | -             | Needs more logging, not more plumbing    |
| `hooks.zig`      | Yes                   | -             | Needs recipe context for richer messages |
| `conditions.zig` | Yes (for is_verbose)  | Yes (logging) | Has flag but only for user function      |
| `import.zig`     | No                    | Yes           |                                          |
| `glob.zig`       | No                    | Yes           |                                          |
| `cache.zig`      | No                    | Yes           |                                          |
| `env.zig`        | No                    | Yes           |                                          |
| `functions.zig`  | No                    | Yes           |                                          |
| `prompt.zig`     | No                    | Yes           |                                          |

### Interaction with CODE-REVIEW-CODEX.md

The parallel executor now uses the shared `RecipeRunner` (per the handoff update in CODE-REVIEW-CODEX.md), so verbose logging added to `executor.zig` will automatically apply to parallel mode. Key considerations:

- **Safe to implement now**: Items 1-6 (high priority) and 10-18 (medium/low) are pure additions to existing code paths
- **Coordinate with watch refactor**: Item 8 (watch mode) should align with the recommended watch mode refactor (reparse on change, cycle-safe traversal)
- **Platform filtering (#12)**: Gating the skip message behind verbose is a minor behavior change (users currently see it always)

### Logging Format

Use consistent prefix format:

```
jake: {action} {details}
```

Examples:

```
jake: importing 'build.jake'
jake: loading .env from '/project/.env'
jake: changing directory to '/project/src'
jake: expanding glob 'src/*.zig' -> 12 files
jake: cache hit for 'build/app' - up to date
```

### Privacy Considerations

- Avoid logging full variable values for potentially sensitive data
- Consider truncating long values: `jake: expanding 'API_KEY' -> '****'`
- Log file paths but not file contents
