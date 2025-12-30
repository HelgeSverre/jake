---
title: Conditionals
description: Conditional execution in Jake.
---

## Basic If/Else

```jake
task install:
    @if env(CI)
        npm ci
    @else
        npm install
    @end
```

## If/Elif/Else

```jake
task deploy:
    @if env(PRODUCTION)
        echo "Deploying to production"
    @elif env(STAGING)
        echo "Deploying to staging"
    @else
        echo "Deploying to development"
    @end
```

## Condition Functions

| Function        | Description                                       |
|-----------------|---------------------------------------------------|
| `env(VAR)`      | True if environment variable is set and non-empty |
| `exists(path)`  | True if file or directory exists                  |
| `eq(a, b)`      | True if strings are equal                         |
| `neq(a, b)`     | True if strings are not equal                     |
| `is_watching()` | True if running in watch mode (`-w`)              |
| `is_dry_run()`  | True if running in dry-run mode (`-n`)            |
| `is_verbose()`  | True if running in verbose mode (`-v`)            |

## Runtime State Conditions

Check how jake was invoked:

```jake
task build:
    @if is_watching()
        echo "Watch mode: skipping expensive lint"
    @else
        npm run lint
    @end
    npm run build

task deploy:
    @if is_dry_run()
        echo "[DRY RUN] Would deploy to production"
    @else
        rsync dist/ server:/var/www/
    @end

task test:
    @if is_verbose()
        npm test -- --verbose
    @else
        npm test
    @end
```

## File Existence

```jake
task setup:
    @if exists(node_modules)
        echo "Dependencies already installed"
    @else
        npm install
    @end
```

## String Comparison

```jake
task build:
    @if eq($BUILD_MODE, "release")
        cargo build --release
    @else
        cargo build
    @end
```
