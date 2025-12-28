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
# Requires Zig 0.15+
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
version = "1.0.0"

# Default task
@default
task build:
    echo "Building v{{version}}..."
    cargo build --release

# Task with dependencies
task test: [build]
    cargo test

# File target (only runs if output is stale)
file dist/app.js: src/**/*.ts
    esbuild src/index.ts --outfile=dist/app.js

# Parallel execution
task all: [frontend, backend, docs]
    echo "All done!"
```

Run it:

```bash
jake              # Run default task
jake build        # Run specific task
jake -j4 all      # Run with 4 parallel jobs
jake -l           # List available tasks
jake -n deploy    # Dry-run (show what would run)
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

### Watch Mode
```bash
jake -w build              # Watch and rebuild
jake -w "src/**" build     # Watch specific patterns
```

## CLI Reference

```
jake [OPTIONS] [RECIPE]

OPTIONS:
    -h, --help         Show help
    -V, --version      Show version
    -l, --list         List recipes
    -n, --dry-run      Print without executing
    -v, --verbose      Verbose output
    -f, --jakefile     Use specified Jakefile
    -w, --watch        Watch and re-run
    -j, --jobs N       Parallel jobs (default: CPU count)
```

## Documentation

- **[User Guide](GUIDE.md)** - Complete reference
- **[Examples](samples/)** - Sample Jakefiles

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

MIT License - see [LICENSE](LICENSE)

---

<p align="center">
  Built with Zig • Inspired by Make & Just
</p>
