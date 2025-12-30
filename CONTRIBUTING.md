# Contributing to Jake

Thank you for your interest in contributing to Jake!

## Development Setup

1. Install [Zig](https://ziglang.org/) v0.15.2 or later
2. Clone the repository:
   ```bash
   git clone https://github.com/HelgeSverre/jake.git
   cd jake
   ```
3. Build and test:
   ```bash
   jake ci          # Lint, test, and build
   ```

   Or without jake installed:
   ```bash
   zig build && zig build test
   ```

## Project Structure

```
jake/
├── src/
│   ├── main.zig          # CLI entry point
│   ├── root.zig          # Library exports
│   ├── lexer.zig         # Tokenizer
│   ├── parser.zig        # AST builder
│   ├── executor.zig      # Recipe execution
│   ├── parallel.zig      # Parallel execution
│   ├── cache.zig         # File change detection
│   ├── glob.zig          # Glob pattern matching
│   ├── import.zig        # Import resolution
│   ├── watch.zig         # File watcher
│   ├── env.zig           # Environment handling
│   ├── conditions.zig    # Conditional logic
│   └── hooks.zig         # Pre/post hooks
├── jake/                 # Reusable jake modules
│   ├── build.jake        # Core build tasks
│   ├── release.jake      # Release automation
│   └── perf.jake         # Performance tasks
├── tests/e2e/            # E2E tests
├── docs/                 # Documentation
│   ├── SYNTAX.md         # Syntax reference
│   └── TUTORIAL.md       # Getting started
└── CLAUDE.md             # AI assistant instructions
```

## Common Tasks

```bash
# Development
jake build           # Debug build
jake test            # Run unit tests
jake e2e             # Run E2E tests
jake lint            # Check formatting
jake format          # Auto-format code
jake ci              # Full CI pipeline (lint + test + build)

# Watch mode (auto-rebuild on changes)
jake dev -w

# Benchmarking & Profiling
jake bench           # Compare with just
jake perf.bench-internal  # Internal benchmarks
jake profile         # CPU profiling with samply

# Clean up
jake clean           # Remove build artifacts
jake prune           # Remove all caches
```

## Running Tests

```bash
jake ci              # Full test suite (recommended)
jake test            # Unit tests only
jake e2e             # E2E tests only
jake fuzz            # Fuzz testing
```

## Code Style

- Follow Zig's standard style
- Run `jake format` (or `zig fmt src/`) before committing
- Keep functions focused and well-documented
- Add tests for new features

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run the full test suite: `jake ci && jake e2e`
5. Commit with a clear message (see below)
6. Push and create a Pull Request

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add watch mode for automatic rebuilds
fix: handle glob patterns with special characters
docs: update user guide with new examples
test: add E2E tests for import system
refactor: simplify lexer token handling
perf: optimize parallel execution scheduling
```

## Updating Documentation

When adding or modifying user-facing features, update the relevant docs:

1. `docs/SYNTAX.md` - Syntax reference
2. `docs/TUTORIAL.md` - Usage examples
3. `site/src/content/docs/` - Website documentation

See `CLAUDE.md` for the full documentation checklist.

## Reporting Issues

When reporting bugs, please include:
- Jake version (`jake --version`)
- Operating system and architecture
- Minimal Jakefile to reproduce the issue
- Expected vs actual behavior
- Full error message

## Feature Requests

We welcome feature ideas! Please:
- Check existing issues first
- Describe the use case clearly
- Provide example syntax if applicable

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
