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
task dev:
    @description "Start development server"
    @needs node npm
    npm run dev

task install:
    @description "Install dependencies"
    @if exists(node_modules)
        echo "Dependencies installed, run 'jake install-fresh' to reinstall"
    @else
        npm install
    @end

task install-fresh:
    @description "Clean install dependencies"
    rm -rf node_modules
    npm install

# === Build ===

@group build
file dist/app.js: src/**/*.ts tsconfig.json
    @description "Compile TypeScript"
    npx tsc

@group build
file dist/styles.css: src/**/*.css
    @description "Bundle CSS"
    npx postcss src/index.css -o dist/styles.css

@group build
task build: [dist/app.js, dist/styles.css]
    @description "Build everything"
    echo "Build complete!"

# === Testing ===

@group test
task test:
    @description "Run all tests"
    npm test

@group test
task test-watch:
    @description "Run tests in watch mode"
    npm test -- --watch

@group test
task lint:
    @description "Run linter"
    npm run lint

@group test
task typecheck:
    @description "Type check without emitting"
    npx tsc --noEmit

task check: [lint, typecheck, test]
    @description "Run all checks"
    echo "All checks passed!"

# === Deployment ===

@group deploy
task deploy: [build, check]
    @description "Deploy to production"
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
task deploy-staging: [build]
    @description "Deploy to staging"
    rsync -avz dist/ staging:/var/www/{{app_name}}/

# === Utilities ===

task clean:
    @description "Remove build artifacts"
    rm -rf dist/
    rm -rf .cache/

task clean-all: [clean]
    @description "Remove everything including node_modules"
    rm -rf node_modules/

task format:
    @description "Format code"
    npx prettier --write "src/**/*.{ts,css,json}"

# === Docker ===

@group docker
task docker-build:
    @description "Build Docker image"
    @needs docker
    docker build -t {{app_name}}:latest .

@group docker
task docker-run: [docker-build]
    @description "Run Docker container"
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
