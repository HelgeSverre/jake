---
title: Web Development
description: Complete Jakefile for modern web development with TypeScript, CSS, and testing.
---

A complete workflow for web development with TypeScript compilation, CSS processing, development servers, and production optimization.

## Complete Jakefile

```jake
# Web Development Jakefile
# ========================

@dotenv
@export NODE_ENV=development

# Configuration
src_dir = "src"
dist_dir = "dist"
port = "3000"

# === Development ===

@default
@desc "Start development server with hot reload"
task dev:
    @needs node npm
    @pre echo "Starting development server on port {{port}}..."
    npm run dev

@desc "Build and watch for changes"
task dev-watch:
    @watch src/**/*.ts src/**/*.tsx src/**/*.css
    npm run build

# === Build Pipeline ===

@group build
@desc "Production build"
task build: [clean, build-ts, build-css, build-assets]
    echo "Build complete! Output in {{dist_dir}}/"

@group build
@desc "Compile TypeScript"
file dist/app.js: src/**/*.ts src/**/*.tsx
    @pre echo "Compiling TypeScript..."
    mkdir -p dist
    npx esbuild src/index.tsx \
        --bundle \
        --minify \
        --sourcemap \
        --target=es2020 \
        --outfile=dist/app.js
    @post echo "TypeScript compiled: dist/app.js"

@group build
@desc "Build Tailwind CSS"
file dist/app.css: src/**/*.css tailwind.config.js
    @pre echo "Processing CSS..."
    mkdir -p dist
    npx tailwindcss -i src/styles/main.css -o dist/app.css --minify
    @post echo "CSS built: dist/app.css"

# Convenience tasks that wrap the file targets. @needs is recipe-modifier
# only — it doesn't work inside a file recipe body — so it lives on the task.
@needs npx
task build-ts: [dist/app.js]
    echo "TypeScript build complete"

@needs npx
task build-css: [dist/app.css]
    echo "CSS build complete"

@desc "Copy static assets"
task build-assets:
    mkdir -p dist/assets
    @if exists(public)
        cp -r public/* dist/
    @end
    @if exists(src/assets)
        cp -r src/assets/* dist/assets/
    @end

# === Development Utilities ===

@group dev
@desc "Run ESLint"
task lint:
    @needs npx
    npx eslint src/ --ext .ts,.tsx

@group dev
@desc "Format code with Prettier"
task format:
    @needs npx
    npx prettier --write "src/**/*.{ts,tsx,css,json}"

@group dev
@desc "Type-check without emitting"
task typecheck:
    @needs npx
    npx tsc --noEmit

@desc "Run all code quality checks"
task check: [lint, typecheck]
    echo "All checks passed!"

# === Testing ===

@group test
@desc "Run all tests"
task test:
    @needs npm
    npm test

@group test
@desc "Run tests in watch mode"
task test-watch:
    @needs npm
    npm test -- --watch

@group test
@desc "Run tests with coverage report"
task test-coverage:
    @needs npm
    npm test -- --coverage
    @post echo "Coverage report: coverage/lcov-report/index.html"

# === Cleanup ===

@desc "Remove build artifacts"
task clean:
    rm -rf dist/
    rm -rf .cache/
    rm -rf node_modules/.cache/
    echo "Cleaned build artifacts"

@desc "Remove everything including dependencies"
task clean-all: [clean]
    rm -rf node_modules/
    echo "Removed node_modules/"
```

## Usage

```bash
jake                    # Start dev server
jake build              # Production build
jake -j4 build          # Parallel build (4 workers)
jake -w build-ts        # Watch and rebuild TypeScript
jake check              # Lint + typecheck
jake test-coverage      # Tests with coverage
```

## Key Features

### File-Based Caching

The `file` recipes track source changes:

```jake
file dist/app.js: src/**/*.ts src/**/*.tsx
    npx esbuild src/index.tsx --bundle --outfile=dist/app.js
```

This only rebuilds if TypeScript files have changed.

### Watch Mode Integration

Use `@watch` to specify patterns for `-w` flag:

```jake
task dev-watch:
    @watch src/**/*.ts src/**/*.tsx src/**/*.css
    npm run build
```

### Conditional Asset Copying

Handle optional directories gracefully (`@if` is recipe-body-only — wrap it in a task):

```jake
task copy-public:
    @if exists(public)
        cp -r public/* dist/
    @end
```

## Customization

Adjust the configuration variables at the top:

```jake
src_dir = "src"          # Source directory
dist_dir = "dist"        # Output directory
port = "3000"            # Dev server port
```

## See Also

- [File Targets](/docs/file-targets/) - Understanding file-based caching
- [Watch Mode](/docs/watch-mode/) - Automatic rebuilds
- [Parallel Execution](/examples/parallel-execution/) - Speed up builds
