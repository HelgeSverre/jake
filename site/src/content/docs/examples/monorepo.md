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
@export MONOREPO_ROOT={{absolute_path(.)}}

@pre echo "=== Monorepo Build System ==="

# === Full Builds ===

@default
task all: [web.build, api.build, mobile.build]
    @description "Build all packages"
    echo "All packages built!"

task all-parallel:
    @description "Build all packages in parallel"
    jake -j4 web.build api.build mobile.build
    echo "Parallel build complete!"

# === Development ===

task dev:
    @description "Start all dev servers"
    @pre echo "Starting development environment..."
    jake web.dev &
    jake api.dev &
    wait
    echo "All dev servers running"

task dev-web: [web.dev]
    @description "Start web dev server only"

task dev-api: [api.dev]
    @description "Start API dev server only"

# === Testing ===

task test: [web.test, api.test, mobile.test]
    @description "Run all tests"
    echo "All tests passed!"

task test-affected:
    @description "Test only affected packages"
    @pre echo "Determining affected packages..."
    @if exists(packages/web)
        git diff --name-only HEAD~1 | grep -q "^packages/web" && jake web.test || true
    @end
    @if exists(packages/api)
        git diff --name-only HEAD~1 | grep -q "^packages/api" && jake api.test || true
    @end
    echo "Affected tests complete"

# === Linting & Formatting ===

task lint: [web.lint, api.lint, mobile.lint]
    @description "Lint all packages"
    echo "All packages linted!"

task format: [web.format, api.format, mobile.format]
    @description "Format all packages"
    echo "All packages formatted!"

# === Deployment ===

task deploy-staging: [web.deploy-staging, api.deploy-staging]
    @description "Deploy all to staging"
    echo "Deployed to staging!"

task deploy-production: [web.deploy-production, api.deploy-production]
    @description "Deploy all to production"
    @confirm "Deploy ALL packages to production?"
    echo "Deployed to production!"

# === Infrastructure ===

task infra-plan: [infra.plan]
    @description "Plan infrastructure changes"

task infra-apply: [infra.apply]
    @description "Apply infrastructure changes"

# === Utilities ===

task clean: [web.clean, api.clean, mobile.clean]
    @description "Clean all packages"
    echo "All packages cleaned!"

task install:
    @description "Install all dependencies"
    @needs npm
    npm install
    @each packages/web packages/api packages/mobile packages/shared
        @cd {{item}}
            npm install
    @end
    echo "All dependencies installed!"

task deps-update:
    @description "Update dependencies in all packages"
    @needs npx
    npx ncu -u
    @each packages/web packages/api packages/mobile packages/shared
        @cd {{item}}
            npx ncu -u
    @end
    echo "Run 'jake install' to install updated deps"

# === CI/CD ===

task ci: [install, lint, test, all]
    @description "Full CI pipeline"
    echo "CI passed!"

task ci-affected:
    @description "CI for affected packages only"
    jake install
    jake test-affected
    echo "Affected CI passed!"
```

## Package Jakefiles

### jake/web.jake

```jake
# Web Package Tasks

root = "packages/web"

task build:
    @description "Build web app"
    @cd {{root}}
        npm run build
    echo "Web app built"

task dev:
    @description "Start web dev server"
    @cd {{root}}
        npm run dev

task test:
    @description "Run web tests"
    @cd {{root}}
        npm test

task lint:
    @description "Lint web code"
    @cd {{root}}
        npm run lint

task format:
    @description "Format web code"
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

task build:
    @description "Build API"
    @cd {{root}}
        npm run build
    echo "API built"

task dev:
    @description "Start API dev server"
    @cd {{root}}
        npm run dev

task test:
    @description "Run API tests"
    @cd {{root}}
        npm test

task lint:
    @description "Lint API code"
    @cd {{root}}
        npm run lint

task format:
    @description "Format API code"
    @cd {{root}}
        npm run format

task clean:
    rm -rf {{root}}/dist
    echo "API cleaned"

task migrate:
    @description "Run API migrations"
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
