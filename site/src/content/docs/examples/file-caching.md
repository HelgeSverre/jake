---
title: Incremental Builds
description: Use file caching to skip unnecessary rebuilds.
---

Track source file modifications and only rebuild when something changes. This is especially useful for large projects where full rebuilds are expensive.

```jake
@desc "Build with caching - only rebuilds when sources change"
task build:
    @needs zig
    @cache src/*.zig build.zig build.zig.zon
    @pre echo "Building..."
    zig build
    @post echo "Build complete!"

@desc "Optimized release build with caching"
task build-release:
    @needs zig
    @cache src/*.zig build.zig
    zig build -Doptimize=ReleaseFast

@desc "Clean and rebuild from scratch"
task rebuild: [clean, build]
    echo "Rebuild complete"

@desc "Remove build artifacts"
task clean:
    @ignore
    rm -rf zig-out .zig-cache .jake
```

## How `@cache` Works

The `@cache` directive tracks file modification times. When you run a task:

1. Jake checks if any of the specified files have changed since the last run
2. If nothing changed, the task is skipped with "up to date"
3. If files changed, the task runs normally

## File Targets for Automatic Caching

For even smarter caching, use `file` targets instead of `task`:

```jake
# File target - only rebuilds when dependencies are newer than output
file dist/app.js: src/**/*.ts tsconfig.json
    npx tsc

file dist/styles.css: src/**/*.css postcss.config.js
    npx postcss src/styles.css -o dist/styles.css

# Task that depends on file targets
task build: [dist/app.js, dist/styles.css]
    echo "Build complete!"
```

File targets automatically track:

- Whether the output file exists
- Whether any dependency is newer than the output
- Glob patterns like `src/**/*.ts`

## Usage

```bash
# First run - full build
jake build

# Second run - skipped if no changes
jake build
# Output: "build: up to date"

# After editing a source file
jake build
# Output: builds again
```
