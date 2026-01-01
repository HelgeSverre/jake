---
title: File Targets
description: Build files only when dependencies change.
---

File recipes are **conditional**—they only run if the output file is missing or any dependency file has been modified.

## Basic Syntax

```jake
file dist/app.js: src/index.ts
    esbuild src/index.ts --outfile=dist/app.js
```

The recipe name is the output file path. Dependencies are listed after the colon.

## Multiple Dependencies

```jake
file dist/bundle.js: src/index.ts src/utils.ts src/helpers.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js
```

## Glob Patterns

Use patterns to match multiple files:

```jake
file dist/app.js: src/**/*.ts
    esbuild src/index.ts --bundle --outfile=dist/app.js
```

Supported patterns:

- `*` - Match any characters except `/`
- `**` - Match any characters including `/` (recursive)
- `?` - Match single character
- `[abc]` - Match character class
- `[a-z]` - Match character range

## Chained Builds

File recipes can chain together for multi-stage builds:

```jake
# Stage 1: Compile TypeScript
file dist/compiled.js: src/**/*.ts
    tsc --outFile dist/compiled.js

# Stage 2: Minify (depends on Stage 1 output)
file dist/app.min.js: dist/compiled.js
    terser dist/compiled.js -o dist/app.min.js

# Task to trigger the full build
task build: [dist/app.min.js]
    echo "Build complete!"
```

When you run `jake build`, Jake automatically:

1. Checks if `dist/compiled.js` needs rebuilding
2. Checks if `dist/app.min.js` needs rebuilding
3. Only runs the necessary stages

## Examples

### CSS Compilation

```jake
file dist/styles.css: src/styles.scss
    sass src/styles.scss dist/styles.css
```

### Multi-file Bundle

```jake
file dist/bundle.js: src/**/*.js lib/**/*.js
    cat src/*.js lib/*.js > dist/bundle.js
```

### Binary Compilation

```jake
cc = "gcc"
cflags = "-Wall -O2"

file app: main.c utils.c
    {{cc}} {{cflags}} -o app main.c utils.c
```

## When to Use File Targets

**Use `file` when:**

- The recipe produces an output file
- You want incremental builds (skip if output is up-to-date)
- Build times matter and you want to avoid unnecessary work

**Use `task` when:**

- The command should run every time
- There's no specific output file
