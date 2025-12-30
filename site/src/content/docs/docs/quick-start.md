---
title: Quick Start
description: Get up and running with Jake in 5 minutes.
---

## Your First Jakefile

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

## Listing Recipes

```bash
$ jake --list
Available recipes:
  hello [task]
```

## Setting a Default

```jake
@default
task build:
    echo "Building..."
```

Now `jake` with no arguments runs `build`.

## Adding Dependencies

```jake
task build:
    echo "Building..."

task test: [build]
    echo "Testing..."

task deploy: [build, test]
    echo "Deploying..."
```

Running `jake deploy` executes: `build` → `test` → `deploy`

## Using Variables

```jake
app_name = "myapp"
version = "1.0.0"

task info:
    echo "{{app_name}} v{{version}}"
```

## Parameters

```jake
task greet name="World":
    echo "Hello, {{name}}!"
```

```bash
$ jake greet name=Alice
Hello, Alice!
```

## File Targets

Only rebuild when sources change:

```jake
file dist/bundle.js: src/**/*.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js
```

## Watch Mode

Re-run on file changes:

```bash
jake -w build
```

## Parallel Execution

Run independent tasks concurrently:

```bash
jake -j4 all
```

## Complete Example

```jake
# Variables
app_name = "myapp"

# Load .env file
@dotenv

# Default task
@default
task build:
    @description "Build the application"
    cargo build --release

# Task with dependencies
task test: [build]
    cargo test

# File target
file dist/app: src/**/*.rs
    cargo build --release
    cp target/release/{{app_name}} dist/app

# Conditional logic
task deploy: [build, test]
    @confirm "Deploy to production?"
    @if env(CI)
        ./scripts/deploy-ci.sh
    @else
        ./scripts/deploy-local.sh
    @end
```

## Next Steps

- [Jakefile Syntax](/docs/syntax/)
- [Tasks Reference](/docs/tasks/)
- [CLI Options](/reference/cli/)
