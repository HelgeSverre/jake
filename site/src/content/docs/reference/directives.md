---
title: Directives
description: All Jake directives reference.
---

## Global Directives

Placed at the top level of a Jakefile.

| Directive | Description |
|-----------|-------------|
| `@default` | Mark next recipe as default |
| `@dotenv` | Load `.env` file |
| `@dotenv "path"` | Load specific env file |
| `@export VAR=value` | Export environment variable |
| `@require VAR...` | Require environment variables |
| `@import "path"` | Import another Jakefile |
| `@import "path" as name` | Import with namespace |
| `@pre command` | Global pre-hook |
| `@post command` | Global post-hook |
| `@before recipe command` | Pre-hook for specific recipe |
| `@after recipe command` | Post-hook for specific recipe |
| `@on_error command` | Run on any recipe failure |

## Recipe Modifiers

Placed before a recipe definition.

| Directive | Description |
|-----------|-------------|
| `@group name` | Group recipe in listings |
| `@only-os os...` | Only run on specified OS |
| `@quiet` | Suppress command echoing |

## Recipe Directives

Used inside recipe bodies.

| Directive | Description |
|-----------|-------------|
| `@description "text"` | Recipe description |
| `@pre command` | Recipe pre-hook |
| `@post command` | Recipe post-hook |
| `@confirm "message"` | Ask for confirmation |
| `@needs cmd...` | Require commands exist |
| `@needs cmd "hint"` | With installation hint |
| `@needs cmd -> recipe` | With auto-install recipe |
| `@cd path` | Change working directory |
| `@shell name` | Use different shell |
| `@ignore` | Continue on failure |
| `@cache pattern...` | Skip if files unchanged |
| `@watch pattern...` | Watch patterns for `-w` |

## Control Flow

| Directive | Description |
|-----------|-------------|
| `@if condition` | Conditional start |
| `@elif condition` | Else-if branch |
| `@else` | Else branch |
| `@end` | End conditional/loop |
| `@each items...` | Loop over items |

## Command Prefix

| Prefix | Description |
|--------|-------------|
| `@` | Suppress command echoing |

Example:
```jake
task build:
    @echo "Building quietly..."
    npm run build
```

## Condition Functions

For use with `@if`:

| Function | Description |
|----------|-------------|
| `env(VAR)` | Variable is set and non-empty |
| `exists(path)` | File/directory exists |
| `eq(a, b)` | Strings are equal |
| `neq(a, b)` | Strings are not equal |
| `is_watching()` | In watch mode |
| `is_dry_run()` | In dry-run mode |
| `is_verbose()` | In verbose mode |
