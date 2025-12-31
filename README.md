# Jake

[![CI](https://github.com/HelgeSverre/jake/actions/workflows/ci.yml/badge.svg)](https://github.com/HelgeSverre/jake/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/HelgeSverre/jake?style=flat-square)](https://github.com/HelgeSverre/jake/releases)
![Zig](https://img.shields.io/badge/lang-Zig-F7A41D?style=flat-square&logo=zig)
![MIT License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

![Jake](https://jakefile.dev/og-image.png)

The best of **Make** and **Just**, combined. Clean syntax, parallel execution, glob patterns, and smart rebuilds.

**[Documentation](https://jakefile.dev)** · **[Installation](#installation)** · **[Quick Start](#quick-start)** · **[User Guide](GUIDE.md)** · **[Cookbook](https://www.jakefile.dev/examples/benchmarking/)**

> [!WARNING]
> This project is still a work in progress and not yet production ready.

---

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

## Installation

```shell
# Requires Zig 0.15.2+
git clone https://github.com/HelgeSverre/jake.git
cd jake
zig build -Doptimize=ReleaseFast --prefix ~/.local
```

Or find prebuilt binaries on the [Releases](https://github.com/HelgeSverre/jake/releases) page.

## Features

- **[Task recipes](GUIDE.md#task-recipes)** - Define commands with parameters and dependencies
- **[File recipes](GUIDE.md#file-recipes)** - Rebuild only when sources change
- **[Glob patterns](GUIDE.md#glob-patterns)** - Watch `src/**/*.ts` for changes
- **[Imports](GUIDE.md#imports)** - Split Jakefiles into modules with namespacing
- **[Conditionals](GUIDE.md#conditionals)** - Branch on environment or context
- **[Hooks](GUIDE.md#hooks)** - Pre/post execution callbacks
- **[Validation](GUIDE.md#command-directives)** - Require commands (`@needs`) and env vars (`@require`)

## CLI Reference

```
jake [OPTIONS] [RECIPE]

OPTIONS:
  -h, --help              Show help
  -V, --version           Show version
  -l, --list              List recipes
  -a, --all               Include hidden recipes (with -l)
  -s, --show RECIPE       Show detailed recipe info
  -n, --dry-run           Print without executing
  -v, --verbose           Verbose output
  -y, --yes               Auto-confirm prompts
  -f, --jakefile FILE     Use specified Jakefile
  -w, --watch             Watch and re-run on changes
  -j, --jobs N            Parallel jobs (default: CPU count)
      --completions SHELL Generate shell completions
      --install/--uninstall  Manage shell completions
      --fmt               Format Jakefile (--check, --dump)
      --short/--summary   Machine-readable recipe listing
```

See [CLI Reference](GUIDE.md#cli-reference) for full details.

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

*Built with Zig · Inspired by Make & Just*
