---
title: Watch Mode
description: Automatically re-run tasks when files change.
---

## Basic Watch

Re-run recipe when files change:

```bash
jake -w build
```

Jake watches files based on:

- File dependencies in file recipes
- `@watch` directives in tasks

When watch mode starts, Jake shows what's being monitored:

```
[watch] Watching 5 file(s) for changes...
[watch] Patterns: src/**/*.ts, Jakefile
[watch] Press Ctrl+C to stop
```

## Watch Specific Patterns

```bash
jake -w "src/**/*.ts" build
```

## Watch Directive

Mark files to watch in a task:

```jake
task build:
    @watch src/*.ts
    npm run build
```

Multiple patterns:

```jake
task dev:
    @watch src/**/*.ts tests/**/*.ts
    npm run dev
```

## Watch with Verbose Output

```bash
jake -w -v build
```

Shows which files triggered the rebuild.

## Conditional Watch Behavior

Use `is_watching()` to adjust behavior:

```jake
task build:
    @if is_watching()
        echo "Watch mode: skipping expensive lint"
    @else
        npm run lint
    @end
    npm run build
```

## Combining with Other Flags

```bash
# Watch with verbose output
jake -w -v build

# Watch with parallel jobs
jake -w -j4 build
```
