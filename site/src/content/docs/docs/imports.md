---
title: Imports
description: Organize your Jakefile with imports.
---

## Basic Import

Import all recipes from another file:

```jake
@import "scripts/docker.jake"
```

This makes all recipes from `docker.jake` available.

## Namespaced Import

Import with a prefix to avoid name collisions:

```jake
@import "scripts/deploy.jake" as deploy
```

Access recipes as `deploy.production`, `deploy.staging`, etc.

## Example

**scripts/docker.jake:**

```jake
task build:
    docker build -t myapp .

task push:
    docker push myapp
```

**Jakefile:**

```jake
@import "scripts/docker.jake" as docker

task release: [build, docker.build, docker.push]
    echo "Released!"
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

## Import Resolution

- Paths are relative to the importing file
- Variables from imports are not shared (scoped)
- Recipes from imports can be used as dependencies
