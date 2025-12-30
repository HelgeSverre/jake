---
title: Hooks
description: Pre and post hooks in Jake.
---

## Global Hooks

Run before/after any recipe:

```jake
@pre echo "=== Starting Jake ==="
@post echo "=== Jake Complete ==="
```

## Recipe Hooks

Run before/after a specific recipe:

```jake
task deploy:
    @pre echo "Pre-deploy checks..."
    rsync dist/ server:/var/www/
    @post echo "Deploy notification sent"
```

## Targeted Hooks

Target specific recipes without modifying them:

```jake
# Run before the "build" recipe only
@before build echo "Checking dependencies..."

# Run after the "deploy" recipe only
@after deploy notify "Deployment complete"

# Multiple targeted hooks
@before test docker-compose up -d
@after test docker-compose down
```

## Error Hooks

Run commands when any recipe fails:

```jake
@on_error echo "Recipe failed! Check logs."
@on_error notify "Build failed - see logs"
```

## Post-hooks Always Run

Post-hooks run even if the recipe fails, making them ideal for cleanup:

```jake
task test:
    @pre docker-compose up -d
    npm test
    @post docker-compose down
```

## Execution Order

1. Global `@pre` hooks
2. `@before` hooks targeting this recipe
3. Recipe `@pre` hooks (inside recipe)
4. Recipe commands
5. Recipe `@post` hooks (inside recipe)
6. `@after` hooks targeting this recipe
7. Global `@post` hooks
8. `@on_error` hooks (only if recipe failed)
