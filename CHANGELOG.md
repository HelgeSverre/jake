# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-12-28

### Added

- **Core Engine**
  - Lexer with tokenization for Jakefile syntax
  - Parser with AST generation and error reporting
  - Executor with dependency resolution and recipe execution
  - File hash cache for incremental builds

- **Task Features**
  - Task recipes with parameters and default values
  - File recipes with glob pattern support (`src/**/*.ts`)
  - Dependency tracking between tasks (`task build: [clean, compile]`)
  - Parallel execution with configurable job count (`-j N`)
  - Watch mode for automatic re-execution (`-w`)

- **Environment & Configuration**
  - `.env` file loading with `@dotenv` directive
  - Environment variable export with `@export`
  - Variable interpolation with `{{variable}}` syntax

- **Modularity**
  - Import system with `@import` directive
  - Namespaced imports with `@import "file.jake" as name`

- **Hooks & Conditionals**
  - Global and per-recipe `@pre` and `@post` hooks
  - Conditional execution with `@if`, `@else`, `@end`

- **CLI**
  - `jake` - Run default task
  - `jake <recipe>` - Run specific recipe
  - `jake -l` / `--list` - List available recipes
  - `jake -n` / `--dry-run` - Show what would run
  - `jake -v` / `--verbose` - Verbose output
  - `jake -f <file>` - Use alternate Jakefile
  - `jake -j N` - Parallel jobs
  - `jake -w` - Watch mode

- **Documentation**
  - Comprehensive user guide
  - Contributing guidelines
  - Example Jakefiles for common patterns

- **CI/CD**
  - GitHub Actions workflows for CI and releases
  - Multi-platform build support (Linux, macOS, Windows)
  - Cross-compilation for x86_64 and aarch64

[0.1.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.1.0
