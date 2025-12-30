---
title: Parallel Execution
description: Run independent tasks simultaneously to speed up builds.
---

Jake can run independent tasks in parallel, dramatically speeding up builds with multiple components.

```jake
# Independent components that can build simultaneously
task frontend:
    @desc "Build React frontend"
    cd frontend && npm run build

task backend:
    @desc "Build Go backend"
    cd backend && go build -o dist/server

task docs:
    @desc "Build documentation"
    mkdocs build

task assets:
    @desc "Optimize images and assets"
    npx imagemin src/images/* --out-dir=dist/images

# Dependencies run in parallel when possible
@default
task build: [frontend, backend, docs, assets]
    @desc "Build everything"
    echo "All components built!"

# Testing can also be parallelized
task test-frontend:
    cd frontend && npm test

task test-backend:
    cd backend && go test ./...

task test-e2e:
    @needs playwright
    npx playwright test

task test: [test-frontend, test-backend, test-e2e]
    echo "All tests passed!"
```

## How Parallel Execution Works

When you run `jake -j`, independent dependencies run in parallel:

```
jake build
├── frontend ─┐
├── backend  ─┼─ run in parallel ─→ build completes
├── docs     ─┤
└── assets   ─┘
```

Dependencies are analyzed:
- Tasks with no inter-dependencies run simultaneously
- Tasks that depend on each other run in sequence
- The `-j` flag controls the maximum parallel jobs

## Usage

```bash
# Run with default parallelism (CPU count)
jake -j build

# Limit to 4 parallel jobs
jake -j4 build

# Sequential execution (no parallelism)
jake build
```

## Viewing Parallel Execution

Use verbose mode to see parallel execution:

```bash
$ jake -j -v build

[1/4] Starting frontend...
[2/4] Starting backend...
[3/4] Starting docs...
[4/4] Starting assets...
[1/4] frontend completed (2.3s)
[3/4] docs completed (1.1s)
[4/4] assets completed (3.2s)
[2/4] backend completed (4.1s)
build: Build everything
All components built!
```

## Dependency Chains

Tasks with dependencies still respect ordering:

```jake
task compile: [generate-types]
    tsc

task bundle: [compile]
    esbuild dist/index.js --bundle

task minify: [bundle]
    terser dist/bundle.js -o dist/bundle.min.js

# These run in sequence: generate-types → compile → bundle → minify
task release: [minify]
    echo "Release ready!"
```

## Combining Sequential and Parallel

```jake
# These can run in parallel with each other
task lint:
    npm run lint

task typecheck:
    tsc --noEmit

task format-check:
    prettier --check .

# Pre-flight checks (parallel)
task check: [lint, typecheck, format-check]
    echo "All checks passed!"

# Build depends on checks (sequential)
task build: [check, compile]
    echo "Build complete!"
```

Running `jake -j build`:
1. lint, typecheck, and format-check run in parallel
2. Once all pass, compile runs
3. Then the build task runs
