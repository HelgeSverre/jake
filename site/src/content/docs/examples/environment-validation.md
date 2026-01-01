---
title: Environment Validation
description: Validate tools and environment before running tasks.
---

Catch missing dependencies and configuration issues early with validation directives.

```jake
# Load environment files
@dotenv
@dotenv ".env.local"

# Require specific environment variables at parse time
@require DATABASE_URL
@require API_KEY

@desc "Deploy to production"
task deploy:
    # Validate tools are installed
    @needs docker kubectl helm

    # Validate environment variables for this task
    @require KUBECONFIG
    @require DOCKER_REGISTRY

    # Require confirmation for dangerous operations
    @confirm Deploy to production cluster?

    # Build and push
    docker build -t $DOCKER_REGISTRY/app:latest .
    docker push $DOCKER_REGISTRY/app:latest

    # Deploy to Kubernetes
    helm upgrade --install myapp ./helm/myapp

@desc "Deploy to staging (no confirmation needed)"
task deploy-staging:
    @needs docker kubectl
    @require STAGING_KUBECONFIG
    docker build -t staging-registry/app:latest .
    docker push staging-registry/app:latest
    KUBECONFIG=$STAGING_KUBECONFIG kubectl apply -f k8s/staging/

@desc "Run database migrations"
task migrate:
    @needs psql
    @require DATABASE_URL
    @confirm Run database migrations?
    psql $DATABASE_URL -f migrations/latest.sql

@desc "Backup database before deployment"
task backup:
    @needs pg_dump
    @require DATABASE_URL
    @require BACKUP_BUCKET
    pg_dump $DATABASE_URL > backup-$(date +%Y%m%d).sql
    aws s3 cp backup-*.sql s3://$BACKUP_BUCKET/
```

## Validation Directives

### `@needs` - Validate Tool Availability

Check that commands are available in PATH:

```jake
@needs docker          # Fails if docker not found
@needs cargo rust      # Multiple tools
@needs hyperfine "brew install hyperfine"  # With install hint
```

### `@require` - Validate Environment Variables

Ensure environment variables are set:

```jake
@require API_KEY       # Fails if API_KEY not set
@require DB_HOST DB_PORT DB_NAME  # Multiple variables
```

### `@confirm` - User Confirmation

Prompt before dangerous operations:

```jake
@confirm Delete all data?     # Prompts with y/n
@confirm Deploy to prod?
```

Use `-y` flag to auto-confirm all prompts:

```bash
jake -y deploy  # Skips all @confirm prompts
```

## Error Messages

When validation fails, Jake provides helpful error messages:

```
$ jake deploy
error: Required command not found: kubectl
hint: Install with: brew install kubectl

$ jake migrate
error: Required environment variable not set: DATABASE_URL
```

## Platform-Specific Validation

Combine with conditionals for platform-aware validation:

```jake
@desc "Platform-specific setup"
task setup:
    @if os(macos)
        @needs brew
        brew install dependencies
    @elif os(linux)
        @needs apt-get
        sudo apt-get install dependencies
    @end
```
