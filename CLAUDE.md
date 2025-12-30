# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Jake is a modern command runner/build system written in Zig (requires v0.15.2+). It combines features from GNU Make and Just with clean syntax, parallel execution, and file-based dependency tracking.

## Build & Test Commands

```bash
# Build
zig build                            # Debug build
zig build -Doptimize=ReleaseFast     # Optimized build
zig build run                        # Build and run

# Tests
zig build test                       # Unit tests
bash tests/e2e_test.sh               # E2E tests

# Formatting
zig fmt src/                         # Format source files
```

### Using Jake's Own Jakefile

```bash
jake build          # Build jake
jake test           # Run all tests
jake ci             # Lint + test + build
jake bench          # Benchmark vs just
jake profile        # CPU profiling with samply
jake fuzz           # Fuzz parser
```

## Architecture

The codebase follows a compiler pipeline: Lexer → Parser → Executor

```
src/
├── main.zig        # CLI entry point, argument handling
├── args.zig        # CLI argument parser (flags: -h, -V, -l, -n, -v, -f, -w, -j, -s, etc.)
├── lexer.zig       # Tokenizer with location tracking
├── parser.zig      # Builds AST (Jakefile struct with variables, recipes, directives)
├── executor.zig    # Recipe execution, dependency resolution, variable expansion
├── parallel.zig    # Thread pool for parallel execution (-j N)
├── cache.zig       # File modification tracking for file targets
├── glob.zig        # Glob pattern matching (*, **, ?, [abc])
├── watch.zig       # File watcher (FSEvents/inotify)
├── import.zig      # @import resolution with namespacing
├── env.zig         # Environment variable handling, .env loading
├── conditions.zig  # @if/@elif/@else evaluation
├── hooks.zig       # Pre/post hook execution
├── functions.zig   # Built-in functions (uppercase, dirname, basename, etc.)
├── suggest.zig     # Typo suggestions using Levenshtein distance
├── completions.zig # Shell completion generation
└── root.zig        # Library exports
```

### Key Data Structures

The `Jakefile` struct in parser.zig is the main AST:
- `variables`: Variable assignments
- `recipes`: Task/file/simple recipe definitions with dependencies, parameters, commands
- `directives`: @dotenv, @export, @require statements
- `imports`: @import statements with optional namespacing
- `global_pre_hooks`, `global_post_hooks`, `global_on_error_hooks`

### Execution Flow

1. Args parsed → Jakefile located
2. Lexer tokenizes source
3. Parser builds AST
4. Executor initializes (loads variables, env, validates @require)
5. Dependencies resolved via topological sort
6. Pre-hooks → Commands → Post-hooks (or on_error)
7. Cache updated for file targets

## Code Patterns

- Memory: Uses `std.mem.Allocator`, structures implement `deinit()` for cleanup
- Errors: Explicit error unions (`!Type`), dedicated error sets per module
- Tests: Embedded in source files with `test "description" { ... }` blocks

## Commit Convention

```
feat: add new feature
fix: bug fix
docs: documentation
test: tests
refactor: code refactoring
perf: performance
```
