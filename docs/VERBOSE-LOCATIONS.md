# Verbose Logging Opportunities

This document identifies locations where additional debug information should be printed when `--verbose` is provided.

## Current Verbose Logging

The verbose flag is currently used in these locations:

| File | Line | What's Logged |
|------|------|---------------|
| `executor.zig` | 653-656 | Parallel execution thread count and stats |
| `executor.zig` | 716-718 | File target "is up to date" messages |
| `executor.zig` | 1276-1278 | Command echo (`$ command`) |
| `hooks.zig` | 191-192 | Hook command being executed |
| `watch.zig` | 189-191 | File not found warning |

## Proposed Additions

### High Priority

#### 1. @import Resolution (`import.zig`)

**Location**: `resolveImports()` function
**Currently**: No verbose flag passed to ImportResolver
**What to log**:
- `jake: importing '{path}'`
- `jake: importing '{path}' as '{namespace}'`
- `jake: imported {n} recipes, {n} variables from '{path}'`
- `jake: circular import detected: {path}` (before error)

#### 2. .env File Loading (`env.zig` / `executor.zig`)

**Location**: `loadDotenv()` function, called from `executor.zig:80-83`
**Currently**: Silent loading
**What to log**:
- `jake: loading .env from '{path}'`
- `jake: loaded {n} variables from .env`
- `jake: .env file not found (skipping)`

#### 3. @cd Directive (`executor.zig`)

**Location**: When `current_working_dir` is set/used
**Currently**: Silent directory changes
**What to log**:
- `jake: changing directory to '{path}'`
- `jake: recipe '{name}' running in '{path}'`

#### 4. Variable Expansion (`executor.zig`)

**Location**: `expandJakeVariables()` function (~line 1390)
**Currently**: Silent expansion
**What to log**:
- `jake: expanding variable '{{name}}' -> '{value}'`
- `jake: variable '{{name}}' not found, keeping literal`
- `jake: calling function {{func(arg)}} -> '{result}'`

#### 5. Glob Pattern Matching (`glob.zig` / `executor.zig`)

**Location**: `expandGlob()` calls
**Currently**: Silent expansion
**What to log**:
- `jake: expanding glob '{pattern}' -> {n} files`
- `jake: glob '{pattern}' matched: {file1}, {file2}, ...` (if few files)

#### 6. Cache Operations (`cache.zig`)

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

**Location**: `buildGraph()` function
**Currently**: Only parallel stats logged
**What to log**:
- `jake: resolving dependencies for '{recipe}'`
- `jake: dependency order: {recipe1} -> {recipe2} -> {recipe3}`
- `jake: critical path: {recipe1} -> {recipe2} ({n} steps)`

#### 8. Watch Mode (`watch.zig`)

**Location**: `resolvePatterns()`, file change detection
**Currently**: Only "file not found" warning
**What to log**:
- `jake: watching {n} files for changes`
- `jake: watching pattern '{pattern}'`
- `jake: detected change in '{file}'`
- `jake: triggering rebuild due to '{file}' modification`

#### 9. Hook Details (`hooks.zig`)

**Location**: `run()` function
**Currently**: Logs command being executed
**Additional logging**:
- `jake: running {pre|post|on_error} hook for '{recipe}'`
- `jake: running global {pre|post|on_error} hook`
- `jake: hook exited with code {n}`

#### 10. Recipe Parameter Binding (`executor.zig`)

**Location**: `bindRecipeParams()` function (~line 800)
**Currently**: Silent binding
**What to log**:
- `jake: binding parameter '{name}' = '{value}'`
- `jake: using default for parameter '{name}' = '{default}'`

#### 11. @shell Directive (`executor.zig`)

**Location**: When `current_shell` is set/used
**Currently**: Silent
**What to log**:
- `jake: using shell '{shell}' for recipe '{name}'`
- `jake: using default shell '/bin/sh'`

#### 12. Platform Filtering (`executor.zig`)

**Location**: `shouldSkipForOs()` function
**Currently**: Prints skip message but not verbose-gated
**What to log**:
- `jake: detected platform '{os}'`
- `jake: recipe '{name}' restricted to '{os}', skipping`

### Low Priority

#### 13. Condition Evaluation (`conditions.zig`)

**Location**: Condition function evaluation
**Currently**: Silent
**What to log**:
- `jake: evaluating condition '{condition}' -> {true|false}`
- `jake: @if block {taken|skipped}`

#### 14. Function Evaluation (`functions.zig`)

**Location**: Built-in function calls
**Currently**: Silent
**What to log**:
- `jake: {func}({arg}) -> '{result}'`

#### 15. @require Validation (`executor.zig`)

**Location**: Requirement checking during init
**Currently**: Only errors on failure
**What to log**:
- `jake: checking @require '{program}'`
- `jake: @require '{program}' satisfied`

#### 16. @export Directive (`executor.zig`)

**Location**: When variables are exported to environment
**Currently**: Silent
**What to log**:
- `jake: exporting '{name}={value}' to environment`

#### 17. @confirm Prompt (`prompt.zig` / `executor.zig`)

**Location**: When `-y` auto-confirms
**Currently**: Silent when using `-y`
**What to log**:
- `jake: auto-confirming '{message}' (--yes flag)`

#### 18. Timeout Handling (`executor.zig`)

**Location**: `executeCommandsWithTimeout()`
**Currently**: Silent
**What to log**:
- `jake: command timeout set to {n}s`
- `jake: command killed after {n}s timeout`

## Implementation Notes

### Verbose Flag Propagation

Several modules need the verbose flag passed to them:

| Module | Currently Has Verbose | Needs Verbose |
|--------|----------------------|---------------|
| `executor.zig` | Yes | - |
| `parallel.zig` | Yes | - |
| `watch.zig` | Yes | - |
| `hooks.zig` | Yes | - |
| `import.zig` | No | Yes |
| `glob.zig` | No | Yes |
| `cache.zig` | No | Yes |
| `env.zig` | No | Yes |
| `conditions.zig` | No | Yes |
| `functions.zig` | No | Yes |

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
