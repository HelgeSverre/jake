---
title: Imports
description: Organize your Jakefile with imports.
---

Split large Jakefiles into separate modules and import them where needed. Imported content is merged into the importing file before execution — it's not a plugin system, it's closer to `#include`.

## Basic Import

```jake
@import "scripts/docker.jake"
```

All recipes from `docker.jake` become available directly by name.

## Namespaced Import

```jake
@import "scripts/deploy.jake" as deploy
```

Recipes are prefixed: `deploy.production`, `deploy.staging`, etc. Use namespaced imports when you have recipes with the same name in multiple files.

**The prefix applies only to recipes, not variables.** Variables from the imported file are merged globally without any prefix. If the imported file defines `version = "1.0"`, that variable becomes available everywhere — and will override any existing `version` variable defined earlier.

## What Gets Merged

When you import a file, Jake merges everything into the main Jakefile:

| What                                          | Behavior                                          |
| --------------------------------------------- | ------------------------------------------------- |
| Recipes                                       | Merged; prefix applied if `as name` is used       |
| Variables                                     | Merged globally, no prefix — last definition wins |
| Directives (`@dotenv`, `@export`, `@require`) | Merged and applied globally                       |
| Global hooks (`@pre`, `@post`, `@on_error`)   | Merged and apply to all recipes in the project    |

This means an imported file's `@dotenv`, `@export`, or `@pre` directives affect the entire project, not just the recipes in that file.

## Variable Collisions

Because variables from imports are merged unnamespaced, name collisions are possible. If your main Jakefile and an imported file both define `port = "..."`, the last one loaded wins (imports are processed in order, so imports override main-file definitions that appear before the `@import` line, and main-file definitions that appear after will override the import).

If this is a concern, name variables with a prefix manually:

```jake
# docker.jake
docker_port = "5432"
docker_image = "postgres:16"
```

## Project Organization

```
project/
├── Jakefile
└── jake/
    ├── docker.jake
    ├── deploy.jake
    └── test.jake
```

```jake
# Jakefile
@import "jake/docker.jake" as docker
@import "jake/deploy.jake" as deploy
@import "jake/test.jake" as test

@default
task all: [docker.build, test.unit, deploy.staging]
    echo "Done!"
```

## Path Resolution

Import paths are relative to the file containing the `@import`, not the project root.

If `Jakefile` imports `lib/build.jake`, and `lib/build.jake` imports `../shared/utils.jake`, that resolves relative to `lib/` — giving `shared/utils.jake` from the project root. Absolute paths are used as-is.

This means you can safely reorganize your module hierarchy without breaking relative paths inside each module.

## Rooted Modules (`@rooted`)

Import paths resolve relative to the importing file, but by default an imported recipe's **runtime** relative paths (`@cd`, `file` targets, relative paths in command bodies) resolve against the **root** Jakefile's directory. This is what you want for a helper module in `jake/` that references repo-root paths like `crates/...`.

To compose independent sub-projects instead — a `workspace` meta-repo whose sub-directories each carry their own self-contained `Jakefile` — declare `@rooted` at the top of the sub-project file. Its recipes then resolve relative paths against **its own** directory:

```jake
# services/api/Jakefile
@rooted

task build:
    cargo build          # runs in services/api/

file dist/bundle.js: src/*.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js   # dist/ under services/api/
```

```jake
# workspace Jakefile
@import "services/api/Jakefile" as api

task build: [api.build]
    echo "Workspace build complete"
```

`@rooted` takes no arguments and is backward-compatible — files without it keep the default root-relative behaviour. A `@cd <dir>` inside a rooted module is resolved relative to the module directory. Running a `@rooted` file directly as the root Jakefile is a no-op.

### Forcing `rooted` at the import site

When you don't own the sub-project's `Jakefile` — a vendored tool or a git submodule you'd rather not modify — force rooting from the importer's side with a trailing `rooted` modifier:

```jake
@import "vendored/tool/Jakefile" as tool rooted
@import "sub/Jakefile" rooted            # also valid without `as`
```

Rooting is **additive**: a module is rooted if its file declares `@rooted` **or** an import directive says `rooted` (both present is fine). There is no `unrooted` — a module that declares `@rooted` itself can't be forced back to root-relative.

## @dotenv in Imported Files

`@dotenv` paths in imported files are resolved relative to the **working directory** (where `jake` is invoked), not relative to the imported file's location.

```jake
# lib/build.jake
@dotenv ".env"    # loads ./.env from project root, not lib/.env
@dotenv "lib/.env" # loads lib/.env — use this if that's what you mean
```

If a module expects its own `.env` file, use a path relative to the project root when writing the `@dotenv` directive.

## Circular and Diamond Imports

**Circular imports are an error.** If file A imports file B and file B imports file A, Jake detects the cycle and stops with an error. The same applies to longer chains (A → B → C → A).

**Diamond imports work.** If A imports B and C, and both B and C import D, Jake processes D once and skips it on the second encounter. You won't get duplicate recipes or hooks from being imported via multiple paths.

## Example

**jake/docker.jake:**

```jake
docker_image = "myapp"

task build:
    docker build -t {{docker_image}} .

task push:
    docker push {{docker_image}}
```

**Jakefile:**

```jake
@import "jake/docker.jake" as docker

task release: [build, docker.build, docker.push]
    echo "Released {{docker_image}}!"  # docker_image is available here too
```
