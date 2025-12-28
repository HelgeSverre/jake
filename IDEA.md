# Jake: The Best of Make and Just

> **Jake** = **J**ust + M**ake** — A modern command runner with real dependency tracking

## The Problem Space

### Make's Strengths
- File-based dependency tracking (only rebuild what changed)
- Parallel execution with `-j`
- Pattern rules (`%.o: %.c`)
- Decades of battle-tested reliability

### Make's Pain Points
- Tab-sensitivity is a constant footgun
- Cryptic error messages
- Designed for C builds, awkward for modern workflows
- Variable syntax is confusing (`$@`, `$<`, `$^`, `$(VAR)`, `${VAR}`)
- Recursive make is considered harmful
- `.PHONY` everywhere for non-file targets

### Just's Strengths
- Clean, readable syntax
- Great CLI UX (listing recipes, tab completion)
- Variables and expressions that make sense
- Cross-platform by default
- Built-in help generation
- Recipe parameters with defaults

### Just's Limitations
- No file-based dependency tracking
- No incremental builds
- Always runs the full recipe
- No parallel execution of dependencies

---

## Jake Vision

**A command runner with Make's dependency intelligence and Just's developer experience.**

---

## Core Design Ideas

### 1. Jakefile Syntax

```jake
# Variables (simple, no $ prefix needed in definitions)
build_dir = "dist"
src_dir = "src"

# Default recipe (first one, or marked with @default)
@default
build: [compile, assets]  # depends on other recipes
    echo "Build complete!"

# File-based target (automatically tracks file changes)
file dist/app.js: src/**/*.ts
    esbuild src/index.ts --bundle --outfile=dist/app.js

# Task-based recipe (like just, always runs)
task deploy:
    rsync -av dist/ server:/var/www/

# Recipe with parameters
task greet name="World":
    echo "Hello, {{name}}!"

# Pattern rules (like make, but cleaner)
file dist/%.css: src/%.scss
    sass $input $output
```

### 2. Dependency Model

```jake
# Three types of dependencies:

# 1. Recipe dependencies - run these first
build: [compile, test]

# 2. File dependencies - rebuild if these change
file dist/bundle.js: src/**/*.js, package.json

# 3. Order-only dependencies - ensure order, don't trigger rebuild
deploy: | build   # run build first, but don't rebuild for deploy
```

### 3. Smart Caching

```jake
# Hash-based caching (not just mtime)
file dist/app: src/**/*.go
    @cache hash        # use content hash, not mtime
    @cache deps go.sum # also invalidate on go.sum changes
    go build -o dist/app

# Remote cache support
@cache remote s3://my-bucket/jake-cache
```

### 4. Parallel Execution

```jake
# Automatic parallelism for independent deps
build: [frontend, backend, docs]  # runs in parallel by default

# Explicit sequencing when needed
deploy: frontend -> backend -> migrate
    echo "Deployed!"
```

### 5. Modern CLI UX

```bash
# List all recipes with descriptions
$ jake
Available recipes:
  build     Build the entire project
  test      Run test suite
  deploy    Deploy to production
  clean     Remove build artifacts

# Run with parameters
$ jake greet name=Alice

# Dry run - show what would execute
$ jake build --dry-run

# Force rebuild (ignore cache)
$ jake build --force

# Parallel with explicit jobs
$ jake build -j8

# Show dependency graph
$ jake build --graph
```

### 6. Environment & Secrets

```jake
# Load from .env automatically
@dotenv

# Required env vars (fail early with clear message)
@require AWS_ACCESS_KEY_ID
@require AWS_SECRET_ACCESS_KEY

deploy:
    aws s3 sync dist/ s3://my-bucket/
```

### 7. Conditional Logic

```jake
# Platform-specific commands
task install:
    @if os == "macos"
        brew install myapp
    @elif os == "linux"
        apt install myapp
    @else
        echo "Unsupported platform"
    @end

# Check if command exists
task setup:
    @needs docker, node, npm
    npm install
```

### 8. Imports & Modularity

```jake
# Import other jakefiles
@import ./scripts/docker.jake as docker
@import ./scripts/deploy.jake

# Use imported recipes
build: [docker.build, compile]
```

### 9. Watch Mode

```jake
task dev:
    @watch src/**/*.ts
    npm run build

# Or from CLI
$ jake build --watch
```

### 10. Recipe Documentation

```jake
# Build the project for production
#
# This compiles TypeScript, bundles assets, and runs optimization.
# Use --no-minify to skip minification for debugging.
task build:
    ...

$ jake --help build
# Shows the doc comment
```

---

## Advanced Features

### Workspaces / Monorepo Support

```jake
# Run recipe in all packages
@workspace packages/*

task test:
    @each package
        cd {{package}} && npm test
```

### Hooks

```jake
@before build
    echo "Starting build at $(date)"

@after build
    notify-send "Build complete"

@on-error build
    echo "Build failed!" | slack-notify
```

### Built-in Common Tasks

```jake
# Built-in recipes that "just work"
@builtin docker    # docker.build, docker.push, etc.
@builtin npm       # npm.install, npm.test, npm.publish
@builtin git       # git.tag, git.release
```

### Interactive Mode

```jake
task setup:
    @prompt "Database host?" -> db_host
    @prompt "Database port?" default=5432 -> db_port
    @confirm "Create database?"
    createdb -h {{db_host}} -p {{db_port}} myapp
```

### Sandboxing / Containers

```jake
# Run in container for reproducibility
task build:
    @container node:20-alpine
    npm ci
    npm run build
```

---

## Implementation Thoughts

### Language Choices

| Language | Pros | Cons |
|----------|------|------|
| **Rust** | Fast, single binary, just is written in it | Longer compile times |
| **Go** | Fast, single binary, great stdlib | GC overhead (minimal) |
| **Zig** | Extremely fast, minimal deps | Younger ecosystem |

### File Change Detection

- Use hash-based detection by default (more reliable than mtime)
- Store hashes in `.jake/cache`
- Support both file globs and explicit lists
- Integrate with git for smart dirty detection

### Name Alternatives

- `jake` - **J**ust + M**ake** (primary choice)
- `bake` - Build + Make (taken by several tools)
- `rake` - taken by Ruby
- `jmake` - Just Make
- `mk` - short for make (used by Plan 9)
- `run` - simple but generic
- `do` - very short (used by redo)
- `jk` - just kidding... but also jake initials

---

## Example Jakefile (Full)

```jake
# Jakefile for a TypeScript web project

@dotenv
@require DATABASE_URL

src = "src"
dist = "dist"
node_modules = "node_modules"

# Default: build everything
@default
all: [build, test]

# Install dependencies (only if package.json changed)
file {{node_modules}}/.install-stamp: package.json, package-lock.json
    npm ci
    touch {{node_modules}}/.install-stamp

# Type check
task typecheck: [node_modules/.install-stamp]
    npx tsc --noEmit

# Build the app
file {{dist}}/bundle.js: {{src}}/**/*.ts, tsconfig.json
    @needs node_modules/.install-stamp
    npx esbuild src/index.ts --bundle --outfile={{dist}}/bundle.js

# Alias for file target
build: [dist/bundle.js]

# Run tests
task test: [typecheck]
    npx vitest run

# Development server with watch
task dev:
    @watch {{src}}/**/*.ts
    npx esbuild src/index.ts --bundle --outfile={{dist}}/bundle.js --watch

# Clean build artifacts
task clean:
    rm -rf {{dist}}

# Deploy to production
task deploy: [build, test]
    @confirm "Deploy to production?"
    rsync -av {{dist}}/ prod:/var/www/

# Database tasks
task db.migrate:
    npx prisma migrate deploy

task db.seed:
    npx prisma db seed

# Shortcut for full DB setup
task db.setup: [db.migrate, db.seed]
```

---

## Open Questions

1. **Config format**: Custom DSL (like just) vs YAML/TOML vs embedded in existing lang?
2. **Shell**: POSIX sh, bash, or built-in cross-platform shell?
3. **Defaults**: How opinionated should it be out of the box?
4. **Migration**: Tooling to convert Makefiles/Justfiles to Jakefiles?
5. **Plugin system**: Allow extensions? How to distribute?
6. **LSP/Editor support**: Syntax highlighting, completions, error checking?

---

## MVP Features (v0.1)

1. Parse Jakefile with clean syntax
2. File-based dependency tracking with hashes
3. Task-based recipes (always run)
4. Recipe dependencies (runs in order)
5. Variables and substitution
6. Recipe parameters with defaults
7. `jake` (list), `jake <recipe>` (run), `jake --help`
8. Parallel execution of independent deps
9. `.env` loading
10. Color output, good error messages

---

## Tagline Ideas

- "Jake: Finally, a build tool that makes sense"
- "Jake: Make, but make it modern"
- "Jake: Commands that know when to run"
- "Jake: Build smarter, not harder"
- "Jake: The task runner with a memory"
