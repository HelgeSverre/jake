---
title: Watch Mode
description: Automatically re-run tasks when files change.
---

Watch mode re-runs a recipe whenever relevant files change. It's useful for development loops — running tests, rebuilding on save, or restarting a dev server.

```bash
jake -w build
```

Jake polls for file changes every 500ms, with a 100ms debounce after the last detected change before triggering a re-run. This means the recipe fires roughly 100ms after files stop changing, not on every individual write.

## What Gets Watched

Without an explicit pattern, Jake automatically watches:

- The Jakefile and any imported files
- File dependencies declared in `file` recipes
- Patterns in `@watch` directives in the target recipe

```bash
jake -w build    # watches Jakefile + @watch patterns + file deps
```

With an explicit pattern, Jake watches only what you specify:

```bash
jake -w "src/**/*.ts" build
```

When watch mode starts, Jake shows what it's monitoring:

```
[watch] Watching 5 file(s) for changes...
[watch] Patterns: src/**/*.ts, Jakefile
[watch] Press Ctrl+C to stop
```

## @watch Directive

Declare additional watch patterns inside a recipe:

```jake
task build:
    @watch src/**/*.ts
    npm run build
```

Multiple patterns on one line:

```jake
task dev:
    @watch src/**/*.ts tests/**/*.ts config/*.json
    npm run dev
```

## Jakefile Reloads

If the Jakefile itself (or an imported file) changes while watch mode is running, Jake reloads it before the next run. The entire executor reinitializes with the updated recipe definitions — so changes to recipe commands, dependencies, or new recipes take effect immediately without restarting.

When using an explicit pattern (`jake -w "src/**" build`), Jakefile reloading still happens if the Jakefile matches the pattern or is being auto-tracked.

## Deleted and Recreated Files

Deleted files trigger a re-run. If you delete a watched file and then recreate it, both events trigger the recipe. This is useful for workflows that regenerate files from scratch.

## Conditional Watch Behavior

Use `is_watching()` to adjust what a recipe does in watch mode vs a one-off run:

```jake
task build:
    @if is_watching()
        echo "Incremental build (skipping lint)..."
    @else
        npm run lint
    @end
    npm run build
```

## Long-Running Recipes

If a recipe is still running when the next file change is detected, Jake waits for the current run to finish before starting the next one. Changes that arrive during execution are not queued — only the latest change matters, and it triggers one re-run once the current execution completes.

## Combining Flags

```bash
# Verbose output shows which file triggered the rebuild
jake -w -v build

# Parallel execution in watch mode
jake -w -j4 test

# Explicit pattern + verbose
jake -w "src/**/*.go" -v test
```

## Common Patterns

**Frontend dev loop** — watch TypeScript source, rebuild on change:

```jake
task dev:
    @watch src/**/*.ts src/**/*.css public/**/*
    npm run build:dev
```

**Test on save** — run only affected tests:

```jake
task test:
    @watch src/**/*.ts tests/**/*.test.ts
    npm test
```

**Go rebuild** — recompile and restart on source changes:

```jake
task run:
    @watch **/*.go
    go run ./cmd/server
```
