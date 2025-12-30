---
title: Modular Projects
description: Split large Jakefiles into reusable modules with imports.
---

Organize complex projects by splitting your Jakefile into focused modules. Use namespaced imports to prevent naming collisions.

## Project Structure

```
project/
├── Jakefile           # Main file with imports
├── jake/
│   ├── build.jake     # Build tasks
│   ├── test.jake      # Testing tasks
│   ├── release.jake   # Release/packaging tasks
│   └── deploy.jake    # Deployment tasks
```

## Main Jakefile

```jake
# Import modules - some with aliases, some without
@import "jake/build.jake"
@import "jake/test.jake" as test
@import "jake/release.jake" as release
@import "jake/deploy.jake" as deploy

# Load environment
@dotenv

# Project metadata
version = "1.0.0"
@export version

# Global hooks
@pre echo "=== MyProject v{{version}} ==="
@on_error echo "Build failed!"

# Targeted hooks for release tasks
@before release.all echo "Starting cross-platform build..."
@after release.all echo "All platforms built!"

# Default task uses imported tasks
@default
task all: [build, test.run]
    echo "Build complete!"

# CI pipeline
task ci: [lint, test.run, build]
    echo "CI passed!"
```

## Module: jake/build.jake

```jake
@desc "Compile the project"
task build:
    @needs cargo
    @cache src/**/*.rs Cargo.toml
    cargo build --release

@desc "Check code formatting"
task lint:
    cargo fmt --check
    cargo clippy

@desc "Remove build artifacts"
task clean:
    @ignore
    rm -rf target/
```

## Module: jake/test.jake

```jake
@desc "Run all tests"
task run:
    @needs cargo
    cargo test

@desc "Run tests with coverage"
task coverage:
    @needs cargo-tarpaulin "cargo install cargo-tarpaulin"
    cargo tarpaulin --out html

@desc "Run tests in watch mode"
task watch:
    @needs cargo-watch "cargo install cargo-watch"
    cargo watch -x test
```

## Module: jake/release.jake

```jake
targets = "x86_64-linux aarch64-linux x86_64-macos aarch64-macos"

@desc "Build for all platforms"
task all:
    @needs cross "cargo install cross"
    mkdir -p dist
    @each {{targets}}
        cross build --release --target {{item}}
        cp target/{{item}}/release/myapp dist/myapp-{{item}}
    @end

@desc "Create GitHub release"
task publish: [all]
    @require GITHUB_TOKEN
    @confirm Publish release?
    gh release create v$VERSION dist/*
```

## Key Features

- **`@import "file.jake"`** - Import without namespace (tasks available directly)
- **`@import "file.jake" as name`** - Import with namespace (access as `name.task`)
- **`@before release.all`** - Hook into namespaced tasks
- **`@after release.all`** - Run after namespaced tasks complete

## Usage

```bash
# Run imported task directly (no namespace)
jake build

# Run namespaced tasks
jake test.run
jake release.all
jake deploy.staging

# Hooks fire automatically
jake release.all
# Output: "Starting cross-platform build..."
# ...build output...
# Output: "All platforms built!"
```
