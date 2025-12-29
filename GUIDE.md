# Jake User Guide

A comprehensive guide to using Jake, the modern command runner with dependency tracking.

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Getting Started](#getting-started)
4. [Jakefile Syntax](#jakefile-syntax)
5. [Variables](#variables)
6. [Recipes](#recipes)
7. [Dependencies](#dependencies)
8. [File Targets](#file-targets)
9. [Parameters](#parameters)
10. [Imports](#imports)
11. [Environment Variables](#environment-variables)
12. [Conditionals](#conditionals)
13. [Hooks](#hooks)
14. [Command Directives](#command-directives)
15. [Recipe Metadata](#recipe-metadata)
16. [Positional Arguments](#positional-arguments)
17. [Built-in Functions](#built-in-functions)
18. [Parallel Execution](#parallel-execution)
19. [Watch Mode](#watch-mode)
20. [CLI Reference](#cli-reference)
21. [Best Practices](#best-practices)
22. [Migrating from Make](#migrating-from-make)
23. [Migrating from Just](#migrating-from-just)

---

## Introduction

Jake is a modern command runner that combines the best features of GNU Make and Just:

- **From Make**: File-based dependency tracking, parallel execution, incremental builds
- **From Just**: Clean syntax, parameters, conditionals, imports, .env loading
- **New in Jake**: Glob patterns, pre/post hooks, better error messages

Jake uses a simple, readable syntax without Make's tab sensitivity or arcane features.

---

## Installation

### From Source (Recommended)

Requires [Zig](https://ziglang.org/) 0.14 or later:

```bash
git clone https://github.com/HelgeSverre/jake.git
cd jake
zig build -Doptimize=ReleaseFast
```

The binary is at `zig-out/bin/jake`. Copy it to your PATH:

```bash
cp zig-out/bin/jake ~/.local/bin/
# or
sudo cp zig-out/bin/jake /usr/local/bin/
```

### Pre-built Binaries

Download from [GitHub Releases](https://github.com/HelgeSverre/jake/releases) for:
- Linux (x86_64, aarch64)
- macOS (x86_64, aarch64/Apple Silicon)
- Windows (x86_64)

---

## Getting Started

### Your First Jakefile

Create a file named `Jakefile` in your project root:

```jake
# A simple greeting
task hello:
    echo "Hello from Jake!"
```

Run it:

```bash
$ jake hello
-> hello
Hello from Jake!
```

### Listing Recipes

```bash
$ jake --list
Available recipes:
  hello [task]
```

### Setting a Default

```jake
@default
task build:
    echo "Building..."
```

Now `jake` with no arguments runs `build`.

---

## Jakefile Syntax

### Comments

```jake
# This is a comment
task foo:  # Inline comment
    echo "Hello"
```

### Indentation

Commands must be indented with **4 spaces** or **1 tab**:

```jake
task example:
    echo "Line 1"
    echo "Line 2"
```

### Line Continuation

Long commands can span multiple lines (use shell continuation):

```jake
task long-command:
    echo "This is a very long command" \
         "that spans multiple lines"
```

---

## Variables

### Defining Variables

```jake
name = "Jake"
version = "1.0.0"
```

### Using Variables

Use `{{variable}}` syntax in commands:

```jake
greeting = "Hello"
target = "World"

task greet:
    echo "{{greeting}}, {{target}}!"
```

Output: `Hello, World!`

### Variable Scope

Variables are global and available to all recipes:

```jake
project = "myapp"

task build:
    echo "Building {{project}}"

task test:
    echo "Testing {{project}}"
```

---

## Recipes

Jake supports three types of recipes:

### Task Recipes

Always run when invoked. Use for commands that should execute every time:

```jake
task clean:
    rm -rf dist/
    rm -rf node_modules/

task test:
    npm test
```

### File Recipes

Only run if the output file is missing or dependencies have changed:

```jake
file dist/app.js: src/index.ts
    esbuild src/index.ts --outfile=dist/app.js
```

### Simple Recipes

Shorthand for basic recipes (no `task` or `file` keyword):

```jake
build:
    cargo build

test: [build]
    cargo test
```

---

## Dependencies

### Recipe Dependencies

Run other recipes first using brackets:

```jake
task build:
    echo "Building..."

task test: [build]
    echo "Testing..."

task deploy: [build, test]
    echo "Deploying..."
```

Running `jake deploy` executes: `build` → `test` → `deploy`

### File Dependencies

For file recipes, list source files/patterns after the colon:

```jake
file dist/bundle.js: src/index.ts src/utils.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js
```

### Glob Patterns

Use glob patterns for file dependencies:

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

### Dependency Chains

File recipes automatically run recipes that produce their dependencies:

```jake
file dist/compiled.js: src/**/*.ts
    tsc --outFile dist/compiled.js

file dist/bundle.js: dist/compiled.js
    terser dist/compiled.js -o dist/bundle.js

task build: [dist/bundle.js]
    echo "Build complete!"
```

Running `jake build` automatically runs compilation first.

---

## Parameters

### Defining Parameters

```jake
task greet name:
    echo "Hello, {{name}}!"
```

### Default Values

```jake
task greet name="World":
    echo "Hello, {{name}}!"
```

### Multiple Parameters

```jake
task deploy env="staging" version="latest":
    echo "Deploying {{version}} to {{env}}"
```

### Using Parameters

```bash
$ jake greet name=Alice
Hello, Alice!

$ jake deploy env=production version=1.2.3
Deploying 1.2.3 to production
```

---

## Imports

### Basic Import

Import all recipes from another file:

```jake
@import "scripts/docker.jake"
```

This makes all recipes from `docker.jake` available.

### Namespaced Import

Import with a prefix to avoid name collisions:

```jake
@import "scripts/deploy.jake" as deploy
```

Access recipes as `deploy.production`, `deploy.staging`, etc.

### Example

**scripts/docker.jake:**
```jake
task build:
    docker build -t myapp .

task push:
    docker push myapp
```

**Jakefile:**
```jake
@import "scripts/docker.jake" as docker

task release: [build, docker.build, docker.push]
    echo "Released!"
```

---

## Environment Variables

### Loading .env Files

```jake
@dotenv                    # Load .env
@dotenv ".env.local"       # Load specific file
```

Files are loaded in order; later files override earlier ones.

### Exporting Variables

```jake
@export NODE_ENV=production
@export DEBUG=false
```

### Using Environment Variables

Use `$VAR` or `${VAR}` syntax:

```jake
task show:
    echo "Node: $NODE_ENV"
    echo "Debug: ${DEBUG}"
```

### .env File Format

```env
# Database settings
DATABASE_URL=postgres://localhost/myapp
DB_POOL_SIZE=10

# API Keys (use quotes for special chars)
API_KEY="abc123!@#"
SECRET="multi
line
value"
```

---

## Conditionals

### Basic If/Else

```jake
task install:
    @if env(CI)
        npm ci
    @else
        npm install
    @end
```

### If/Elif/Else

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

### Condition Functions

| Function | Description |
|----------|-------------|
| `env(VAR)` | True if environment variable is set and non-empty |
| `exists(path)` | True if file or directory exists |
| `eq(a, b)` | True if strings are equal |
| `neq(a, b)` | True if strings are not equal |

### Examples

```jake
task setup:
    @if exists(node_modules)
        echo "Dependencies already installed"
    @else
        npm install
    @end

task build:
    @if eq($BUILD_MODE, "release")
        cargo build --release
    @else
        cargo build
    @end
```

---

## Hooks

### Global Hooks

Run before/after any recipe:

```jake
@pre echo "=== Starting Jake ==="
@post echo "=== Jake Complete ==="
```

### Recipe Hooks

Run before/after specific recipe:

```jake
task deploy:
    @pre echo "Pre-deploy checks..."
    rsync dist/ server:/var/www/
    @post echo "Deploy notification sent"
```

### Hook Execution Order

1. Global pre-hooks
2. Recipe pre-hooks
3. Recipe commands
4. Recipe post-hooks
5. Global post-hooks

### Post-hooks Always Run

Post-hooks run even if the recipe fails, making them ideal for cleanup:

```jake
task test:
    @pre docker-compose up -d
    npm test
    @post docker-compose down
```

### Targeted Hooks

Target specific recipes without modifying them:

```jake
# Run before the "build" recipe only
@before build echo "Checking dependencies..."

# Run after the "deploy" recipe only
@after deploy notify "Deployment complete"

# Multiple targeted hooks
@before test docker-compose up -d
@after test docker-compose down
```

### Error Hooks

Run commands when any recipe fails:

```jake
# Error handler - runs on any recipe failure
@on_error echo "Recipe failed! Check logs."

# Send notification on failure
@on_error notify "Build failed - see logs"
```

Note: `@on_error` is always global - it runs when any recipe fails.

### Complete Hook Execution Order

1. Global `@pre` hooks (matching recipe)
2. `@before` hooks targeting this recipe
3. Recipe `@pre` hooks (inside recipe)
4. Recipe commands
5. Recipe `@post` hooks (inside recipe)
6. `@after` hooks targeting this recipe
7. Global `@post` hooks (matching recipe)
8. `@on_error` hooks (only if recipe failed)

---

## Command Directives

Directives control command execution behavior within recipes.

### @confirm - Interactive Prompts

Ask for confirmation before proceeding:

```jake
task deploy:
    @confirm "Deploy to production?"
    ./deploy.sh production
```

Use `-y` or `--yes` to auto-confirm all prompts:

```bash
jake -y deploy
```

### @needs - Command Existence Check

Verify required commands are available:

```jake
task build:
    @needs docker npm node
    docker build -t myapp .
```

If any command is missing, Jake exits with a helpful error.

### @require - Environment Variables

Validate required environment variables before running:

```jake
@require API_KEY DATABASE_URL

task deploy:
    echo "Deploying with $API_KEY"
```

### @each - Loop Iteration

Iterate over items:

```jake
task lint-all:
    @each src test lib
        echo "Linting {{item}}..."
        eslint {{item}}/
    @end
```

Items can be space or comma-separated.

#### Glob Pattern Expansion

Glob patterns in `@each` are automatically expanded to matching files:

```jake
# Process all TypeScript files
task check-all:
    @each src/**/*.ts
        echo "Checking {{item}}..."
        tsc --noEmit {{item}}
    @end

# Process specific file types
task format:
    @each *.go cmd/**/*.go
        go fmt {{item}}
    @end
```

### @cache - Skip When Unchanged

Skip commands if input files haven't changed:

```jake
task build:
    @cache src/*.ts package.json
    npm run build
```

The command only runs if any of the cached files have changed since the last run.

### @ignore - Continue on Failure

Continue execution even if command fails:

```jake
task cleanup:
    @ignore
    rm -rf temp/
    rm -rf cache/
    echo "Cleanup done"
```

### @cd - Working Directory

Run commands in a different directory:

```jake
task build-frontend:
    @cd frontend
    npm install
    npm run build
```

### @shell - Custom Shell

Use a different shell for the recipe:

```jake
task powershell-task:
    @shell powershell
    Write-Host "Hello from PowerShell"

task zsh-task:
    @shell zsh
    echo "Running in zsh"
```

### @ Command Prefix - Silent Execution

Prefix a command with `@` to suppress echoing:

```jake
task build:
    @echo "This won't show the 'echo' command itself"
    npm run build
```

---

## Recipe Metadata

### @group - Organize Recipes

Group related recipes together in listings:

```jake
@group build
task build-frontend:
    npm run build

@group build
task build-backend:
    cargo build

@group test
task test-unit:
    npm test
```

`jake --list` will show recipes organized by group.

### @description - Recipe Description

Add a description shown in listings:

```jake
task deploy:
    @description "Deploy application to production server"
    ./deploy.sh
```

### @only-os - Platform-Specific Recipes

Run recipes only on specific operating systems:

```jake
@only-os linux macos
task install-deps:
    ./install.sh

@only-os windows
task install-deps:
    install.bat
```

Valid OS values: `linux`, `macos`, `windows`

### @quiet - Suppress Output

Suppress command echoing for a recipe:

```jake
@quiet
task secret-task:
    echo "Commands won't be echoed"
```

### Recipe Aliases

Define alternative names for a recipe:

```jake
task build | b | compile:
    cargo build
```

Now `jake build`, `jake b`, and `jake compile` all work.

### Private Recipes

Prefix recipe names with `_` to hide from listings:

```jake
task _internal-helper:
    echo "This won't show in jake --list"

task public-task: [_internal-helper]
    echo "This uses the private helper"
```

---

## Positional Arguments

Pass arguments directly to recipes using shell-style variables.

### Basic Usage

```jake
task greet:
    echo "Hello, $1!"
```

```bash
$ jake greet World
Hello, World!
```

### Multiple Arguments

```jake
task deploy:
    echo "Deploying $1 to $2"
```

```bash
$ jake deploy v1.0.0 production
Deploying v1.0.0 to production
```

### All Arguments ($@)

Access all arguments at once:

```jake
task echo-all:
    echo "Arguments: $@"
```

```bash
$ jake echo-all a b c d
Arguments: a b c d
```

### Combined with Parameters

Positional args work alongside named parameters:

```jake
task deploy env="staging":
    echo "Deploying to {{env}} with args: $@"
```

---

## Built-in Functions

Use functions in variable expansion with `{{function(arg)}}` syntax.

### String Functions

| Function | Description | Example |
|----------|-------------|---------|
| `uppercase(s)` | Convert to uppercase | `{{uppercase(hello)}}` → `HELLO` |
| `lowercase(s)` | Convert to lowercase | `{{lowercase(HELLO)}}` → `hello` |
| `trim(s)` | Remove whitespace | `{{trim( hello )}}` → `hello` |

### Path Functions

| Function | Description | Example |
|----------|-------------|---------|
| `dirname(p)` | Get directory part | `{{dirname(/a/b/c.txt)}}` → `/a/b` |
| `basename(p)` | Get filename part | `{{basename(/a/b/c.txt)}}` → `c.txt` |
| `extension(p)` | Get file extension | `{{extension(file.txt)}}` → `.txt` |
| `without_extension(p)` | Remove extension | `{{without_extension(file.txt)}}` → `file` |
| `absolute_path(p)` | Get absolute path | `{{absolute_path(./src)}}` → `/home/user/project/src` |

### Using with Variables

```jake
file_path = "src/components/Button.tsx"

task info:
    echo "Directory: {{dirname(file_path)}}"
    echo "Filename: {{basename(file_path)}}"
    echo "Extension: {{extension(file_path)}}"
```

Output:
```
Directory: src/components
Filename: Button.tsx
Extension: .tsx
```

---

## Parallel Execution

### Running in Parallel

Use `-j` to run independent recipes concurrently:

```bash
jake -j4 all    # Use 4 parallel jobs
jake -j all     # Use CPU count
```

### Example

```jake
task frontend:
    npm run build

task backend:
    cargo build

task docs:
    mkdocs build

task all: [frontend, backend, docs]
    echo "All built!"
```

With `jake -j4 all`, frontend, backend, and docs build simultaneously.

### Dependency Ordering

Jake respects dependencies—parallel execution only happens for independent tasks:

```jake
task compile:
    cargo build

task test: [compile]    # Must wait for compile
    cargo test

task lint:              # Independent, can run parallel
    cargo clippy

task all: [test, lint]
    echo "Done!"
```

---

## Watch Mode

### Basic Watch

Re-run recipe when files change:

```bash
jake -w build
```

### Watch Specific Patterns

```bash
jake -w "src/**/*.ts" build
```

### Watch with Verbose Output

```bash
jake -w -v build
```

Shows which files triggered the rebuild.

---

## CLI Reference

```
jake [OPTIONS] [RECIPE] [ARGS...]

ARGUMENTS:
    RECIPE          Recipe to run (default: first recipe or @default)
    ARGS            Recipe arguments (name=value)

OPTIONS:
    -h, --help              Show help message
    -V, --version           Show version
    -l, --list              List available recipes
    -n, --dry-run           Print commands without executing
    -v, --verbose           Show verbose output
    -y, --yes               Auto-confirm all @confirm prompts
    -f, --jakefile PATH     Use specified Jakefile
    -w, --watch [PATTERN]   Watch and re-run on changes
    -j, --jobs [N]          Parallel jobs (default: CPU count)

EXAMPLES:
    jake                    Run default recipe
    jake build              Run 'build' recipe
    jake test --verbose     Run 'test' with verbose output
    jake deploy env=prod    Run 'deploy' with parameter
    jake -j4 all            Run 'all' with 4 parallel jobs
    jake -w build           Watch and rebuild
    jake -n deploy          Show what 'deploy' would do
```

---

## Best Practices

### 1. Use Descriptive Names

```jake
# Good
task build-frontend:
    npm run build

# Avoid
task bf:
    npm run build
```

### 2. Set a Default Task

```jake
@default
task dev:
    npm run dev
```

### 3. Group Related Tasks

```jake
# === Build ===
task build: [build-frontend, build-backend]
    echo "Build complete"

task build-frontend:
    npm run build

task build-backend:
    cargo build

# === Test ===
task test: [test-unit, test-integration]
    echo "All tests passed"
```

### 4. Use File Targets for Artifacts

```jake
# Good - only rebuilds when needed
file dist/app.js: src/**/*.ts
    esbuild src/index.ts --outfile=dist/app.js

# Avoid - rebuilds every time
task build:
    esbuild src/index.ts --outfile=dist/app.js
```

### 5. Use Imports for Organization

```
project/
├── Jakefile
└── jake/
    ├── docker.jake
    ├── deploy.jake
    └── test.jake
```

```jake
# Jakefile
@import "jake/docker.jake" as docker
@import "jake/deploy.jake" as deploy
@import "jake/test.jake" as test
```

### 6. Document Complex Recipes

```jake
# Deploy to production
# Requires: AWS credentials, SSH key
# Usage: jake deploy env=production
task deploy env="staging":
    @if eq($env, "production")
        @pre echo "WARNING: Deploying to production!"
    @end
    ./scripts/deploy.sh $env
```

---

## Migrating from Make

### Syntax Changes

| Make | Jake |
|------|------|
| `target: deps` | `task target: [deps]` |
| `$(VAR)` | `{{VAR}}` |
| `.PHONY: target` | `task target:` (automatic) |
| Tab indentation | 4 spaces or tab |
| `$@` | Use explicit name |
| `$<` | Use explicit name |

### Example Migration

**Makefile:**
```make
CC = gcc
CFLAGS = -Wall

.PHONY: all clean

all: build test

build: main.o utils.o
	$(CC) -o app main.o utils.o

%.o: %.c
	$(CC) $(CFLAGS) -c $<

clean:
	rm -f *.o app
```

**Jakefile:**
```jake
cc = "gcc"
cflags = "-Wall"

@default
task all: [build, test]
    echo "Done"

file app: main.o utils.o
    {{cc}} -o app main.o utils.o

file main.o: main.c
    {{cc}} {{cflags}} -c main.c

file utils.o: utils.c
    {{cc}} {{cflags}} -c utils.c

task clean:
    rm -f *.o app
```

---

## Migrating from Just

### Syntax Comparison

| Just | Jake |
|------|------|
| `recipe:` | `task recipe:` |
| `{{var}}` | `{{var}}` (same!) |
| `[group]` | Use imports |
| `@recipe` | (not needed) |
| `set dotenv-load` | `@dotenv` |

### Example Migration

**justfile:**
```just
set dotenv-load

default:
    just --list

build:
    cargo build

test: build
    cargo test

[group: 'deploy']
deploy-staging:
    ./deploy.sh staging

[group: 'deploy']
deploy-production:
    ./deploy.sh production
```

**Jakefile:**
```jake
@dotenv

@default
task list:
    jake --list

task build:
    cargo build

task test: [build]
    cargo test

# Or use imports for grouping:
# @import "deploy.jake" as deploy

task deploy-staging:
    ./deploy.sh staging

task deploy-production:
    ./deploy.sh production
```

### Key Differences

1. **File targets**: Jake supports Make-style file dependencies
2. **Parallel execution**: Jake has `-j` flag for parallel builds
3. **Glob patterns**: Jake supports `**/*.ts` in file deps
4. **Hooks**: Jake has `@pre`/`@post` hooks

---

## Troubleshooting

### Recipe Not Found

```
error: Recipe 'foo' not found
Run 'jake --list' to see available recipes.
```

Check spelling and that the Jakefile is in current directory.

### Cyclic Dependency

```
error: Cyclic dependency detected in 'foo'
```

Check that recipes don't depend on each other circularly:
```jake
# Wrong!
task a: [b]
task b: [a]
```

### Command Failed

```
error: command exited with code 1
```

The shell command failed. Use `-v` for verbose output to see the command.

### File Not Found

```
error: No Jakefile found
```

Create a `Jakefile` in current directory, or use `-f` to specify path.

---

## Getting Help

- **GitHub Issues**: [github.com/HelgeSverre/jake/issues](https://github.com/HelgeSverre/jake/issues)
- **Examples**: See the `samples/` directory

---

*Jake v0.2.0 • MIT License*
