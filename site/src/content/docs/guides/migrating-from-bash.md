---
title: Migrating from Bash Scripts
description: Replace your build.sh and task runner scripts with Jake.
tableOfContents:
  minHeadingLevel: 2
  maxHeadingLevel: 2
---

Many projects use bash scripts (`build.sh`, `run.sh`, `Taskfile`) as task runners. Jake provides the same functionality with better ergonomics.

## Common Bash Patterns

### Function-Based Task Runner

A typical bash task script looks like this:

```bash
#!/bin/bash
set -euo pipefail

build() {
  echo "Building..."
  gcc -o app src/*.c
}

test() {
  build  # Manual dependency
  ./app --test
}

clean() {
  rm -f app *.o
}

help() {
  echo "Available tasks:"
  compgen -A function | grep -v "^_"
}

${@:-build}  # Default task
```

### Jake Equivalent

```jake
@default
task build:
    echo "Building..."
    gcc -o app src/*.c

task test: [build]
    ./app --test

task clean:
    rm -f app *.o
```

## Key Improvements

### 1. Automatic Dependency Resolution

**Bash** - Manual function calls:

```bash
deploy() {
  build
  test
  rsync dist/ server:/app/
}
```

**Jake** - Declarative dependencies:

```jake
task deploy: [build, test]
    rsync dist/ server:/app/
```

Jake automatically runs dependencies in the right order and skips duplicates.

### 2. Parallel Execution

**Bash** - Complex PID management:

```bash
build() {
  build_backend &
  PID1=$!
  build_frontend &
  PID2=$!
  wait $PID1 || exit 1
  wait $PID2 || exit 1
}
```

**Jake** - Just use `-j` flag:

```jake
task build: [build-backend, build-frontend]
    echo "Build complete"

task build-backend:
    go build ./cmd/server

task build-frontend:
    npm run build
```

```bash
jake -j4 build  # Run with 4 parallel workers
```

### 3. File-Based Dependencies

**Bash** - No way to skip if unchanged:

```bash
compile() {
  # Always runs, even if nothing changed
  gcc -o app main.c util.c
}
```

**Jake** - Smart rebuilds:

```jake
file app: main.c util.c
    gcc -o app main.c util.c
```

This only runs if `main.c` or `util.c` are newer than `app`.

### 4. Built-in Help

**Bash** - Manual implementation:

```bash
help() {
  echo "Available tasks:"
  compgen -A function | grep -v "^_" | cat -n
}
```

**Jake** - Built-in:

```bash
jake --list     # List all recipes with descriptions
jake -s build   # Show detailed info about a recipe
```

### 5. Cross-Platform Compatibility

**Bash** - Platform-specific code:

```bash
# macOS vs Linux differences
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's/foo/bar/' file
else
  sed -i 's/foo/bar/' file
fi
```

**Jake** - Platform directives:

```jake
@platform macos
task install:
    brew install deps

@platform linux
task install:
    apt-get install deps
```

### 6. Confirmation Prompts

**Bash** - Manual prompt:

```bash
deploy() {
  read -p "Deploy to production? (yes/no) " -r
  if [ "$REPLY" != "yes" ]; then
    exit 0
  fi
  # deploy...
}
```

**Jake** - Built-in directive:

```jake
task deploy:
    @confirm "Deploy to production?"
    ./deploy.sh
```

Use `jake -y deploy` to auto-confirm.

### 7. Environment Variables

**Bash** - Manual loading:

```bash
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi
```

**Jake** - Built-in:

```jake
@dotenv
@dotenv ".env.local"

@require DATABASE_URL API_KEY

task deploy:
    echo "Using $DATABASE_URL"
```

## Complete Migration Example

### Before (build.sh)

```bash
#!/bin/bash
set -euo pipefail

PROJECT="myapp"
BUILD_DIR="build"

_log() {
  echo "[$(date +'%H:%M:%S')] $1"
}

_check_deps() {
  command -v node >/dev/null 2>&1 || { echo "node required"; exit 1; }
  command -v go >/dev/null 2>&1 || { echo "go required"; exit 1; }
}

install() {
  _log "Installing dependencies..."
  npm install
  go mod download
}

build-backend() {
  _log "Building backend..."
  go build -o "${BUILD_DIR}/server" ./cmd/server
}

build-frontend() {
  _log "Building frontend..."
  npm run build
}

build() {
  _check_deps
  mkdir -p "${BUILD_DIR}"

  build-backend &
  local pid1=$!
  build-frontend &
  local pid2=$!

  wait $pid1 || exit 1
  wait $pid2 || exit 1

  _log "Build complete!"
}

test() {
  _log "Running tests..."
  go test ./... -v
  npm test
}

clean() {
  rm -rf "${BUILD_DIR}" dist/ node_modules/
}

deploy() {
  local env="${1:-staging}"

  if [ "$env" = "production" ]; then
    read -p "Deploy to PRODUCTION? " -r
    [ "$REPLY" != "yes" ] && exit 0
  fi

  build
  rsync -avz "${BUILD_DIR}/" "deploy@${env}.example.com:/app/"
}

help() {
  echo "Usage: $0 <task> [args...]"
  echo "Tasks:"
  compgen -A function | grep -v "^_" | sort
}

"${@:-help}"
```

### After (Jakefile)

```jake
@dotenv

project = "myapp"
build_dir = "build"

@default
task build: [build-backend, build-frontend]
    @needs node go
    @pre echo "Building {{project}}..."
    @post echo "Build complete!"

task build-backend:
    mkdir -p {{build_dir}}
    go build -o {{build_dir}}/server ./cmd/server

task build-frontend:
    mkdir -p {{build_dir}}
    npm run build

task install:
    @desc "Install dependencies"
    npm install
    go mod download

task test: [build]
    @desc "Run all tests"
    go test ./... -v
    npm test

task clean:
    @desc "Remove build artifacts"
    rm -rf {{build_dir}} dist/ node_modules/

task deploy env="staging": [build]
    @desc "Deploy to environment"
    @if eq({{env}}, "production")
        @confirm "Deploy to PRODUCTION?"
    @end
    rsync -avz {{build_dir}}/ deploy@{{env}}.example.com:/app/
```

### Usage Comparison

| Bash                        | Jake                         |
| --------------------------- | ---------------------------- |
| `./build.sh`                | `jake`                       |
| `./build.sh build`          | `jake build`                 |
| `./build.sh deploy staging` | `jake deploy env=staging`    |
| `./build.sh help`           | `jake --list`                |
| N/A                         | `jake -j4 build` (parallel)  |
| N/A                         | `jake -w build` (watch mode) |
| N/A                         | `jake -n deploy` (dry-run)   |

## What You Gain

1. **Automatic dependency resolution** - No manual function calls
2. **Parallel execution** - Built-in with `-j` flag
3. **File-based caching** - Skip unchanged builds
4. **Watch mode** - Re-run on file changes
5. **Dry-run mode** - See what would run
6. **Better help** - Auto-generated from recipes
7. **Cross-platform** - No bash-specific quirks
8. **Cleaner syntax** - Less boilerplate

## See Also

- [Quick Start](/docs/quick-start/) - Get started with Jake
- [Best Practices](/docs/best-practices/) - Write effective Jakefiles
- [File Targets](/docs/file-targets/) - Smart rebuilds
