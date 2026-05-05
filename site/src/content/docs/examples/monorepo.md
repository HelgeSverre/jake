---
title: Monorepo Management
description: Organize and build multi-package projects with imports and namespacing.
---

Manage complex monorepo projects with imports, namespacing, and parallel builds.

## Project Structure

```
monorepo/
├── Jakefile              # Root orchestrator
├── jake/
│   ├── common.jake       # Shared utilities
│   ├── web.jake          # Web app tasks
│   ├── api.jake          # API tasks
│   ├── mobile.jake       # Mobile app tasks
│   └── infra.jake        # Infrastructure tasks
├── packages/
│   ├── web/
│   ├── api/
│   ├── mobile/
│   └── shared/
└── infrastructure/
```

## Root Jakefile

```jake
# Monorepo Jakefile
# =================

@import "jake/common.jake"
@import "jake/web.jake" as web
@import "jake/api.jake" as api
@import "jake/mobile.jake" as mobile
@import "jake/infra.jake" as infra

@dotenv
# @export values are passed verbatim — they don't expand {{...}}.
# Set MONOREPO_ROOT inline on the commands that need it, e.g.
#   MONOREPO_ROOT=$(pwd) ./script.sh

@pre echo "=== Monorepo Build System ==="

# === Full Builds ===

@default
@description "Build all packages"
task all: [web.build, api.build, mobile.build]
    echo "All packages built!"

@description "Build all packages in parallel"
task all-parallel:
    jake -j4 web.build api.build mobile.build
    echo "Parallel build complete!"

# === Development ===

@description "Start all dev servers"
task dev:
    @pre echo "Starting development environment..."
    jake web.dev &
    jake api.dev &
    wait
    echo "All dev servers running"

@description "Start web dev server only"
task dev-web: [web.dev]

@description "Start API dev server only"
task dev-api: [api.dev]

# === Testing ===

@description "Run all tests"
task test: [web.test, api.test, mobile.test]
    echo "All tests passed!"

@description "Test only affected packages"
task test-affected:
    @pre echo "Determining affected packages..."
    @if exists(packages/web)
        git diff --name-only HEAD~1 | grep -q "^packages/web" && jake web.test || true
    @end
    @if exists(packages/api)
        git diff --name-only HEAD~1 | grep -q "^packages/api" && jake api.test || true
    @end
    echo "Affected tests complete"

# === Linting & Formatting ===

@description "Lint all packages"
task lint: [web.lint, api.lint, mobile.lint]
    echo "All packages linted!"

@description "Format all packages"
task format: [web.format, api.format, mobile.format]
    echo "All packages formatted!"

# === Deployment ===

@description "Deploy all to staging"
task deploy-staging: [web.deploy-staging, api.deploy-staging]
    echo "Deployed to staging!"

@description "Deploy all to production"
task deploy-production: [web.deploy-production, api.deploy-production]
    @confirm "Deploy ALL packages to production?"
    echo "Deployed to production!"

# === Infrastructure ===

@description "Plan infrastructure changes"
task infra-plan: [infra.plan]

@description "Apply infrastructure changes"
task infra-apply: [infra.apply]

# === Utilities ===

@description "Clean all packages"
task clean: [web.clean, api.clean, mobile.clean]
    echo "All packages cleaned!"

@description "Install all dependencies"
task install:
    @needs npm
    npm install
    @each packages/web packages/api packages/mobile packages/shared
        @cd {{item}}
            npm install
    @end
    echo "All dependencies installed!"

@description "Update dependencies in all packages"
task deps-update:
    @needs npx
    npx ncu -u
    @each packages/web packages/api packages/mobile packages/shared
        @cd {{item}}
            npx ncu -u
    @end
    echo "Run 'jake install' to install updated deps"

# === CI/CD ===

@description "Full CI pipeline"
task ci: [install, lint, test, all]
    echo "CI passed!"

@description "CI for affected packages only"
task ci-affected:
    jake install
    jake test-affected
    echo "Affected CI passed!"
```

## Package Jakefiles

### jake/web.jake

```jake
# Web Package Tasks

root = "packages/web"

@description "Build web app"
task build:
    @cd {{root}}
        npm run build
    echo "Web app built"

@description "Start web dev server"
task dev:
    @cd {{root}}
        npm run dev

@description "Run web tests"
task test:
    @cd {{root}}
        npm test

@description "Lint web code"
task lint:
    @cd {{root}}
        npm run lint

@description "Format web code"
task format:
    @cd {{root}}
        npm run format

task clean:
    rm -rf {{root}}/dist
    rm -rf {{root}}/.next
    echo "Web cleaned"

task deploy-staging:
    @cd {{root}}
        npm run deploy:staging
    echo "Web deployed to staging"

task deploy-production:
    @confirm "Deploy web to production?"
    @cd {{root}}
        npm run deploy:production
    echo "Web deployed to production"
```

### jake/api.jake

```jake
# API Package Tasks

root = "packages/api"

@description "Build API"
task build:
    @cd {{root}}
        npm run build
    echo "API built"

@description "Start API dev server"
task dev:
    @cd {{root}}
        npm run dev

@description "Run API tests"
task test:
    @cd {{root}}
        npm test

@description "Lint API code"
task lint:
    @cd {{root}}
        npm run lint

@description "Format API code"
task format:
    @cd {{root}}
        npm run format

task clean:
    rm -rf {{root}}/dist
    echo "API cleaned"

@description "Run API migrations"
task migrate:
    @cd {{root}}
        npm run migrate

task deploy-staging:
    @cd {{root}}
        npm run deploy:staging
    echo "API deployed to staging"

task deploy-production:
    @confirm "Deploy API to production?"
    @cd {{root}}
        npm run deploy:production
    echo "API deployed to production"
```

## Usage

```bash
jake                        # Build all packages
jake -j4 all                # Build all in parallel
jake dev                    # Start all dev servers
jake web.build              # Build just web
jake api.test               # Test just API
jake test-affected          # Test only changed packages
jake deploy-production      # Deploy everything
```

## Key Features

### Namespaced Imports

Access package tasks with prefixes:

```jake
@import "jake/web.jake" as web
@import "jake/api.jake" as api

task all: [web.build, api.build]
```

### Parallel Builds

Run independent builds simultaneously:

```bash
jake -j4 all  # 4 parallel workers
```

Or explicitly in the Jakefile:

```jake
task all-parallel:
    jake -j4 web.build api.build mobile.build
```

### Affected Package Detection

Only test/build changed packages:

```jake
task test-affected:
    git diff --name-only HEAD~1 | grep -q "^packages/web" && jake web.test
```

### Shared Configuration

Use `@export` to share variables:

```jake
@export MONOREPO_ROOT={{absolute_path(.)}}
```

### Per-Package Working Directory

Execute commands in package directories:

```jake
task build:
    @cd packages/web
        npm run build
```

## Customization

### Adding a New Package

1. Create `jake/newpackage.jake`
2. Import it in root Jakefile:
   ```jake
   @import "jake/newpackage.jake" as newpackage
   ```
3. Add to composite tasks:
   ```jake
   task all: [web.build, api.build, newpackage.build]
   ```

### Workspace Tools

Integrate with package managers:

```jake
# pnpm workspaces
task install:
    pnpm install

# Turborepo integration
task build:
    npx turbo run build
```

## See Also

- [Imports](/docs/imports/) - Import syntax and namespacing
- [Parallel Execution](/examples/parallel-execution/) - `-j` flag details
