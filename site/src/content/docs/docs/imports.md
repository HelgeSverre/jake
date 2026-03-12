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

| What | Behavior |
| ---- | -------- |
| Recipes | Merged; prefix applied if `as name` is used |
| Variables | Merged globally, no prefix — last definition wins |
| Directives (`@dotenv`, `@export`, `@require`) | Merged and applied globally |
| Global hooks (`@pre`, `@post`, `@on_error`) | Merged and apply to all recipes in the project |

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
