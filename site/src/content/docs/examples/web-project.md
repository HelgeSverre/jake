---
title: Web Project
description: Example Jakefile for a typical web project.
---

A complete Jakefile for a modern web project with TypeScript, testing, and deployment.

```jake
# Project configuration
app_name = "myapp"
node_env = "development"

# Load environment variables
@dotenv
@dotenv ".env.local"

# Export for all commands
@export NODE_ENV={{node_env}}

# === Development ===

@default
@description "Start development server"
task dev:
    @needs node npm
    npm run dev

@description "Install dependencies"
task install:
    @if exists(node_modules)
        echo "Dependencies installed, run 'jake install-fresh' to reinstall"
    @else
        npm install
    @end

@description "Clean install dependencies"
task install-fresh:
    rm -rf node_modules
    npm install

# === Build ===

@group build
@description "Compile TypeScript"
file dist/app.js: src/**/*.ts tsconfig.json
    npx tsc

@group build
@description "Bundle CSS"
file dist/styles.css: src/**/*.css
    npx postcss src/index.css -o dist/styles.css

@group build
@description "Build everything"
task build: [dist/app.js, dist/styles.css]
    echo "Build complete!"

# === Testing ===

@group test
@description "Run all tests"
task test:
    npm test

@group test
@description "Run tests in watch mode"
task test-watch:
    npm test -- --watch

@group test
@description "Run linter"
task lint:
    npm run lint

@group test
@description "Type check without emitting"
task typecheck:
    npx tsc --noEmit

@description "Run all checks"
task check: [lint, typecheck, test]
    echo "All checks passed!"

# === Deployment ===

@group deploy
@description "Deploy to production"
task deploy: [build, check]
    @confirm "Deploy to production?"
    @require DEPLOY_TOKEN
    @if env(CI)
        echo "Deploying from CI..."
        ./scripts/deploy.sh
    @else
        echo "Deploying locally..."
        rsync -avz dist/ server:/var/www/{{app_name}}/
    @end

@group deploy
@description "Deploy to staging"
task deploy-staging: [build]
    rsync -avz dist/ staging:/var/www/{{app_name}}/

# === Utilities ===

@description "Remove build artifacts"
task clean:
    rm -rf dist/
    rm -rf .cache/

@description "Remove everything including node_modules"
task clean-all: [clean]
    rm -rf node_modules/

@description "Format code"
task format:
    npx prettier --write "src/**/*.{ts,css,json}"

# === Docker ===

@group docker
@description "Build Docker image"
task docker-build:
    @needs docker
    docker build -t {{app_name}}:latest .

@group docker
@description "Run Docker container"
task docker-run: [docker-build]
    docker run -p 3000:3000 {{app_name}}:latest
```

## Usage

```bash
# Start development
jake dev

# Build project
jake build

# Run all checks before commit
jake check

# Deploy to staging
jake deploy-staging

# Deploy to production
jake deploy

# Clean and rebuild
jake clean && jake build
```
