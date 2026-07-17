---
title: Variables
description: Using variables in your Jakefile.
---

## Defining Variables

```jake
name = "Jake";
version = "1.0.0";
build_dir = "dist";
```

## Using Variables

Use `{{variable}}` syntax in commands:

```jake
greeting = "Hello"
target = "World"

task greet:
    echo "{{greeting}}, {{target}}!"
```

Output: `Hello, World!`

## Variable Scope

Variables are global and available to all recipes:

```jake
project = "myapp"

task build:
    echo "Building {{project}}"

task test:
    echo "Testing {{project}}"
```

## Two Variable Worlds: `{{var}}` vs `$VAR`

Jake has **two separate variable namespaces** and they don't override each other.
This trips people up; understand it once and the rest is obvious.

| Syntax     | Reads from                                                                                 |
| ---------- | ------------------------------------------------------------------------------------------ |
| `{{name}}` | Jakefile variables (`name = "..."`) and recipe parameters                                  |
| `$NAME`    | Shell environment (loaded by `@dotenv`, set by `@export`, inherited from the parent shell) |

`{{...}}` substitutions are resolved by Jake **before** the shell sees the
command. `$NAME` substitutions are resolved by the shell at command time.
Setting `PORT = "3000"` in the Jakefile does _not_ put `PORT` in the
environment, and conversely `@dotenv` does _not_ put loaded values into the
`{{...}}` namespace.

### Precedence within each namespace

For `{{name}}`:

1. Recipe parameters passed at the command line (`jake build env=prod` → `{{env}}` is `prod` for that run)
2. Jakefile variables (`name = "..."` assignments)

For `$NAME`:

1. Variables set on the same shell command line (`PORT=9999 jake serve`)
2. `@export VAR=value` directives
3. `.env` values loaded by `@dotenv`
4. Variables inherited from the shell that started Jake

### Worked example

```jake
@dotenv

PORT = "3000"

task serve:
    echo "via Jake namespace: {{PORT}}"   # always prints "3000"
    echo "via shell env:      $PORT"      # prints whatever the env says
```

With `.env` containing `PORT=8080`:

```
$ jake serve
via Jake namespace: 3000
via shell env:      8080
```

If you want a single value to drive both, set it once and pick the right syntax
on the consuming side. To pass a Jakefile variable to a subprocess as an
environment variable, set it inline on the command — Jake expands the `{{...}}`
before the shell sees it:

```jake
APP_PORT = "3000"

task serve:
    PORT={{APP_PORT}} my-server
```

`@export VAR=value` passes `value` through to subprocesses verbatim — `{{...}}`
inside an `@export` value is **not** expanded.

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

Exported variables are passed to all subprocess commands.

### Using in Commands

Use `$VAR` or `${VAR}` syntax:

```jake
task show:
    echo "Node: $NODE_ENV"
    echo "Debug: ${DEBUG}"
```

## .env File Format

```dotenv
# Database settings
DATABASE_URL=postgres://localhost/myapp
DB_POOL_SIZE=10

# API Keys (use quotes for special chars)
API_KEY="abc123!@#"

# Empty values
EMPTY_VAR=

# Escape sequences
MULTILINE=line1\nline2
WINDOWS_PATH=C:\\Users\\Name
```

Supported escapes: `\n`, `\t`, `\r`, `\\`, `\"`, `\'`, `\$`

## Requiring Variables

Validate required environment variables:

```jake
@require API_KEY DATABASE_URL

task deploy:
    echo "Deploying with $API_KEY"
```

Jake exits with an error if any required variable is missing.
