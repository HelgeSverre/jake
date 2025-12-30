---
title: Jakefile Syntax
description: Learn the Jakefile syntax and structure.
---

## Comments

```jake
# This is a comment
task foo:  # Inline comment
    echo "Hello"
```

### Doc Comments

Comments placed **immediately before** a recipe (no blank lines) are captured as documentation and shown in `jake -l`:

```jake
# Build the application binary
task build:
    zig build
```

A blank line between the comment and recipe **prevents** capture, making it easy to use section headers:

```jake
# ============================================
# Build Section
# ============================================

task build:  # This has no doc comment
    zig build
```

For inline descriptions, use `@desc` (shown in the same line as the recipe name):

```jake
@desc "Build the application"
task build:
    zig build
```

## Indentation

Commands must be indented with **4 spaces** or **1 tab**:

```jake
task example:
    echo "Line 1"
    echo "Line 2"
```

## Line Continuation

Long commands can span multiple lines using shell continuation:

```jake
task long-command:
    echo "This is a very long command" \
         "that spans multiple lines"
```

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

## Recipe Types

Jake supports three types of recipes:

| Type   | Keyword | Runs When                              | Best For                         |
|--------|---------|----------------------------------------|----------------------------------|
| Task   | `task`  | Always                                 | Commands, scripts, development   |
| File   | `file`  | Output missing or dependencies changed | Build artifacts, compilation     |
| Simple | (none)  | Always                                 | Quick recipes, Make-like syntax  |

### Task Recipes

Always run when invoked:

```jake
task clean:
    rm -rf dist/

task dev:
    npm run dev
```

### File Recipes

Only run if output is missing or dependencies changed:

```jake
file dist/app.js: src/**/*.ts
    esbuild src/index.ts --bundle --outfile=dist/app.js
```

### Simple Recipes

No keyword, Make-like syntax:

```jake
build:
    cargo build

test: [build]
    cargo test
```

## Recipe Aliases

Define alternative names:

```jake
task build | b | compile:
    cargo build
```

Now `jake build`, `jake b`, and `jake compile` all work.

## Private Recipes

Prefix with `_` to hide from listings:

```jake
task _internal-helper:
    echo "Hidden from jake --list"

task public-task: [_internal-helper]
    echo "Uses the private helper"
```
