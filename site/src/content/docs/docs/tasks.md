---
title: Tasks
description: Working with task recipes in Jake.
---

Task recipes **always run** when invoked. Use them for commands that should execute every time.

## Basic Tasks

```jake
task clean:
    rm -rf dist/
    rm -rf node_modules/

task test:
    npm test

task dev:
    npm run dev
```

## Parameters

Tasks support parameters with optional default values:

```jake
task greet name="World":
    echo "Hello, {{name}}!"

task deploy env="staging" version="latest":
    echo "Deploying {{version}} to {{env}}"
    ./deploy.sh {{env}} {{version}}
```

### Using Parameters

```bash
$ jake greet name=Alice
Hello, Alice!

$ jake deploy env=production version=1.2.3
Deploying 1.2.3 to production
```

## Dependencies

Tasks can depend on other recipes:

```jake
task build:
    echo "Building..."

task test: [build]
    echo "Testing after build..."

task deploy: [build, test]
    echo "Deploying after build and test..."
```

## Positional Arguments

Pass arguments directly using `{{$1}}`, `{{$2}}`, etc:

```jake
task greet:
    echo "Hello, {{$1}}!"
```

```bash
$ jake greet World
Hello, World!
```

### All Arguments

Access all arguments with `{{$@}}`:

```jake
task echo-all:
    echo "Arguments: {{$@}}"
```

```bash
$ jake echo-all a b c d
Arguments: a b c d
```

## Metadata

### Description

Use `@description` for inline descriptions:

```jake
task deploy:
    @description "Deploy application to production server"
    ./deploy.sh
```

Or use a comment **immediately before** the recipe (no blank lines):

```jake
# Deploy application to production server
task deploy:
    ./deploy.sh
```

A blank line between comment and recipe prevents capture—useful for section headers.

### Grouping

```jake
@group build
task build-frontend:
    npm run build

@group build
task build-backend:
    cargo build
```

### Platform-Specific

```jake
@only-os linux macos
task install-deps:
    ./install.sh

@only-os windows
task install-deps:
    install.bat
```

Valid OS values: `linux`, `macos`, `windows`

## When to Use Tasks

**Use `task` when:**

- The command should run every time (tests, dev servers, deployments)
- You need parameters
- You want explicit, self-documenting syntax

**Use `file` when:**

- The recipe produces an output file
- You want incremental builds
