---
title: Dependencies
description: Managing recipe dependencies in Jake.
---

Dependencies let you declare that one recipe must complete before another runs. Jake resolves the full dependency graph before execution — you don't have to think about ordering.

## Recipe Dependencies

```jake
task build:
    echo "Building..."

task test: [build]
    echo "Testing..."

task deploy: [build, test]
    echo "Deploying..."
```

Running `jake deploy` executes: `build` → `test` → `deploy`

## Deduplication

Each recipe runs at most once per invocation, regardless of how many other recipes depend on it.

```jake
task compile:
    echo "Compiling..."

task test: [compile]
    npm test

task lint: [compile]
    eslint src/

task ci: [test, lint]
    echo "Done"
```

Running `jake ci` executes: `compile` → `test` → `lint` → `ci`  
`compile` runs once, even though both `test` and `lint` depend on it.

## Parallel Execution

When you run with `-j` (parallel jobs), recipes that don't depend on each other run concurrently. Dependencies are still respected — Jake builds a topological graph and runs as many independent recipes as possible in parallel.

```bash
jake -j4 ci
```

With the example above, `test` and `lint` can run in parallel once `compile` finishes, cutting total time roughly in half.

## Dependency Order

Dependencies in the list run in declaration order when executed sequentially. In parallel mode, order is determined by the dependency graph — unrelated recipes may run in any order.

## File Dependencies

For `file` recipes, list source files or glob patterns after the colon:

```jake
file dist/bundle.js: src/index.ts src/utils.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js
```

The recipe only runs if the output file is missing or any dependency file is newer than the output.

## Glob Patterns

```jake
file dist/app.js: src/**/*.ts
    esbuild src/index.ts --bundle --outfile=dist/app.js
```

Supported patterns:

- `*` — any characters except `/`
- `**` — any characters including `/` (recursive)
- `?` — single character
- `[abc]` — character class
- `[a-z]` — character range

## Chained File Recipes

File recipes can depend on each other for multi-stage builds:

```jake
file dist/compiled.js: src/**/*.ts
    tsc --outFile dist/compiled.js

file dist/bundle.js: dist/compiled.js
    terser dist/compiled.js -o dist/bundle.js

task build: [dist/bundle.js]
    echo "Build complete!"
```

Jake checks freshness at each stage — if only `dist/compiled.js` is stale, only the minification step reruns.

## Mixed Dependencies

Combine recipe and file dependencies freely:

```jake
task setup:
    npm install

file dist/app.js: src/**/*.ts
    tsc --outDir dist

task build: [setup, dist/app.js]
    echo "Build complete!"
```

## Dependencies on Imported Recipes

Recipes from imported files can be used as dependencies by their namespaced name:

```jake
@import "jake/docker.jake" as docker
@import "jake/test.jake" as test

task ci: [docker.build, test.unit, test.integration]
    echo "CI complete"
```

## Cycle Detection

Jake detects cyclic dependencies and exits with an error:

```jake
task a: [b]
    echo "A"

task b: [a]
    echo "B"
```

```
error: Cyclic dependency detected in 'a'
```
