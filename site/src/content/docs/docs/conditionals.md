---
title: Conditionals
description: Conditional execution in Jake.
---

Use `@if`, `@elif`, `@else`, and `@end` to conditionally execute commands inside a recipe.

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

| Function            | Description                                         |
| ------------------- | --------------------------------------------------- |
| `env(VAR)`          | True if environment variable is set and non-empty   |
| `exists(path)`      | True if file or directory exists                    |
| `command(name)`     | True if command exists in PATH                      |
| `eq(a, b)`          | True if strings are equal                           |
| `neq(a, b)`         | True if strings are not equal                       |
| `is_watching()`     | True if running in watch mode (`-w`)                |
| `is_dry_run()`      | True if running in dry-run mode (`-n`)              |
| `is_verbose()`      | True if running in verbose mode (`-v`)              |
| `is_macos()`        | True if running on macOS                            |
| `is_linux()`        | True if running on Linux                            |
| `is_windows()`      | True if running on Windows                          |
| `is_unix()`         | True if running on Unix-like OS (Linux, macOS, BSD) |
| `is_platform(name)` | True if running on the specified platform           |

## How Arguments Are Resolved

`eq()`, `neq()`, and `exists()` all resolve their arguments before evaluating. The resolution order is:

1. **`$VAR` or `${VAR}`** — looked up as an environment variable
2. **`{{var}}`** — looked up as a Jake variable (from your Jakefile)
3. **Plain identifier** — looked up as a Jake variable
4. **Quoted string** — used as a literal value

```jake
env_var    = "staging"        # Jake variable

task deploy:
    # $ENV resolves as environment variable
    @if eq($DEPLOY_ENV, production)
        echo "Deploying to prod"
    @end

    # Jake variable via plain identifier
    @if eq(env_var, staging)
        echo "Deploying to staging"
    @end

    # Jake variable via {{}} syntax
    @if eq({{env_var}}, staging)
        echo "Same thing"
    @end

    # Quoted literal — always the string "production"
    @if eq($DEPLOY_ENV, "production")
        echo "Explicit string comparison"
    @end
```

Unresolved variables (not found anywhere) silently become empty strings. A missing variable won't error — the condition just evaluates against `""`.

## Limitation: Positional Arguments

Positional arguments (`$1`, `$2`, `{{$1}}`) do not work inside condition expressions. Condition strings are evaluated before variable expansion, so `{{$1}}` in a condition is treated as a lookup for a variable literally named `$1`, which never exists.

Use named recipe parameters instead:

```jake
# Works
task deploy env="staging":
    @if eq(env, production)
        echo "Deploying to production!"
    @else
        echo "Deploying to {{env}}"
    @end
```

```bash
$ jake deploy env=production
```

## String Comparison

Compare Jake variables, environment variables, or literals:

```jake
task build:
    @if eq($BUILD_MODE, release)
        cargo build --release
    @else
        cargo build
    @end
```

```jake
mode = "debug"

task compile:
    @if neq(mode, release)
        echo "Building in debug mode"
    @end
```

## File Existence

`exists()` checks whether a file or directory exists on disk. Pass a path, a Jake variable, or a quoted string:

```jake
task setup:
    @if exists(node_modules)
        echo "Dependencies already installed"
    @else
        npm install
    @end

task build:
    @if exists(dist/index.html)
        echo "Already built, skipping"
    @else
        npm run build
    @end
```

Note: `exists()` only handles a single whole-path variable reference (`exists({{dir}})`) — it doesn't expand variables inline within a path string like `exists({{dir}}/file.txt)`.

## Environment Variables

`env(VAR)` is true if the variable is set and non-empty:

```jake
task install:
    @if env(CI)
        npm ci
    @else
        npm install
    @end

task deploy:
    @if env(PRODUCTION)
        echo "Deploying to production"
    @elif env(STAGING)
        echo "Deploying to staging"
    @else
        echo "Deploying to development"
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
        echo "kubectl not installed — skipping deploy"
    @end
```

Works with absolute paths too:

```jake
task check:
    @if command(/usr/local/bin/custom-tool)
        /usr/local/bin/custom-tool run
    @end
```

## Runtime State

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

## Platform Detection

```jake
task install:
    @if is_macos()
        brew install ripgrep
    @elif is_linux()
        apt-get install ripgrep
    @elif is_windows()
        choco install ripgrep
    @end
```

Use `is_unix()` for commands that work on all Unix-like systems (Linux, macOS, BSDs):

```jake
task permissions:
    @if is_unix()
        chmod +x ./script.sh
    @end
```

Use `is_platform()` to match any platform by OS tag name:

```jake
task build:
    @if is_platform(freebsd)
        gmake build
    @else
        make build
    @end
```

## Error Behavior

If a condition expression is malformed or uses an unknown function, Jake treats it as `false` and skips the block — no error is produced. If you see a block silently not executing, double-check the condition syntax.

## Nesting

`@if` blocks can be nested to arbitrary depth:

```jake
task deploy:
    @if env(CI)
        @if is_macos()
            echo "CI on macOS"
        @else
            echo "CI on Linux/Windows"
        @end
    @else
        echo "Local build"
    @end
```
