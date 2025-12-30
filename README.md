<p align="center">
  <h1 align="center">jake</h1>
  <p align="center">
    <strong>A modern command runner with dependency tracking</strong>
  </p>
  <p align="center">
    The best of Make and Just, combined.
  </p>
</p>

<p align="center">
  <a href="https://github.com/HelgeSverre/jake/actions/workflows/ci.yml"><img src="https://github.com/HelgeSverre/jake/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/HelgeSverre/jake/releases"><img src="https://img.shields.io/github/v/release/HelgeSverre/jake?style=flat-square" alt="Release"></a>
  <img src="https://img.shields.io/badge/lang-Zig-F7A41D?style=flat-square&logo=zig" alt="Zig">
  <img src="https://img.shields.io/badge/built_with-Claude_Code-cc785c?style=flat-square&logo=anthropic" alt="Built with Claude Code">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
</p>

<p align="center">
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#features">Features</a> •
  <a href="GUIDE.md">User Guide</a>
</p>

---

## Why Jake?

**Make** is powerful but cryptic. **Just** is friendly but limited. **Jake** gives you both:

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

### From Source

```bash
# Requires Zig 0.15.2+
git clone https://github.com/HelgeSverre/jake.git
cd jake
zig build -Doptimize=ReleaseFast
cp zig-out/bin/jake ~/.local/bin/
```

### Pre-built Binaries

Download from [Releases](https://github.com/HelgeSverre/jake/releases):
- `jake-linux-x86_64`
- `jake-linux-aarch64`
- `jake-macos-x86_64`
- `jake-macos-aarch64`
- `jake-windows-x86_64.exe`

## Quick Start

Create a `Jakefile` in your project:

```jake
# Variables
app_name = "myapp"
version = "1.0.0"

# Load environment variables
@dotenv

# Default task - runs when you just type 'jake'
@default
@desc "Build the application"
task build:
    echo "Building {{app_name}} v{{version}}..."
    mkdir -p dist
    echo "Build complete!"

# Task with dependencies - test runs build first
@desc "Run all tests"
task test: [build]
    echo "Running tests..."
    echo "All tests passed!"

# Clean task
@desc "Remove build artifacts"
task clean:
    rm -rf dist

# Task with parameter
task greet name="World":
    echo "Hello, {{name}}!"

# Conditional based on environment
@desc "Deploy to production"
task deploy: [build, test]
    @confirm "Deploy to production?"
    @if env(CI)
        echo "Deploying from CI..."
    @else
        echo "Deploying locally..."
    @end
    echo "Deployed {{app_name}} v{{version}}"

# File target - only rebuilds when sources change
file dist/bundle.js: src/*.js
    cat src/*.js > dist/bundle.js

# Parallel execution - all subtasks run together
task all: [build, test, lint]
    echo "All tasks complete!"

@desc "Check code style"
task lint:
    echo "Linting..."
```

Run it:

```bash
jake                    # Run default task (build)
jake test               # Run tests (builds first)
jake greet name=Alice   # Pass parameters
jake -j4 all            # Run with 4 parallel jobs
jake -l                 # List available tasks
jake -l --short         # One recipe per line (for scripting)
jake -s build           # Show detailed recipe info
jake -n deploy          # Dry-run (show what would run)
jake -w build           # Watch mode - rebuild on changes
jake buidl              # Typo? Suggests: "Did you mean: build?"
```

## Features

### Task Recipes
```jake
task greet name="World":
    echo "Hello, {{name}}!"
```

### File Recipes with Globs
```jake
file dist/bundle.js: src/**/*.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js
```

### Dependencies
```jake
task deploy: [build, test]
    rsync dist/ server:/var/www/
```

### Imports
```jake
@import "scripts/docker.jake"
@import "scripts/deploy.jake" as deploy

task all: [build, deploy.production]
    echo "Done!"
```

### Environment Variables
```jake
@dotenv
@dotenv ".env.local"
@export NODE_ENV=production

task start:
    echo "Starting with $NODE_ENV"
```

### Conditionals
```jake
task install:
    @if env(CI)
        npm ci
    @else
        npm install
    @end

task dev:
    @if is_watching()
        echo "Watch mode active"
    @end
```

### Hooks
```jake
@pre echo "Starting..."
@post echo "Done!"

task build:
    @pre echo "Compiling..."
    cargo build
    @post echo "Build complete!"
```

### Validation
```jake
@needs docker npm     # Check commands exist before running
@require API_KEY      # Check environment variables

task deploy:
    docker build -t app .
```

### Watch Mode
```bash
jake -w build              # Watch and rebuild
jake -w "src/**" build     # Watch specific patterns
```

## CLI Reference

```
jake [OPTIONS] [RECIPE]

OPTIONS:
    -h, --help              Show help
    -V, --version           Show version
    -l, --list              List recipes
        --short             Output one recipe per line (with -l)
    -s, --show RECIPE       Show detailed recipe info
    -n, --dry-run           Print without executing
    -v, --verbose           Verbose output
    -y, --yes               Auto-confirm prompts
    -f, --jakefile FILE     Use specified Jakefile
    -w, --watch             Watch and re-run
    -j, --jobs N            Parallel jobs (default: CPU count)
        --summary           Print recipe names (for scripting)
        --completions SHELL Print shell completion script
        --install           Install completions to user directory
        --uninstall         Remove completions and config
```

**Typo suggestions**: If you mistype a recipe name, jake suggests similar recipes:
```
$ jake buidl
error: Recipe 'buidl' not found
Did you mean: build?
```

## Shell Completions

Jake provides tab completion for recipe names and flags in bash, zsh, and fish.

### Quick Install

```bash
# Auto-detect your shell and install completions
jake --completions --install
```

### Manual Installation

```bash
# Generate completion script for your shell
jake --completions bash > ~/.local/share/bash-completion/completions/jake
jake --completions zsh > ~/.zsh/completions/_jake
jake --completions fish > ~/.config/fish/completions/jake.fish
```

### Smart Detection

The `--install` command automatically detects your environment:

| Environment | Install Location | Config Needed |
|-------------|------------------|---------------|
| **Oh-My-Zsh** | `~/.oh-my-zsh/custom/completions/_jake` | None |
| **Homebrew zsh** | `/opt/homebrew/share/zsh/site-functions/_jake` | None |
| **Vanilla zsh** | `~/.zsh/completions/_jake` | Auto-patches `~/.zshrc` |
| **Bash** | `~/.local/share/bash-completion/completions/jake` | None |
| **Fish** | `~/.config/fish/completions/jake.fish` | None |

### Uninstall

```bash
# Remove completions and any config changes
jake --completions --uninstall
```

### What Gets Completed

- **Recipe names** - dynamically loaded from your Jakefile
- **Flags** - all CLI options with descriptions
- **Flag values** - file paths for `-f`, shell names for `--completions`

## Documentation

- **[User Guide](GUIDE.md)** - Complete reference
- **[E2E Tests](tests/e2e/)** - Example Jakefiles and test fixtures

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

MIT License - see [LICENSE](LICENSE.md)

---

<p align="center">
  Built with Zig • Inspired by Make & Just
</p>
