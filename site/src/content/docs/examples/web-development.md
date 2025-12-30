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
task dev:
    @description "Start development server with hot reload"
    @needs node npm
    @pre echo "Starting development server on port {{port}}..."
    npm run dev

task dev-watch:
    @description "Build and watch for changes"
    @watch src/**/*.ts src/**/*.tsx src/**/*.css
    npm run build

# === Build Pipeline ===

@group build
task build: [clean, build-ts, build-css, build-assets]
    @description "Production build"
    echo "Build complete! Output in {{dist_dir}}/"

@group build
file dist/app.js: src/**/*.ts src/**/*.tsx
    @description "Compile TypeScript"
    @needs npx
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
file dist/app.css: src/**/*.css tailwind.config.js
    @description "Build Tailwind CSS"
    @needs npx
    @pre echo "Processing CSS..."
    mkdir -p dist
    npx tailwindcss -i src/styles/main.css -o dist/app.css --minify
    @post echo "CSS built: dist/app.css"

# Convenience tasks that depend on file targets
task build-ts: [dist/app.js]
    @echo "TypeScript build complete"

task build-css: [dist/app.css]
    @echo "CSS build complete"

task build-assets:
    @description "Copy static assets"
    mkdir -p dist/assets
    @if exists(public)
        cp -r public/* dist/
    @end
    @if exists(src/assets)
        cp -r src/assets/* dist/assets/
    @end

# === Development Utilities ===

@group dev
task lint:
    @description "Run ESLint"
    @needs npx
    npx eslint src/ --ext .ts,.tsx

@group dev
task format:
    @description "Format code with Prettier"
    @needs npx
    npx prettier --write "src/**/*.{ts,tsx,css,json}"

@group dev
task typecheck:
    @description "Type-check without emitting"
    @needs npx
    npx tsc --noEmit

task check: [lint, typecheck]
    @description "Run all code quality checks"
    echo "All checks passed!"

# === Testing ===

@group test
task test:
    @description "Run all tests"
    @needs npm
    npm test

@group test
task test-watch:
    @description "Run tests in watch mode"
    @needs npm
    npm test -- --watch

@group test
task test-coverage:
    @description "Run tests with coverage report"
    @needs npm
    npm test -- --coverage
    @post echo "Coverage report: coverage/lcov-report/index.html"

# === Cleanup ===

task clean:
    @description "Remove build artifacts"
    rm -rf dist/
    rm -rf .cache/
    rm -rf node_modules/.cache/
    echo "Cleaned build artifacts"

task clean-all: [clean]
    @description "Remove everything including dependencies"
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

Handle optional directories gracefully:

```jake
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
