---
title: Migrating from Make
description: A guide to converting your Makefile to a Jakefile.
tableOfContents:
  minHeadingLevel: 2
  maxHeadingLevel: 2
---

If you're coming from GNU Make, this guide will help you translate your Makefiles to Jakefiles.

## Syntax Changes

| Make | Jake |
|------|------|
| `target: deps` | `task target: [deps]` |
| `$(VAR)` | `{{VAR}}` |
| `.PHONY: target` | `task target:` (automatic) |
| Tab required | 4 spaces or tab |
| `$@` (target name) | Use explicit name |
| `$<` (first dep) | Use explicit name |
| `%.o: %.c` | Write explicit rules |

## Key Differences

### No Tab Sensitivity

Make requires tabs for indentation. Jake accepts either 4 spaces or a tab:

```jake
# Both work in Jake
task build:
    echo "Hello"  # 4 spaces
```

### No .PHONY Required

In Make, you must declare `.PHONY` for non-file targets. In Jake, `task` recipes are always treated as phony:

```jake
# This is automatically phony - no declaration needed
task clean:
    rm -rf dist/
```

### Explicit Variable Syntax

Make uses `$(VAR)` with many variants (`${VAR}`, `$@`, `$<`). Jake uses a single, clear syntax:

```jake
cc = "gcc"
cflags = "-Wall"

task build:
    {{cc}} {{cflags}} -c main.c
```

### Dependencies in Brackets

Make lists dependencies after the colon. Jake uses `[brackets]` for task dependencies:

```jake
# Make: test: build
# Jake:
task test: [build]
    cargo test
```

## Example Migration

### Before (Makefile)

```make
CC = gcc
CFLAGS = -Wall -O2

.PHONY: all clean test

all: build test

build: main.o utils.o
	$(CC) -o app main.o utils.o

%.o: %.c
	$(CC) $(CFLAGS) -c $<

test: build
	./test_runner

clean:
	rm -f *.o app
```

### After (Jakefile)

```jake
cc = "gcc"
cflags = "-Wall -O2"

@default
task all: [build, test]
    echo "Done"

file app: main.o utils.o
    {{cc}} -o app main.o utils.o

file main.o: main.c
    {{cc}} {{cflags}} -c main.c -o main.o

file utils.o: utils.c
    {{cc}} {{cflags}} -c utils.c -o utils.o

task test: [build]
    ./test_runner

task clean:
    rm -f *.o app
```

## What You Gain

Migrating from Make to Jake gives you:

1. **Readable syntax** - No more deciphering `$@` and `$<`
2. **Glob patterns** - Use `src/**/*.ts` instead of listing every file
3. **Parameters** - Pass arguments to recipes with defaults
4. **Conditionals** - `@if/@else` without shell gymnastics
5. **Imports** - Organize large projects with namespaced imports
6. **Better errors** - Helpful messages with suggestions
7. **Watch mode** - Built-in file watching with `-w`

## Migration Tips

1. **Start with tasks** - Convert your `.PHONY` targets to `task` recipes first
2. **Convert file rules** - Change pattern rules to explicit `file` recipes
3. **Simplify variables** - Replace Make's variable variants with `{{var}}`
4. **Add glob patterns** - Use `**/*.c` instead of `$(wildcard ...)`
5. **Remove workarounds** - Delete shell tricks that Jake handles natively

## See Also

- [File Targets](/docs/file-targets/) - Learn about `file` recipes
- [Dependencies](/docs/dependencies/) - Dependency syntax details
- [Variables](/docs/variables/) - Variable expansion
