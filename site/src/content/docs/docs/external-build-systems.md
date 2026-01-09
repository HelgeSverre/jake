---
title: External Build Systems
description: Use Jake alongside Makefile and Justfile targets.
---

Jake can detect and run targets from Makefile and Justfile in the same directory. This lets you gradually migrate to Jake or use them together.

## Automatic Detection

Jake automatically detects these files:

**Makefile variants** (in priority order):
- `GNUmakefile`
- `Makefile`
- `makefile`

**Justfile variants** (in priority order):
- `justfile`
- `Justfile`
- `.justfile`

## Recipe Naming

External recipes get a prefix to avoid conflicts:

| Source | Prefix | Example |
|--------|--------|---------|
| Makefile | `make.` | `make.build`, `make.clean` |
| Justfile | `just.` | `just.test`, `just.deploy` |

## Listing External Recipes

```bash
# List all recipes including external
jake --list

# List only external recipes
jake --external

# List only Makefile targets
jake --external make

# List only Justfile recipes
jake --external just

# Hide external recipes from listing
jake --list --no-external
```

## Running External Recipes

Run them like any other recipe:

```bash
# Run a Makefile target
jake make.build

# Run a Justfile recipe
jake just.test

# With arguments (passed through)
jake make.install PREFIX=/usr/local
```

## How It Works

When you run an external recipe, Jake delegates to the underlying tool:

- **Makefile**: Runs `make -f <file> <target>`
- **Justfile**: Runs `just --justfile <file> <recipe>`

The original tool handles all the execution logic.

## Private Targets

Targets starting with `_` are treated as private:

```makefile
# Makefile
_helper:    # Hidden from jake --list
	echo "helper"

build: _helper
	echo "building"
```

## Example: Mixed Project

Directory structure:
```
project/
├── Jakefile      # Jake recipes
├── Makefile      # Legacy build
└── justfile      # Additional tooling
```

```bash
# See everything
jake --list

# Output:
# Available recipes:
#   build         Build the project
#   test          Run tests
#
# Makefile (Makefile):
#   make.all
#   make.clean
#
# Justfile (justfile):
#   just.fmt      Format code
#   just.lint     Run linter
```

## Gradual Migration

Use external support to migrate incrementally:

1. Create a Jakefile alongside your Makefile
2. Move recipes one at a time
3. Have Jake recipes call make targets during transition:

```jake
task build:
    @description "New Jake build"
    # Can still call old make targets
    make legacy-step
    echo "New build steps..."
```

4. Remove Makefile when migration is complete
