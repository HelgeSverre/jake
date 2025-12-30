# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Jake is a modern command runner/build system written in Zig (requires v0.15.2+). It combines features from GNU Make and Just with clean syntax, parallel execution, and file-based dependency tracking.

## Build & Test Commands

```bash
# Build
zig build                            # Debug build
zig build -Doptimize=ReleaseFast     # Optimized build
zig build -Dtracy=true               # Build with Tracy profiler support

# Tests
zig build test                       # Unit tests
jake e2e                             # E2E tests (jake testing jake)

# Fuzz testing
zig build fuzz --fuzz                # Run coverage-guided fuzz tests

# Formatting
zig fmt src/                         # Format source files
```

### Using Jake's Own Jakefile

```bash
# Core tasks
jake build          # Build jake (default)
jake test           # Run all tests
jake lint           # Check code formatting
jake ci             # Lint + test + build
jake e2e            # End-to-end tests

# Development
jake dev            # Development build (use -w for watch mode)
jake clean          # Remove build artifacts
jake rebuild        # Clean and rebuild

# Benchmarking & Profiling
jake bench          # Benchmark vs just (requires hyperfine)
jake bench-startup  # Benchmark startup time
jake bench-parse    # Benchmark parsing different file sizes
jake profile        # CPU profiling with samply
jake leaks          # Memory leak check (macOS only)

# Fuzzing
jake fuzz           # Run coverage-guided fuzz tests

# Installation
jake install        # Install to ~/.local/bin
jake self-update    # Rebuild and reinstall
```

## Architecture

The codebase follows a compiler pipeline: Lexer → Parser → Executor

```
src/
├── main.zig          # CLI entry point, argument handling
├── args.zig          # CLI argument parser (flags: -h, -V, -l, -n, -v, -f, -w, -j, -s, -y, etc.)
├── lexer.zig         # Tokenizer with location tracking
├── parser.zig        # Builds AST (Jakefile struct with variables, recipes, directives)
├── executor.zig      # Recipe execution, dependency resolution, variable expansion
├── parallel.zig      # Thread pool for parallel execution (-j N)
├── cache.zig         # File modification tracking for file targets
├── glob.zig          # Glob pattern matching (*, **, ?, [abc])
├── watch.zig         # File watcher (FSEvents/inotify)
├── import.zig        # @import resolution with namespacing
├── env.zig           # Environment variable handling, .env loading
├── conditions.zig    # @if/@elif/@else evaluation
├── hooks.zig         # Pre/post hook execution
├── functions.zig     # Built-in functions (see list below)
├── suggest.zig       # Typo suggestions using Levenshtein distance
├── completions.zig   # Shell completion generation (bash/zsh/fish)
├── prompt.zig        # User confirmation prompts (@confirm handling)
├── compat.zig        # Zig version compatibility layer (0.14 vs 0.15+)
├── tracy.zig         # Tracy profiler integration (zero-cost when disabled)
├── root.zig          # Library exports
├── fuzz_*.zig        # Fuzz testing entry points
└── bench/            # Benchmark utilities
```

### Jake Modules

Reusable Jakefile modules in `jake/`:
- `build.jake` - Core build, test, and install tasks
- `release.jake` - Cross-platform release builds
- `perf.jake` - Performance and profiling tasks
- `web.jake` - Website-related tasks
- `editors.jake` - Editor integration setup

### Key Data Structures

The `Jakefile` struct in parser.zig is the main AST:
- `variables`: Variable assignments
- `recipes`: Task/file/simple recipe definitions with dependencies, parameters, commands
- `directives`: @dotenv, @export, @require statements
- `imports`: @import statements with optional namespacing
- `global_pre_hooks`, `global_post_hooks`, `global_on_error_hooks`

### CLI Flags

| Flag | Description |
|------|-------------|
| `-h, --help` | Show help message |
| `-V, --version` | Show version |
| `-l, --list` | List available recipes |
| `-n, --dry-run` | Print commands without executing |
| `-v, --verbose` | Show verbose output |
| `-y, --yes` | Auto-confirm all @confirm prompts |
| `-f, --jakefile FILE` | Use specified Jakefile |
| `-w, --watch [PATTERN]` | Watch files and re-run on changes |
| `-j, --jobs [N]` | Run N recipes in parallel (default: CPU count) |
| `-s, --show RECIPE` | Show detailed recipe information |
| `--short` | Output one recipe name per line (for scripting) |
| `--summary` | Print recipe names space-separated |
| `--completions [SHELL]` | Print shell completion script |
| `--install` | Install completions to user directory |
| `--uninstall` | Remove completions and config |

### Built-in Functions

Available in variable expansion `{{function(arg)}}`:
- `uppercase(s)`, `lowercase(s)`, `trim(s)` - String manipulation
- `dirname(path)`, `basename(path)` - Path components
- `extension(path)`, `without_extension(path)`, `without_extensions(path)` - File extensions
- `absolute_path(path)` - Convert to absolute path
- `home()` - User home directory
- `local_bin(name)` - Path to ~/.local/bin/name
- `shell_config()` - Path to shell config file (.bashrc, .zshrc, etc.)

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
- Compatibility: `compat.zig` provides cross-version std library compatibility

## Documentation

See the `docs/` directory for detailed guides:
- `SYNTAX.md` - Complete Jakefile syntax reference
- `TUTORIAL.md` - Getting started tutorial
- `PROFILING.md` - Performance profiling guide
- `FUZZING.md` - Fuzz testing guide

### Documentation Updates Required

When adding or modifying user-facing behavior, update ALL relevant documentation:

1. **`docs/SYNTAX.md`** - Syntax reference (condition functions, directives, built-in functions)
2. **`docs/TUTORIAL.md`** - Usage examples and patterns
3. **`site/src/content/docs/`** - Website documentation:
   - `docs/conditionals.md` - Condition function changes
   - `docs/watch-mode.md` - Watch mode changes
   - `reference/directives.md` - Directive changes
   - `reference/functions.md` - Built-in function changes
4. **`TODO.md`** - Mark completed features and update test counts

**Checklist for new features:**
- [ ] Add to relevant docs/ file
- [ ] Add to relevant site/ documentation
- [ ] Add usage example to TUTORIAL.md if applicable
- [ ] Update TODO.md to mark as complete
- [ ] Add unit tests
- [ ] Add E2E tests in `tests/e2e/`

## Commit Convention

```
feat: add new feature
fix: bug fix
docs: documentation
test: tests
refactor: code refactoring
perf: performance
```
