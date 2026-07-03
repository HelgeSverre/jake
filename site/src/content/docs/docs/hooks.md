---
title: Hooks
description: Pre and post hooks in Jake.
---

Hooks let you run commands before or after recipe execution — for setup, cleanup, notifications, and error recovery. There are three scopes: global (all recipes), targeted (one specific recipe), and recipe-internal (defined inside the recipe body).

## Common Use Cases

**Service lifecycle** — Spin up dependencies before a task and tear them down after, regardless of whether the task succeeds.

```jake
task test:
    @pre docker-compose up -d
    npm test
    @post docker-compose down
```

**Deployment notifications** — Post to Slack, send a webhook, or update a status page after a deploy finishes or fails.

```jake
@after deploy curl -s -X POST $SLACK_WEBHOOK -d '{"text":"Deploy complete"}'

task deploy:
    ./deploy.sh
    @on_error curl -s -X POST $SLACK_WEBHOOK -d '{"text":"Deploy FAILED"}'
```

**Automatic rollback** — Trigger a rollback script if a deploy or migration fails.

```jake
task deploy:
    ./deploy.sh --env production
    @on_error ./scripts/rollback.sh --env production

task migrate:
    psql $DATABASE_URL -f migrations/up.sql
    @on_error psql $DATABASE_URL -f migrations/rollback.sql
```

**Environment validation** — Check that required tools, credentials, or conditions exist before a recipe runs. Because pre-hook failures stop execution, this acts as a clean gate.

```jake
@before deploy ./scripts/check-env.sh
@before release git diff --exit-code  # fail if there are uncommitted changes
```

**Timing and audit logs** — Record when tasks start and finish, useful in CI logs or for auditing long-running pipelines.

```jake
@pre echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting {{JAKE_RECIPE}}"
@post echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Finished {{JAKE_RECIPE}}"
```

**Artifact cleanup** — Remove temp files or caches after a build, whether it succeeded or not.

```jake
task build:
    npm run build
    @post rm -rf .tmp/ .cache/
```

**Cross-cutting CI concerns** — Apply behaviors to multiple recipes without touching each one. Define them at the top of your Jakefile or in an imported module.

```jake
@before build   ./scripts/ensure-node-version.sh
@before test    ./scripts/ensure-node-version.sh
@before release ./scripts/ensure-node-version.sh
```

## Which Hook to Use

The choice between hook types is mostly about ownership: does the hook belong to the recipe, or is it an external concern?

**Recipe-internal `@pre` / `@post`** — Use inside a recipe body when the hook is tightly coupled to that task and should always run with it. The hook moves with the recipe, stays visible in the recipe definition, and is part of its contract.

```jake
task test:
    @pre docker-compose up -d    # always runs before test
    npm test
    @post docker-compose down    # always runs after test
```

**Targeted `@before` / `@after`** — Use at the top level to attach behavior to a recipe you don't want to modify. Useful for project-level conventions, CI-specific steps, or cross-cutting concerns defined in an imported file.

```jake
@before deploy echo "Checking deploy prerequisites..."
@after deploy notify "Deployment complete"
```

**Global `@pre` / `@post`** — Use when you want something to run regardless of which recipe is invoked.

```jake
@pre echo "=== Starting ==="
@post echo "=== Done ==="
```

## Execution Order

For any recipe that runs, hooks fire in this order:

1. Global `@pre` hooks
2. `@before` hooks targeting this recipe
3. Recipe `@pre` hooks (inside recipe body)
4. Recipe commands
5. Recipe `@post` hooks (inside recipe body)
6. `@after` hooks targeting this recipe
7. Global `@post` hooks
8. `@on_error` hooks (only if the recipe failed)

## Error Hooks

`@on_error` runs when a recipe fails. Use it for notifications, cleanup that shouldn't run on success, or logging.

**Global** — top-level `@on_error` runs whenever any recipe fails:

```jake
@on_error echo "Build failed — check logs at ./build.log"
@on_error notify "CI failure on {{BRANCH}}"
```

**Recipe-local** — body-level `@on_error` inside a recipe runs only when that recipe fails:

```jake
task deploy:
    ./deploy.sh
    @on_error rollback --last
```

## Failure Behavior

Hook failures are handled differently depending on the hook type.

**Pre-hooks** — if a pre-hook fails, execution stops immediately. The recipe commands don't run, and no post-hooks fire.

**Post-hooks** — all post-hooks always run, even if the recipe failed or an earlier post-hook failed. Errors are collected internally and the first one is returned after all post-hooks complete. This makes post-hooks reliable for cleanup — a failing notification hook won't prevent a Docker container from being stopped.

**`@on_error` hooks** — failures are silently ignored. If your error hook itself errors, execution continues normally. Don't rely on `@on_error` hooks for anything that must succeed.

## Hooks in Parallel Execution

When running with `-j` (parallel execution), hooks fire per recipe, not globally for the parallel batch. Each recipe's pre/post cycle runs in the thread executing that recipe. Global `@pre` and `@post` hooks still run for every recipe — they're not deduplicated across parallel runs.

## Variable Expansion in Hooks

Hook commands support the same `{{variable}}` expansion as recipe commands:

```jake
app = "myapp"

@before deploy echo "Deploying {{app}} to production..."
@after deploy notify "{{app}} deployment complete"

task deploy:
    ./deploy.sh
    @on_error notify "{{app}} deployment failed!"
```
