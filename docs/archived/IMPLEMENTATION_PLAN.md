# Jake Implementation Plan

## Multi-Agent Coordination Strategy for Feature Development

This document provides a comprehensive implementation plan for the remaining jake features,
organized by dependency relationships and parallelization opportunities.

---

## Current State Analysis

### MVP Components (Complete)

- **Lexer** (`src/lexer.zig`): Tokenizes Jakefile syntax, includes keywords for future features
- **Parser** (`src/parser.zig`): Builds AST with Recipe, Variable, Directive structures
- **Executor** (`src/executor.zig`): Sequential dependency resolution, variable expansion, shell execution
- **Cache** (`src/cache.zig`): SHA256 content hashing, basic staleness detection

### Architecture Observations

1. Lexer already has tokens for: `@if`, `@elif`, `@else`, `@end`, `@import`, `@dotenv`, `@require`, `@watch`, `@cache`, `@needs`, `@confirm`, `@each`
2. Parser has partial structures for directives but limited implementation
3. Executor runs dependencies sequentially (no parallelism yet)
4. Cache has `isGlobStale()` stub returning `true` for glob patterns

---

## Feature Dependency Graph

```
                                    [Foundation Layer]
                                           |
            +------------------------------+------------------------------+
            |                              |                              |
    [1] Glob Pattern              [13] Better Error             [14] Documentation
        Matching                       Messages                      Generation
            |                              |
            +------------------------------+
                           |
                    [Cache Improvements]
                           |
            +--------------+--------------+
            |                             |
    [2] Watch Mode               [3] Parallel Execution
            |                             |
            |                    +--------+--------+
            |                    |                 |
            |            [11] Workspace      [12] Remote Cache
            |                Support
            |
            +--------------------+--------------------+
            |                    |                    |
    [4] Dotenv Loading    [5] Required Env     [6] Conditional Logic
            |                    |                    |
            +--------------------+--------------------+
                                 |
                    +------------+------------+
                    |                         |
            [7] Import System          [8] Hooks
                    |                         |
                    +------------+------------+
                                 |
                    +------------+------------+
                    |                         |
            [9] Interactive           [10] Container
                Prompts                  Execution
```

---

## Parallelization Groups

### PHASE 1: Foundation (No Dependencies - Maximum Parallelism)

These features can be implemented completely independently and in parallel.

| Feature                    | Complexity | Est. Time | Agent Assignment |
| -------------------------- | ---------- | --------- | ---------------- |
| [1] Glob Pattern Matching  | Medium     | 2-3 days  | Agent-A          |
| [13] Better Error Messages | Low        | 1-2 days  | Agent-B          |
| [14] Recipe Documentation  | Low        | 1-2 days  | Agent-C          |

**Coordination Notes:**

- All modify different parts of the codebase
- Zero inter-dependencies
- Can proceed simultaneously with no synchronization

---

### PHASE 2: Core Enhancements (Depends on Phase 1)

These features build on glob patterns and error handling.

| Feature                | Depends On            | Complexity | Est. Time | Agent Assignment |
| ---------------------- | --------------------- | ---------- | --------- | ---------------- |
| [2] Watch Mode         | [1] Glob              | Medium     | 2-3 days  | Agent-A          |
| [3] Parallel Execution | [1] Glob, [13] Errors | High       | 3-4 days  | Agent-D          |
| [4] Dotenv Loading     | [13] Errors           | Low        | 1 day     | Agent-B          |
| [5] Required Env Vars  | [13] Errors           | Low        | 1 day     | Agent-C          |

**Coordination Notes:**

- [2] and [3] can run in parallel after [1] completes
- [4] and [5] can run in parallel after [13] completes
- Agent-A continues with watch mode after glob completion
- Agent-D picks up parallel execution (fresh perspective on concurrency)

---

### PHASE 3: Logic & Modularity (Depends on Phase 2)

These features require environment and error handling infrastructure.

| Feature               | Depends On  | Complexity | Est. Time | Agent Assignment |
| --------------------- | ----------- | ---------- | --------- | ---------------- |
| [6] Conditional Logic | [4], [5]    | Medium     | 2-3 days  | Agent-B          |
| [7] Import System     | [13] Errors | High       | 3-4 days  | Agent-C          |

**Coordination Notes:**

- [6] requires environment variables to test conditions like `@if env.DEBUG`
- [7] can start earlier if parser modifications are isolated
- Both can run in parallel

---

### PHASE 4: Advanced Features (Depends on Phase 3)

Higher-level features building on the complete foundation.

| Feature                | Depends On                         | Complexity | Est. Time | Agent Assignment |
| ---------------------- | ---------------------------------- | ---------- | --------- | ---------------- |
| [8] Hooks              | [7] Import (for hook organization) | Medium     | 2 days    | Agent-A          |
| [11] Workspace Support | [3] Parallel, [7] Import           | High       | 3-4 days  | Agent-D          |
| [12] Remote Cache      | [1] Glob, [3] Parallel             | High       | 3-4 days  | Agent-E          |

**Coordination Notes:**

- [8] and [11] can start when dependencies complete
- [12] is architecturally independent but benefits from parallel execution

---

### PHASE 5: Interactive & Isolation (Depends on Phase 4)

Final advanced features requiring stable core.

| Feature                  | Depends On                | Complexity | Est. Time | Agent Assignment |
| ------------------------ | ------------------------- | ---------- | --------- | ---------------- |
| [9] Interactive Prompts  | [6] Conditional           | Low        | 1-2 days  | Agent-B          |
| [10] Container Execution | [8] Hooks (for @on_error) | High       | 3-4 days  | Agent-C          |

**Coordination Notes:**

- [9] is simpler, can complete quickly
- [10] is complex but relatively isolated

---

## Detailed Feature Specifications

### [1] Glob Pattern Matching

**Files to Modify:** `src/cache.zig`, new `src/glob.zig`

**Implementation:**

```zig
// src/glob.zig
pub const Glob = struct {
    pattern: []const u8,

    pub fn match(self: Glob, path: []const u8) bool { ... }
    pub fn expandFiles(self: Glob, allocator: Allocator) ![][]const u8 { ... }
};

// Patterns to support:
// - * matches any characters except /
// - ** matches any characters including /
// - ? matches single character
// - [abc] matches character class
```

**Integration Points:**

- `cache.isGlobStale()` - replace stub with real implementation
- File recipe dependency resolution
- Watch mode file discovery

---

### [2] Watch Mode (@watch directive)

**Files to Modify:** `src/executor.zig`, new `src/watcher.zig`

**Implementation:**

```zig
// src/watcher.zig
pub const Watcher = struct {
    paths: []const []const u8,
    callback: *const fn() void,

    pub fn start(self: *Watcher) !void { ... }  // Uses kqueue/inotify/FSEvents
    pub fn stop(self: *Watcher) void { ... }
};
```

**CLI Integration:**

- `jake build --watch` flag
- `@watch src/**/*.ts` directive in recipes

---

### [3] Parallel Execution

**Files to Modify:** `src/executor.zig`

**Implementation:**

```zig
pub const ParallelExecutor = struct {
    thread_pool: ThreadPool,
    dependency_graph: DependencyGraph,
    completed: AtomicSet,

    pub fn executeParallel(self: *ParallelExecutor, targets: []const []const u8) !void {
        // Topological sort for correct ordering
        // Spawn threads for independent tasks
        // Barrier synchronization at dependency boundaries
    }
};
```

**Key Algorithms:**

- Topological sort for dependency ordering
- Critical path analysis for optimal scheduling
- Lock-free completion tracking

---

### [4] Dotenv Loading (@dotenv)

**Files to Modify:** `src/executor.zig`, new `src/dotenv.zig`

**Implementation:**

```zig
// src/dotenv.zig
pub fn loadDotenv(allocator: Allocator, path: []const u8) !StringHashMap([]const u8) {
    // Parse KEY=value pairs
    // Handle quoted values, multiline, comments
    // Support variable expansion within .env
}
```

**Behavior:**

- Auto-load `.env` if `@dotenv` directive present (no args)
- `@dotenv .env.local` for explicit path
- Variables available to all recipes

---

### [5] Required Environment Variables (@require)

**Files to Modify:** `src/executor.zig`

**Implementation:**

```zig
fn validateRequiredEnv(self: *Executor) !void {
    for (self.jakefile.directives) |d| {
        if (d.kind == .require) {
            for (d.args) |var_name| {
                if (std.process.getEnvVarOwned(self.allocator, var_name)) |_| {
                    // OK
                } else {
                    return error.MissingRequiredEnv;
                }
            }
        }
    }
}
```

**Error Message:**

```
error: Required environment variable 'AWS_ACCESS_KEY_ID' is not set
  --> Jakefile:3:1
   |
 3 | @require AWS_ACCESS_KEY_ID
   | ^^^^^^^^^^^^^^^^^^^^^^^^^^
   |
hint: Set this variable in your shell or add it to .env
```

---

### [6] Conditional Logic (@if/@elif/@else/@end)

**Files to Modify:** `src/parser.zig`, `src/executor.zig`

**Implementation:**

```zig
// Parser creates conditional blocks in AST
pub const ConditionalBlock = struct {
    condition: Condition,
    commands: []const Command,
    elif_blocks: []const ConditionalBlock,
    else_commands: []const Command,
};

pub const Condition = union(enum) {
    os_check: []const u8,      // @if os == "macos"
    env_check: []const u8,     // @if env.DEBUG
    cmd_check: []const u8,     // @if which docker
    file_exists: []const u8,   // @if exists ./config.json
};
```

**Supported Conditions:**

- `os == "macos" | "linux" | "windows"`
- `arch == "x86_64" | "aarch64"`
- `env.VAR_NAME` (truthy check)
- `env.VAR_NAME == "value"`
- `exists path/to/file`
- `which command_name`

---

### [7] Import System (@import)

**Files to Modify:** `src/parser.zig`, `src/executor.zig`, new `src/import.zig`

**Implementation:**

```zig
// src/import.zig
pub const ImportResolver = struct {
    base_path: []const u8,
    loaded: StringHashMap(*Jakefile),

    pub fn resolve(self: *ImportResolver, import_path: []const u8) !*Jakefile { ... }
    pub fn mergeRecipes(self: *ImportResolver, into: *Jakefile, from: *Jakefile, namespace: ?[]const u8) !void { ... }
};
```

**Syntax:**

```jake
@import ./scripts/docker.jake           # Imports recipes directly
@import ./scripts/deploy.jake as deploy # Namespaced: deploy.production
```

**Circular Import Detection:**

- Track import stack during resolution
- Error with clear cycle path if detected

---

### [8] Hooks (@before/@after/@on_error)

**Files to Modify:** `src/parser.zig`, `src/executor.zig`

**Implementation:**

```zig
pub const Hook = struct {
    kind: HookKind,
    target_recipe: []const u8,
    commands: []const Command,
};

pub const HookKind = enum { before, after, on_error };

// In executor:
fn executeWithHooks(self: *Executor, recipe: *const Recipe) !void {
    // Run @before hooks
    for (self.getHooks(.before, recipe.name)) |hook| {
        try self.runCommands(hook.commands);
    }

    // Run recipe
    self.runCommands(recipe.commands) catch |err| {
        // Run @on_error hooks
        for (self.getHooks(.on_error, recipe.name)) |hook| {
            self.runCommands(hook.commands) catch {};
        }
        return err;
    };

    // Run @after hooks
    for (self.getHooks(.after, recipe.name)) |hook| {
        try self.runCommands(hook.commands);
    }
}
```

---

### [9] Interactive Prompts (@prompt/@confirm)

**Files to Modify:** `src/executor.zig`, new `src/prompt.zig`

**Implementation:**

```zig
// src/prompt.zig
pub fn prompt(message: []const u8, default: ?[]const u8) ![]const u8 {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    try stdout.print("{s}", .{message});
    if (default) |d| try stdout.print(" [{s}]", .{d});
    try stdout.print(": ", .{});

    const line = try stdin.reader().readUntilDelimiterAlloc(allocator, '\n', 1024);
    return if (line.len == 0 and default != null) default.? else line;
}

pub fn confirm(message: []const u8) !bool {
    // Returns true for y/Y/yes/YES, false otherwise
}
```

**Non-Interactive Mode:**

- `jake deploy --yes` to auto-confirm
- Error if prompt required but stdin is not a TTY

---

### [10] Container/Sandbox Execution (@container)

**Files to Modify:** `src/executor.zig`, new `src/container.zig`

**Implementation:**

```zig
// src/container.zig
pub const ContainerRunner = struct {
    image: []const u8,
    mounts: []const Mount,
    env: StringHashMap([]const u8),

    pub fn runCommand(self: *ContainerRunner, cmd: []const u8) !void {
        // Build docker/podman command
        // docker run --rm -v $(pwd):/work -w /work {image} sh -c {cmd}
    }
};
```

**Features:**

- Auto-detect docker vs podman
- Mount current directory
- Pass through environment variables
- Cache container images

---

### [11] Workspace/Monorepo Support (@workspace/@each)

**Files to Modify:** `src/parser.zig`, `src/executor.zig`, new `src/workspace.zig`

**Implementation:**

```zig
// src/workspace.zig
pub const Workspace = struct {
    root: []const u8,
    packages: []const Package,

    pub const Package = struct {
        name: []const u8,
        path: []const u8,
        jakefile: ?*Jakefile,
    };

    pub fn discover(root: []const u8, pattern: []const u8) !Workspace { ... }
    pub fn runInAll(self: *Workspace, recipe: []const u8, parallel: bool) !void { ... }
};
```

**Syntax:**

```jake
@workspace packages/*

task test:
    @each package
        cd {{package}} && npm test
```

---

### [12] Remote Cache Support

**Files to Modify:** `src/cache.zig`, new `src/remote_cache.zig`

**Implementation:**

```zig
// src/remote_cache.zig
pub const RemoteCache = struct {
    backend: Backend,

    pub const Backend = union(enum) {
        s3: S3Backend,
        gcs: GcsBackend,
        http: HttpBackend,
    };

    pub fn get(self: *RemoteCache, key: []const u8) !?[]const u8 { ... }
    pub fn put(self: *RemoteCache, key: []const u8, value: []const u8) !void { ... }
};
```

**Configuration:**

```jake
@cache remote s3://bucket/jake-cache
@cache remote gs://bucket/jake-cache
@cache remote https://cache.example.com/v1
```

---

### [13] Better Error Messages with Line Numbers

**Files to Modify:** `src/lexer.zig`, `src/parser.zig`, `src/executor.zig`

**Implementation:**

```zig
// Add to Token
pub const Token = struct {
    tag: Tag,
    loc: Loc,
    line: u32,      // ADD
    column: u32,    // ADD
};

// Error display
pub fn formatError(source: []const u8, loc: Loc, message: []const u8) void {
    // Find line start/end
    // Print: "error: {message}"
    // Print: "  --> Jakefile:{line}:{col}"
    // Print: "   |"
    // Print: " {line} | {source_line}"
    // Print: "   | {caret_underline}"
}
```

**Example Output:**

```
error: Unexpected token ']', expected identifier
  --> Jakefile:15:23
   |
15 | build: [compile, test, ]
   |                       ^
   |
```

---

### [14] Recipe Documentation/Help Generation

**Files to Modify:** `src/parser.zig`, `src/executor.zig`

**Implementation:**

```zig
// Parse doc comments (# comments before recipe)
fn parseDocComment(self: *Parser) ?[]const u8 {
    var comments: ArrayList(u8) = .{};
    while (self.current.tag == .comment) {
        comments.appendSlice(self.slice(self.current)[1..]);  // Skip #
        self.advance();
        self.skipNewlines();
    }
    return if (comments.items.len > 0) comments.toOwnedSlice() else null;
}
```

**CLI Integration:**

- `jake --help build` shows doc comment for build recipe
- `jake --list` shows first line of doc comment

---

## Execution Timeline (Gantt-style)

```
Week 1:
  Agent-A: [====== Glob Patterns ======]
  Agent-B: [== Error Messages ==]
  Agent-C: [== Documentation ==]

Week 2:
  Agent-A: [======= Watch Mode =======]
  Agent-B: [= Dotenv =][== Required Env ==]
  Agent-C: [== Documentation ==][===== Import System =====]
  Agent-D: [========== Parallel Execution ==========]

Week 3:
  Agent-A: [=== Hooks ===]
  Agent-B: [======= Conditional Logic =======]
  Agent-C: [===== Import System =====]
  Agent-D: [========== Parallel Execution ==========]

Week 4:
  Agent-A: [========== Workspace Support ==========]
  Agent-B: [= Prompts =]
  Agent-C: [======== Container Execution ========]
  Agent-E: [========== Remote Cache ==========]

Week 5:
  Agent-A: [== Workspace ==]
  Agent-C: [== Container ==]
  Agent-E: [== Remote Cache ==]
  All:     [Integration Testing & Polish]
```

---

## Synchronization Points

### Checkpoint 1: End of Week 1

- Glob patterns functional
- Error messages improved
- Documentation generation working
- **Gate:** All Phase 1 features pass tests

### Checkpoint 2: End of Week 2

- Watch mode basic functionality
- Dotenv loading complete
- Required env validation complete
- **Gate:** Environment system integration tested

### Checkpoint 3: End of Week 3

- Parallel execution stable
- Conditional logic complete
- Import system basic functionality
- **Gate:** Can run complex multi-file Jakefiles

### Checkpoint 4: End of Week 4

- All advanced features complete
- Integration tests passing
- **Gate:** Full feature parity with IDEA.md

### Final: Week 5

- Performance optimization
- Edge case handling
- Documentation
- Release preparation

---

## Risk Mitigation

### High-Risk Features

1. **Parallel Execution [3]**
   - Risk: Race conditions, deadlocks
   - Mitigation: Extensive testing, conservative locking initially
   - Fallback: Sequential execution remains default

2. **Container Execution [10]**
   - Risk: Platform-specific issues, Docker API changes
   - Mitigation: Abstract container runtime, test on multiple platforms
   - Fallback: Document as experimental

3. **Remote Cache [12]**
   - Risk: Network failures, auth complexity
   - Mitigation: Graceful degradation to local cache
   - Fallback: S3-only initially

### Dependency Risks

- If [1] Glob delays: [2] Watch and [3] Parallel can start with file-list fallback
- If [3] Parallel delays: [11] Workspace works with sequential execution
- If [7] Import delays: [8] Hooks can work without namespacing

---

## Testing Strategy

### Unit Tests (Per Feature)

- Each feature includes comprehensive unit tests
- Test files: `src/glob_test.zig`, `src/watcher_test.zig`, etc.

### Integration Tests

```
tests/
  integration/
    01_basic_recipe.jake
    02_file_deps.jake
    03_parallel_deps.jake
    04_dotenv.jake
    05_conditional.jake
    06_imports/
    07_watch.jake
    08_workspace/
    09_containers.jake
```

### Performance Benchmarks

- Measure parallel vs sequential execution time
- Cache hit/miss ratios
- Watch mode CPU usage
- Large monorepo workspace traversal

---

## Communication Protocol

### Daily Standups

- Report: completed, in-progress, blocked
- Flag dependency conflicts immediately

### Code Review Requirements

- Features affecting parser.zig: 2 reviewers
- Features affecting executor.zig: 2 reviewers
- New modules: 1 reviewer

### Merge Order

- Phase 1 features can merge independently
- Phase 2+ requires phase dependencies merged first
- Integration branch for cross-feature testing

---

## Summary

**Total Features:** 14
**Estimated Duration:** 5 weeks with 5 agents
**Maximum Parallelism:** 3 agents in Phase 1, 4 agents in Phase 2-4
**Critical Path:** Glob -> Parallel -> Workspace (longest chain)

The implementation plan maximizes parallelization by:

1. Starting all independent features simultaneously
2. Assigning features to minimize handoff delays
3. Allowing agents to continue with related features
4. Building synchronization checkpoints for integration

**Coordination Efficiency Target:** 96% (minimal blocking between agents)
**Deadlock Prevention:** Explicit dependency ordering eliminates circular waits
**Fault Tolerance:** Each feature can be delivered independently if others slip
