# Jake

**A modern command runner with file-based dependency tracking**

<p align="center">
  <a href="https://github.com/HelgeSverre/jake/actions/workflows/ci.yml"><img src="https://github.com/HelgeSverre/jake/actions/workflows/ci.yml/badge.svg?v=1767148270" alt="CI"></a>
  <a href="https://github.com/HelgeSverre/jake/releases"><img src="https://img.shields.io/github/v/release/HelgeSverre/jake?style=flat-square&v=1767148270" alt="Release"></a>
  <img src="https://img.shields.io/badge/lang-Zig-F7A41D?style=flat-square&logo=zig&v=1767148270" alt="Zig">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square&v=1767148270" alt="MIT License">
</p>

> [!WARNING]
> This project is still a work in progress and not yet production ready.

<img src="https://jakefile.dev/og-image.png" alt="Jake">

The best of **Make** and **Just**, combined. Clean syntax, parallel execution, glob patterns, and smart rebuilds.

**[Documentation](https://jakefile.dev)** · **[Installation](#installation)** · **[Quick Start](#quick-start)**

---

## Why Jake?

| Feature | Make | Just | Jake |
|---------|------|------|------|
| File-based dependencies | ✅ | ❌ | ✅ |
| Clean syntax | ❌ | ✅ | ✅ |
| Parallel execution | ✅ | ❌ | ✅ |
| Glob patterns | ❌ | ❌ | ✅ |
| Import system | ❌ | ✅ | ✅ |
| Conditionals | ❌ | ✅ | ✅ |
| Pre/post hooks | ❌ | ❌ | ✅ |
| .env loading | ❌ | ✅ | ✅ |

## Installation

### Pre-built Binaries

Download from [Releases](https://github.com/HelgeSverre/jake/releases):

| Platform | Download |
|----------|----------|
| Linux x86_64 | `jake-linux-x86_64` |
| Linux ARM64 | `jake-linux-aarch64` |
| macOS Intel | `jake-macos-x86_64` |
| macOS Apple Silicon | `jake-macos-aarch64` |
| Windows | `jake-windows-x86_64.exe` |

### From Source

```bash
# Requires Zig 0.15.2+
git clone https://github.com/HelgeSverre/jake.git
cd jake
zig build -Doptimize=ReleaseFast
cp zig-out/bin/jake ~/.local/bin/
```

## Quick Start

Create a `Jakefile` in your project:

```jake
# Variables
app = "myapp"
version = "1.0.0"

# Load .env file
@dotenv

# Default task
@default
@desc "Build the application"
task build:
    echo "Building {{app}} v{{version}}..."
    mkdir -p dist

@desc "Run tests"
task test: [build]
    echo "Running tests..."

task clean:
    rm -rf dist

# File target - rebuilds only when sources change
file dist/bundle.js: src/*.js
    cat src/*.js > dist/bundle.js
```

Run it:

```bash
jake              # Run default task
jake test         # Run tests (builds first)
jake -l           # List available tasks
jake -w build     # Watch mode - rebuild on changes
jake -j4 all      # Parallel execution
```

## Features

- **[Task recipes](GUIDE.md#task-recipes)** - Define commands with parameters and dependencies
- **[File recipes](GUIDE.md#file-recipes)** - Rebuild only when sources change
- **[Glob patterns](GUIDE.md#glob-patterns)** - Watch `src/**/*.ts` for changes
- **[Imports](GUIDE.md#imports)** - Split Jakefiles into modules with namespacing
- **[Conditionals](GUIDE.md#conditionals)** - Branch on environment or context
- **[Hooks](GUIDE.md#hooks)** - Pre/post execution callbacks
- **[Validation](GUIDE.md#validation)** - Require commands and env vars before running

## CLI Reference

```
jake [OPTIONS] [RECIPE]

OPTIONS:
  -h, --help              Show help
  -V, --version           Show version
  -l, --list              List recipes
  -s, --show RECIPE       Show detailed recipe info
  -n, --dry-run           Print without executing
  -v, --verbose           Verbose output
  -y, --yes               Auto-confirm prompts
  -f, --jakefile FILE     Use specified Jakefile
  -w, --watch             Watch and re-run on changes
  -j, --jobs N            Parallel jobs (default: CPU count)
      --completions SHELL Generate shell completions
```

**Typo suggestions:** Mistype a recipe name? Jake suggests corrections:
```
$ jake buidl
error: Recipe 'buidl' not found
Did you mean: build?
```

## Shell Completions

```bash
jake --completions --install  # Auto-detect and install
```

See the [User Guide](GUIDE.md#shell-completions) for manual setup options.

## Documentation

- **[User Guide](GUIDE.md)** - Complete reference
- **[Website](https://jakefile.dev)** - Documentation and examples

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

MIT License - see [LICENSE](LICENSE.md)

---

<p align="center">
  Built with Zig · Inspired by Make & Just
</p>
