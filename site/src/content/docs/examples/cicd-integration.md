---
title: CI/CD Integration
description: Integrate Jake with GitHub Actions and other CI/CD systems.
---

Jake works seamlessly with GitHub Actions and other CI systems, providing consistent local and CI builds.

## Complete Jakefile

```jake
# CI/CD Jakefile
# ==============

@dotenv
@export CI=true

# === Local CI Simulation ===

@default
task ci: [install, lint, typecheck, test, build]
    @description "Run full CI pipeline locally"
    echo "CI pipeline passed!"

task install:
    @description "Install dependencies"
    @needs npm
    @if env(CI)
        npm ci
    @else
        npm install
    @end

task lint:
    @description "Run linters"
    @needs npm
    npm run lint

task typecheck:
    @description "Type checking"
    @needs npm
    npm run typecheck

task test:
    @description "Run tests"
    @needs npm
    @if env(CI)
        npm test -- --coverage --ci
    @else
        npm test
    @end

task build:
    @description "Production build"
    @needs npm
    npm run build

# === Environment-Based Deployment ===

task deploy:
    @description "Deploy to appropriate environment"
    @if env(GITHUB_REF_NAME)
        @if eq($GITHUB_REF_NAME, main)
            echo "Deploying to production..."
            jake deploy-production
        @elif eq($GITHUB_REF_NAME, staging)
            echo "Deploying to staging..."
            jake deploy-staging
        @else
            echo "Deploying to preview..."
            jake deploy-preview
        @end
    @else
        echo "Not in CI - use deploy-staging or deploy-production directly"
    @end

task deploy-staging:
    @description "Deploy to staging"
    @require STAGING_URL VERCEL_TOKEN
    @needs npx
    npx vercel deploy --prebuilt --token=$VERCEL_TOKEN
    echo "Deployed to staging: $STAGING_URL"

task deploy-production:
    @description "Deploy to production"
    @require PRODUCTION_URL VERCEL_TOKEN
    @confirm "Deploy to production?"
    @needs npx
    npx vercel deploy --prebuilt --prod --token=$VERCEL_TOKEN
    @post echo "Deployed to production: $PRODUCTION_URL"

task deploy-preview:
    @description "Deploy preview environment"
    @require VERCEL_TOKEN
    @needs npx
    npx vercel deploy --prebuilt --token=$VERCEL_TOKEN
    echo "Preview deployed"

# === GitHub Actions Helpers ===

task gha-summary:
    @description "Write summary for GitHub Actions"
    @if env(GITHUB_STEP_SUMMARY)
        echo "## Build Summary" >> $GITHUB_STEP_SUMMARY
        echo "- Commit: $GITHUB_SHA" >> $GITHUB_STEP_SUMMARY
        echo "- Branch: $GITHUB_REF_NAME" >> $GITHUB_STEP_SUMMARY
        echo "- Runner: $RUNNER_OS" >> $GITHUB_STEP_SUMMARY
    @end

task gha-cache-key:
    @description "Generate cache key for GitHub Actions"
    @quiet
    echo "npm-$RUNNER_OS-$(shasum package-lock.json | cut -c1-8)"

# === Health Checks ===

task health-check:
    @description "Check deployment health"
    @require HEALTH_URL
    @pre echo "Checking health at $HEALTH_URL..."
    curl -sf "$HEALTH_URL/health" || (echo "Health check failed!" && exit 1)
    @post echo "Health check passed!"

task smoke-test:
    @description "Run smoke tests against deployment"
    @require TEST_URL
    npm run test:e2e -- --url=$TEST_URL

# === Rollback ===

task rollback:
    @description "Rollback production deployment"
    @require PREVIOUS_DEPLOY_ID VERCEL_TOKEN
    @confirm "Rollback production to $PREVIOUS_DEPLOY_ID?"
    npx vercel rollback $PREVIOUS_DEPLOY_ID --token=$VERCEL_TOKEN
    echo "Rolled back to $PREVIOUS_DEPLOY_ID"

# === Notifications ===

task notify-success:
    @description "Send success notification"
    @if env(SLACK_WEBHOOK)
        curl -X POST -H 'Content-type: application/json' \
            --data '{"text":"Deployment succeeded: '$GITHUB_REF_NAME'"}' \
            $SLACK_WEBHOOK
    @end

task notify-failure:
    @description "Send failure notification"
    @if env(SLACK_WEBHOOK)
        curl -X POST -H 'Content-type: application/json' \
            --data '{"text":"Deployment FAILED: '$GITHUB_REF_NAME'"}' \
            $SLACK_WEBHOOK
    @end
```

## Usage

```bash
jake ci                 # Full CI pipeline locally
jake deploy             # Environment-based deployment
jake health-check       # Check deployment health
jake rollback           # Rollback production
```

## GitHub Actions Workflow

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main, staging]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"

      - name: Install Jake
        run: |
          curl -fsSL jakefile.dev/install.sh | sh
          echo "$HOME/.local/bin" >> $GITHUB_PATH

      - name: Run CI Pipeline
        run: jake ci
        env:
          CI: true

      - name: Deploy
        if: github.ref == 'refs/heads/main'
        run: jake deploy
        env:
          VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
          PRODUCTION_URL: ${{ vars.PRODUCTION_URL }}

      - name: Notify
        if: always()
        run: |
          if [ ${{ job.status }} == 'success' ]; then
            jake notify-success
          else
            jake notify-failure
          fi
        env:
          SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}
```

## Key Features

### CI-Aware Commands

Adjust behavior based on environment:

```jake
task install:
    @if env(CI)
        npm ci        # Faster, stricter
    @else
        npm install   # Development friendly
    @end
```

### Branch-Based Deployment

Automatic environment selection:

```jake
@if eq($GITHUB_REF_NAME, main)
    jake deploy-production
@elif eq($GITHUB_REF_NAME, staging)
    jake deploy-staging
@else
    jake deploy-preview
@end
```

### GitHub Actions Integration

Write to step summary and generate cache keys:

```jake
task gha-summary:
    @if env(GITHUB_STEP_SUMMARY)
        echo "## Build Summary" >> $GITHUB_STEP_SUMMARY
    @end
```

### Post-Deployment Verification

Health checks after deployment:

```jake
task health-check:
    curl -sf "$HEALTH_URL/health" || exit 1
```

## Local vs CI

The same Jakefile works in both environments:

```bash
# Locally
jake ci        # Simulates full CI pipeline

# In CI
jake ci        # Runs identical checks
jake deploy    # Deploys based on branch
```

## See Also

- [Conditionals](/docs/conditionals/) - Environment-based logic
- [Environment Validation](/examples/environment-validation/) - `@require` for secrets
