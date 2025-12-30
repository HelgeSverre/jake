---
title: Migrating from Just
description: A guide to converting your justfile to a Jakefile.
---

If you're coming from Just, the transition to Jake is smooth. Most syntax is similar or identical.

## Syntax Comparison

| Just | Jake |
|------|------|
| `recipe:` | `task recipe:` (or simple syntax) |
| `{{var}}` | `{{var}}` (same!) |
| `set dotenv-load` | `@dotenv` |
| `@recipe` (quiet) | `@quiet` decorator |
| `[group: 'x']` | `@group x` |
| `[confirm]` | `@confirm "message"` |
| `[private]` | Prefix with `_` |

## Key Differences

### Recipe Keyword

Just uses bare recipe names. Jake prefers the `task` keyword for clarity, but also supports simple syntax:

```jake
# Jake with task keyword (recommended)
task build:
    cargo build

# Jake with simple syntax (Just-like)
build:
    cargo build
```

### .env Loading

Just uses a global setting. Jake uses a directive:

```jake
# Just: set dotenv-load
# Jake:
@dotenv
@dotenv ".env.local"  # Can load multiple files
```

### Groups

Just uses attributes. Jake uses a directive:

```jake
# Just: [group: 'build']
# Jake:
@group build
task compile:
    cargo build
```

### Confirmations

Just uses an attribute. Jake uses a directive with a message:

```jake
# Just: [confirm]
# Jake:
task deploy:
    @confirm "Deploy to production?"
    ./deploy.sh
```

### Private Recipes

Just uses an attribute. Jake uses a naming convention:

```jake
# Just: [private]
# Jake: prefix with underscore
task _helper:
    echo "I'm hidden from --list"

task public: [_helper]
    echo "I use the hidden helper"
```

## Example Migration

### Before (justfile)

```just
set dotenv-load

default:
    @just --list

build:
    cargo build

test: build
    cargo test

[confirm("Deploy to production?")]
[group: 'deploy']
deploy: test
    ./deploy.sh
```

### After (Jakefile)

```jake
@dotenv

@default
task list:
    jake --list

task build:
    cargo build

task test: [build]
    cargo test

@group deploy
task deploy: [test]
    @confirm "Deploy to production?"
    ./deploy.sh
```

## What Jake Adds

Migrating from Just gives you new capabilities:

### 1. File-Based Dependencies

Track source files and only rebuild when changed:

```jake
file dist/bundle.js: src/**/*.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js
```

This skips the build if no TypeScript files changed since the last run.

### 2. Glob Patterns

Reference files with wildcards:

```jake
file dist/app.js: src/**/*.ts
    tsc --outFile dist/app.js
```

### 3. Parallel Execution

Run independent tasks simultaneously:

```bash
jake -j4 all    # 4 parallel workers
jake -j all     # Use CPU count
```

### 4. Pre/Post Hooks

Run setup and cleanup around recipes:

```jake
task deploy:
    @pre echo "Starting deployment..."
    ./deploy.sh
    @post echo "Deployment complete!"
```

### 5. Watch Mode

Re-run tasks when files change:

```bash
jake -w build
jake -w "src/**/*.ts" build
```

### 6. @needs Directive

Verify tools exist before running:

```jake
task build:
    @needs node npm esbuild
    npm run build
```

### 7. Error Hooks

Handle failures globally:

```jake
@on_error notify "Build failed!"

task build:
    npm run build
```

## Migration Tips

1. **Add `task` keyword** - For clarity (or keep simple syntax)
2. **Convert attributes** - Replace `[...]` with `@...` directives
3. **Move dotenv** - Change `set dotenv-load` to `@dotenv`
4. **Use file recipes** - Replace always-run tasks with `file` when appropriate
5. **Add parallelism** - Use `-j` for faster builds

## Keeping Compatibility

If you want to gradually migrate, you can:
1. Keep your justfile during transition
2. Run specific tasks with both tools to verify behavior
3. Once confident, remove the justfile

## See Also

- [File Targets](/docs/file-targets/) - Learn about file-based caching
- [Watch Mode](/docs/watch-mode/) - Automatic rebuilds
- [Directives Reference](/reference/directives/) - All Jake directives
