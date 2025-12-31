# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **"Did you mean?" Suggestions**
  - Unknown flag typos now suggest similar flags
  - `--vrsbose` → `Did you mean '--verbose'?`
  - Uses Levenshtein distance from `suggest.zig`

### Fixed

- Color.zig `Theme.init()` now correctly initializes color detection
- ColoredText format method updated for Zig 0.15 compatibility

## [0.4.0] - 2025-12-30

### Added

- **@launch Directive**
  - Open files and URLs from Jakefiles with `@launch`
  - Built-in `launch()` function for use in commands
  - Cross-platform support using `open` (macOS), `xdg-open` (Linux), `start` (Windows)

- **Platform Detection Conditions**
  - `os()` condition: check `macos`, `linux`, `windows`
  - `arch()` condition: check `x86_64`, `aarch64`
  - Enables platform-specific recipe commands

- **CLI Improvements**
  - Global flags now work after recipe name (e.g., `jake build -v`)
  - More flexible argument ordering

- **Jake Modules**
  - Reusable Jakefile modules in `jake/` directory
  - `build.jake` - Core build, test, and install tasks
  - `release.jake` - Cross-platform release builds
  - `perf.jake` - Performance and profiling tasks
  - `web.jake` - Website-related tasks
  - `editors.jake` - Editor integration setup

- **Watch Mode Improvements**
  - Better pattern parsing with feedback
  - Improved watch mode testing fixtures

### Fixed

- `dirname("/")` edge case now returns "/" correctly
- Editor syntax highlighters updated for `launch()` function
- GitHub URLs updated to HelgeSverre organization
- Docker completions test uses Zig 0.15.2

### Changed

- Removed legacy corpus, lib modules, and fuzz tests
- Improved hook execution and error handling
- Refactored functions, glob, and lexer modules

## [0.3.0] - 2025-12-30

### Added

- **Shell Completions**
  - Generate shell completions for bash, zsh, and fish (`jake --completions <shell>`)
  - Auto-install/uninstall commands (`jake --completions --install`)
  - Smart zsh environment detection (Oh-My-Zsh, Homebrew, vanilla)
  - Machine-readable recipe list (`jake --summary`)

- **CLI Improvements**
  - `jake --list --short` for pipeable one-per-line recipe names
  - `jake --show <recipe>` to display recipe details (dependencies, commands, metadata)
  - Typo suggestions using Levenshtein distance ("Did you mean: build?")

- **Recipe-Level @needs Directive**
  - Check command/binary requirements before recipe execution
  - `@needs git npm docker` validates tools exist in PATH

- **Built-in Functions**
  - System path functions: `home()`, `local_bin()`, `shell_config()`
  - String functions: `uppercase()`, `lowercase()`, `trim()`
  - Path functions: `dirname()`, `basename()`, `extension()`, `without_extension()`, `without_extensions()`

- **Runtime Conditions**
  - `@if`, `@elif`, `@else`, `@end` with condition functions
  - Condition functions: `env()`, `exists()`, `eq()`, `neq()`, `os()`, `arch()`

- **Editor Support**
  - Vim syntax highlighting plugin (`editors/vim-jake/`)
  - IntelliJ Platform plugin with dynamic TextMate bundle (`editors/intellij-jake/`)

- **Recipe Metadata**
  - Location and origin tracking for recipes
  - Recipe source file tracking for imports

- **Documentation Website**
  - New documentation site built with Astro Starlight
  - Feature deep-dives and CLI branding guide

### Fixed

- Zsh completion syntax and array handling
- Private recipes with dot prefix now filtered from listings
- Zig 0.14/0.15 compatibility layer for CI

### Changed

- Migrated E2E tests to `tests/e2e/` directory
- Updated to ztracy library with new API
- Refactored argument parsing with dedicated args module

### CI/CD

- Bumped actions/upload-artifact from 4 to 6
- Bumped actions/download-artifact from 4 to 7
- Bumped mlugg/setup-zig from 1 to 2
- Bumped softprops/action-gh-release from 1 to 2
- Bumped actions/stale from 9 to 10

## [0.2.0] - 2025-12-28

### Added

- **@quiet Directive** - Suppress command echo for entire recipe
- **@confirm Directive** - Interactive confirmation prompts with `--yes` flag support
- **Environment Validation** - `@require` checks env vars exist before execution
- **Command Dependency Checking** - `@needs` validates commands exist in PATH

### Fixed

- Shell/working_dir assignment in parser
- Windows compatibility for environment variable access
- Zig 0.14-compatible std.io API calls

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

[0.4.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.4.0
[0.3.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.3.0
[0.2.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.2.0
[0.1.0]: https://github.com/HelgeSverre/jake/releases/tag/v0.1.0
