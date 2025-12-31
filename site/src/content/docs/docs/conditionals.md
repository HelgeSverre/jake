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
| `command(name)` | True if command exists in PATH                    |
| `eq(a, b)`      | True if strings are equal                         |
| `neq(a, b)`     | True if strings are not equal                     |
| `is_watching()` | True if running in watch mode (`-w`)              |
| `is_dry_run()`  | True if running in dry-run mode (`-n`)            |
| `is_verbose()`  | True if running in verbose mode (`-v`)            |
| `is_macos()`    | True if running on macOS                          |
| `is_linux()`    | True if running on Linux                          |
| `is_windows()`  | True if running on Windows                        |
| `is_unix()`     | True if running on Unix-like OS (Linux, macOS, BSD) |
| `is_platform(name)` | True if running on the specified platform     |

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

## Command Availability

Check if tools are available before using them:

```jake
task build:
    @if command(docker)
        docker build -t myapp .
    @elif command(podman)
        podman build -t myapp .
    @else
        echo "No container runtime found"
    @end

task deploy:
    @if command(kubectl)
        kubectl apply -f k8s/
    @else
        echo "kubectl not installed - skipping deploy"
    @end
```

Works with absolute paths too:

```jake
task check:
    @if command(/usr/local/bin/custom-tool)
        /usr/local/bin/custom-tool run
    @end
```

## Platform Detection

Run platform-specific commands:

```jake
task install:
    @if is_macos()
        brew install ripgrep
    @elif is_linux()
        apt-get install ripgrep
    @elif is_windows()
        choco install ripgrep
    @end

task open:
    @if is_macos()
        open https://jakefile.dev
    @elif is_linux()
        xdg-open https://jakefile.dev
    @elif is_windows()
        start https://jakefile.dev
    @end
```

Use `is_unix()` for commands that work on all Unix-like systems:

```jake
task permissions:
    @if is_unix()
        chmod +x ./script.sh
    @end
```

Use `is_platform()` for flexible platform matching:

```jake
task build:
    @if is_platform(freebsd)
        gmake build
    @else
        make build
    @end
```
