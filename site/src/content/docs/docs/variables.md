---
title: Variables
description: Using variables in your Jakefile.
---

## Defining Variables

```jake
name = "Jake"
version = "1.0.0"
build_dir = "dist"
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
