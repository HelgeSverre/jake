# Executor.zig Refactoring Plan (Revised)

## Goal

Break down `executor.zig` (~1700 lines of code + ~3550 lines of tests) into focused modules following Zig Zen principles.

**Key Constraints**:

- Zig cannot split struct methods across files—use wrapper method pattern
- Avoid circular imports—helper modules must not import `Executor`
- Also deduplicate shared code in `parallel.zig`

---

## Phase 1: Extract Pure Utilities (No Dependencies)

### 1.1 Create `src/platform.zig`

**Lines affected**: 830-862 in executor.zig, 975-1006 in parallel.zig

**Extract**:

- `getCurrentOsString()` → `platform.getCurrentOs()`
- `shouldSkipForOs(recipe)` → `platform.shouldSkipForOs(recipe.only_os)`

**New file structure**:

```zig
// src/platform.zig
const builtin = @import("builtin");
const parser = @import("parser.zig");

pub fn getCurrentOs() []const u8 {
    return switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        .freebsd => "freebsd",
        .openbsd => "openbsd",
        .netbsd => "netbsd",
        .dragonfly => "dragonfly",
        else => "unknown",
    };
}

pub fn shouldSkipForOs(only_os: []const []const u8) bool {
    if (only_os.len == 0) return false;
    const current_os = getCurrentOs();
    for (only_os) |allowed_os| {
        if (std.mem.eql(u8, current_os, allowed_os)) return false;
    }
    return true;
}
```

**Changes to executor.zig**:

```zig
const platform = @import("platform.zig");
// Replace: getCurrentOsString() → platform.getCurrentOs()
// Replace: shouldSkipForOs(recipe) → platform.shouldSkipForOs(recipe.only_os)
```

**Changes to parallel.zig**:

- Same pattern, remove duplicated functions

**Risk**: Very low - pure functions, no state

---

### 1.2 Create `src/system.zig`

**Lines affected**: 187-209 in executor.zig, 397-419 in parallel.zig

**Extract**:

- `commandExists(cmd)` - checks if command is in PATH

**New file structure**:

```zig
// src/system.zig
const std = @import("std");

pub fn commandExists(cmd: []const u8) bool {
    // Handle absolute paths
    if (cmd.len > 0 and cmd[0] == '/') {
        return std.fs.accessAbsolute(cmd, .{}) != error.FileNotFound;
    }
    // Search PATH...
}
```

**Changes to executor.zig**:

```zig
const system = @import("system.zig");

// In Executor struct, replace method with:
fn commandExists(self: *Executor, cmd: []const u8) bool {
    _ = self;
    return system.commandExists(cmd);
}
// Or call system.commandExists() directly at call sites
```

**Changes to parallel.zig**:

- Remove duplicated `commandExists`, use `system.commandExists()`

**Risk**: Very low - pure function, only uses std

---

## Phase 2: Extract Variable Expansion

### 2.1 Create `src/expansion.zig`

**Lines affected**: 569-587, 1246-1305 in executor.zig

**Extract**:

- `expandJakeVariables(line)` → variable substitution `{{var}}`
- `expandItemVariable(input, item)` → `{{item}}` substitution

**Key Design**: Functions must NOT import Executor (avoids cycles). Pass required data as parameters.

**New file structure**:

```zig
// src/expansion.zig
const std = @import("std");
const functions = @import("functions.zig");

/// Expand {{item}} placeholder in a string
pub fn expandItem(
    allocator: std.mem.Allocator,
    input: []const u8,
    item: []const u8,
) ![]const u8 { ... }

/// Expand {{var}}, {{func(arg)}}, $1, $2, $@ variables
pub fn expandVariables(
    allocator: std.mem.Allocator,
    variables: *const std.StringHashMap([]const u8),
    positional_args: []const []const u8,
    line: []const u8,
) ![]const u8 { ... }
```

**Changes to executor.zig**:

```zig
const expansion = @import("expansion.zig");

// Wrapper methods (preserves API):
fn expandJakeVariables(self: *Executor, line: []const u8) ![]const u8 {
    const result = try expansion.expandVariables(
        self.allocator,
        &self.variables,
        self.positional_args,
        line,
    );
    // Track for cleanup
    self.expanded_strings.append(self.allocator, result) catch {};
    return result;
}

fn expandItemVariable(self: *Executor, input: []const u8, item: []const u8) []const u8 {
    const result = expansion.expandItem(self.allocator, input, item) catch return input;
    self.expanded_strings.append(self.allocator, result) catch {};
    return result;
}
```

**Memory ownership**: Caller (Executor) registers returned slices in `expanded_strings` for cleanup in `deinit()`.

**Risk**: Medium - needs careful handling of allocator ownership

---

## Phase 3: Extract Directive Parsing

### 3.1 Create `src/directive_parser.zig`

**Lines affected**: 232-431, 1678-1695 in executor.zig

**Key Design**: This module provides PURE PARSING only. No IO, no error printing, no command execution. Executor handles those.

**Extract**:

- Parse `@needs` line → structured data
- Parse `@each` items (with glob expansion)
- Parse `@cache`/`@watch` patterns
- `extractCondition()` helper
- `stripQuotes()` helper

**New file structure**:

```zig
// src/directive_parser.zig
const std = @import("std");
const glob_mod = @import("glob.zig");

pub const NeedsSpec = struct {
    command: []const u8,
    hint: ?[]const u8 = null,
    install_task: ?[]const u8 = null,
};

/// Parse @needs line into structured requirements
/// Does NOT check if commands exist - caller does that
pub fn parseNeedsLine(allocator: std.mem.Allocator, line: []const u8) ![]NeedsSpec { ... }

/// Parse items from @each directive, expanding globs
pub fn parseEachItems(allocator: std.mem.Allocator, line: []const u8) ![]const []const u8 { ... }

/// Parse file patterns from @cache/@watch directive
pub fn parseCachePatterns(allocator: std.mem.Allocator, line: []const u8) ![]const []const u8 { ... }

/// Extract condition from directive line by stripping prefix
pub fn extractCondition(line: []const u8, prefix: []const u8) []const u8 { ... }

/// Strip surrounding quotes from a string
pub fn stripQuotes(s: []const u8) []const u8 { ... }
```

**Changes to executor.zig**:

```zig
const directive_parser = @import("directive_parser.zig");

// checkNeedsDirective becomes:
fn checkNeedsDirective(self: *Executor, line: []const u8) ExecuteError!void {
    const specs = directive_parser.parseNeedsLine(self.allocator, line) catch return;
    defer self.allocator.free(specs);

    for (specs) |spec| {
        if (!system.commandExists(spec.command)) {
            // Handle missing command (print error, run install task, etc.)
            // This IO/error logic stays in Executor
        }
    }
}
```

**Note**: `handleConfirmDirective` stays in executor.zig (it's inherently IO-bound with prompts)

**Risk**: Medium - glob expansion has memory ownership implications

---

## Phase 4: Extract Display Logic

### 4.1 Create `src/display.zig`

**Lines affected**: 1314-1675 in executor.zig (~360 lines)

**Extract**:

- `isPrivateRecipe(recipe)` - check if recipe is hidden
- `listRecipes(jakefile, short_mode)` - list available recipes
- `printSummary(jakefile)` - space-separated names for scripting
- `printRecipe(stdout, recipe)` - format single recipe
- `showRecipe(jakefile, name)` - detailed recipe info

**Key Design**: Functions operate on `Jakefile`/`Recipe`, not `Executor`. No cycles.

**New file structure**:

```zig
// src/display.zig
const std = @import("std");
const compat = @import("compat.zig");
const parser = @import("parser.zig");

const Jakefile = parser.Jakefile;
const Recipe = parser.Recipe;

fn isPrivateRecipe(recipe: *const Recipe) bool { ... }

pub fn listRecipes(jakefile: *const Jakefile, short_mode: bool) void { ... }

pub fn printSummary(jakefile: *const Jakefile) void { ... }

pub fn showRecipe(jakefile: *const Jakefile, name: []const u8) bool { ... }

fn printRecipe(stdout: std.fs.File, recipe: *const Recipe) void { ... }
```

**Changes to executor.zig**:

```zig
const display = @import("display.zig");

// Wrapper methods (preserves API):
pub fn listRecipes(self: *Executor, short_mode: bool) void {
    display.listRecipes(self.jakefile, short_mode);
}

pub fn printSummary(self: *Executor) void {
    display.printSummary(self.jakefile);
}

pub fn showRecipe(self: *Executor, name: []const u8) bool {
    return display.showRecipe(self.jakefile, name);
}
```

**Alternative**: Change call sites in main.zig to call `display.*` directly, removing wrappers.

**Risk**: Low - display functions only read data, don't modify state

---

## Phase 5: Deduplicate Conditional Logic

### 5.1 Refactor `executeEachBody` to reuse `executeCommands`

**Lines affected**: 435-567, 865-1158 in executor.zig

**Problem**: Both functions implement identical `@if/@elif/@else/@end` state machines.

**Solution**: Add execution context parameter:

```zig
const ExecutionContext = struct {
    item: ?[]const u8 = null,  // For @each loops
};

fn executeCommands(self: *Executor, cmds: []const Recipe.Command, ctx: ExecutionContext) ExecuteError!void {
    // Single implementation
    // If ctx.item is set, expand {{item}} in each line
}

fn executeEachBody(self: *Executor, body: []const Recipe.Command, item: []const u8) ExecuteError!void {
    return self.executeCommands(body, .{ .item = item });
}
```

**Risk**: Medium - needs careful testing of nested conditionals

---

## Phase 6: Simplify init()

### 6.1 Split initialization concerns

**Lines affected**: 59-146 in executor.zig

**Refactor to named helper methods**:

```zig
pub fn init(allocator: std.mem.Allocator, jakefile: *const Jakefile) Executor {
    var self = Executor{
        .allocator = allocator,
        .jakefile = jakefile,
        // ... minimal field initialization
    };
    self.loadVariables();
    self.processDirectives();  // @dotenv, @export
    self.loadHooks();
    self.loadCache();
    return self;
}

fn loadVariables(self: *Executor) void { ... }
fn processDirectives(self: *Executor) void { ... }
fn loadHooks(self: *Executor) void { ... }
fn loadCache(self: *Executor) void { ... }
```

**Risk**: Low - just reorganization, no behavior change

---

## Phase 7: Update Exports

### 7.1 Add new modules to `src/root.zig`

```zig
pub const platform = @import("platform.zig");
pub const system = @import("system.zig");
pub const display = @import("display.zig");
pub const expansion = @import("expansion.zig");
pub const directive_parser = @import("directive_parser.zig");
```

---

## Testing Strategy

Each phase:

1. Run unit tests: `zig build test`
2. Run e2e tests: `jake e2e`
3. Manual smoke test: `jake -l` and `jake build`

**Test migration**:

- Keep high-level integration tests in executor.zig initially
- Add focused unit tests in new modules
- Gradually move relevant tests to new modules

---

## Files Summary

### Files to Create

| File                       | Lines | Purpose                           |
| -------------------------- | ----- | --------------------------------- |
| `src/platform.zig`         | ~40   | OS detection, recipe OS filtering |
| `src/system.zig`           | ~30   | Command existence checks          |
| `src/expansion.zig`        | ~80   | Variable/item expansion           |
| `src/directive_parser.zig` | ~200  | Pure directive parsing            |
| `src/display.zig`          | ~360  | Recipe listing/display            |

### Files to Modify

| File               | Changes                                   |
| ------------------ | ----------------------------------------- |
| `src/executor.zig` | Remove ~700 lines, add imports + wrappers |
| `src/parallel.zig` | Use platform.zig, system.zig              |
| `src/root.zig`     | Add new module exports                    |
| `src/main.zig`     | Possibly update display calls             |

---

## Expected Outcome

| File                 | Before      | After                   |
| -------------------- | ----------- | ----------------------- |
| executor.zig (code)  | ~1700 lines | ~1000 lines             |
| executor.zig (tests) | ~3550 lines | ~3550 lines (initially) |
| New modules          | -           | ~710 lines total        |

**Executor becomes**: Recipe execution engine only

- Dependency resolution
- Command execution
- Hook orchestration
- Cache checking
- IO and error handling

**Extracted concerns**:

- Platform detection → platform.zig
- System utilities → system.zig
- String expansion → expansion.zig (pure)
- Directive parsing → directive_parser.zig (pure)
- User-facing output → display.zig

---

## Key Design Principles

1. **No circular imports**: Helper modules import `std`, `parser`, `compat` etc., never `Executor`
2. **Wrapper method pattern**: Preserve `executor.foo()` API by delegating to module functions
3. **Pure functions where possible**: Parsing and expansion modules have no side effects
4. **Explicit ownership**: Memory allocation/deallocation responsibilities are clear in signatures
5. **Incremental migration**: Tests stay in executor.zig initially for safety
