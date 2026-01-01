---
title: Dependencies
description: Managing recipe dependencies in Jake.
---

## Recipe Dependencies

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

## File Dependencies

For file recipes, list source files/patterns after the colon:

```jake
file dist/bundle.js: src/index.ts src/utils.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js
```

## Glob Patterns

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

## Dependency Chains

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

## Mixed Dependencies

Combine recipe and file dependencies:

```jake
task setup:
    npm install

file dist/app.js: src/**/*.ts
    tsc --outDir dist

task build: [setup, dist/app.js]
    echo "Build complete!"
```

## Avoiding Cycles

Jake detects cyclic dependencies:

```jake
# This will error!
task a: [b]
    echo "A"

task b: [a]
    echo "B"
```

```
error: Cyclic dependency detected in 'a'
```
