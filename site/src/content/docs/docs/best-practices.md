---
title: Best Practices
description: Tips for writing effective Jakefiles.
---

Follow these guidelines for clean, maintainable Jakefiles.

## 1. Use Descriptive Names

Choose clear, self-documenting names:

```jake
# Good
task build-frontend:
    npm run build

# Avoid
task bf:
    npm run build
```

If you need shortcuts, use aliases:

```jake
task build-frontend | bf:
    npm run build
```

## 2. Set a Default Task

Let users run `jake` without arguments:

```jake
@default
task dev:
    npm run dev
```

## 3. Group Related Tasks

Use section comments and `@group` for organization:

```jake
# === Build ===
@group build
task build: [build-frontend, build-backend]
    echo "Build complete"

@group build
task build-frontend:
    npm run build

@group build
task build-backend:
    cargo build
```

## 4. Use File Targets for Artifacts

Avoid unnecessary rebuilds:

```jake
# Good - only rebuilds when sources change
file dist/app.js: src/**/*.ts
    esbuild src/index.ts --outfile=dist/app.js

# Avoid - rebuilds every time
task build:
    esbuild src/index.ts --outfile=dist/app.js
```

## 5. Use Imports for Organization

Split large Jakefiles into modules:

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
```

## 6. Document Complex Recipes

Add descriptions for non-obvious tasks:

```jake
# Deploy to production
# Requires: AWS credentials, SSH key
# Usage: jake deploy env=production
@desc "Deploy to production servers"
task deploy env="staging":
    @require AWS_ACCESS_KEY_ID
    @confirm "Deploy to {{env}}?"
    ./scripts/deploy.sh {{env}}
```

## 7. Validate Requirements Early

Check dependencies before running commands:

```jake
@needs docker npm node
task build:
    docker build -t myapp .
```

```jake
@require DATABASE_URL API_KEY
task deploy:
    ./deploy.sh
```

## 8. Use Hooks for Setup/Cleanup

Pre-hooks for preparation, post-hooks for cleanup:

```jake
task test:
    @pre docker-compose up -d
    npm test
    @post docker-compose down
```

Post-hooks run even if the recipe fails, making them ideal for cleanup.

## 9. Leverage Parallel Execution

Structure dependencies for parallel builds:

```jake
task frontend:
    npm run build

task backend:
    cargo build

task docs:
    mkdocs build

# All three can run in parallel
task all: [frontend, backend, docs]
    echo "Done!"
```

```bash
jake -j4 all  # 4 parallel workers
```

## 10. Use Private Helpers

Hide implementation details with underscore prefix:

```jake
# Public interface
task build: [_setup, _compile, _bundle]
    echo "Build complete!"

# Hidden implementation
task _setup:
    mkdir -p dist

task _compile:
    tsc

task _bundle:
    esbuild dist/index.js --bundle --outfile=dist/bundle.js
```

## Quick Checklist

- [ ] Default task set with `@default`
- [ ] Descriptive names (with aliases if needed)
- [ ] File targets for build artifacts
- [ ] Requirements validated with `@needs` and `@require`
- [ ] Complex recipes documented with `@desc`
- [ ] Related tasks grouped logically
- [ ] Private helpers prefixed with `_`
- [ ] Cleanup handled with `@post` hooks

## See Also

- [Tasks](/docs/tasks/) - Recipe types and syntax
- [File Targets](/docs/file-targets/) - Incremental builds
- [Imports](/docs/imports/) - Organizing large projects
