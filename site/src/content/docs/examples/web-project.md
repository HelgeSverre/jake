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

node_env = "development"

# @export values are passed verbatim — {{...}} substitution does not happen
# inside an @export. Set the literal value here, or set NODE_ENV inline on
# the consuming command (e.g. `NODE_ENV={{node_env}} npm start`).
@export NODE_ENV=development

# === Development ===

@default
@desc "Start development server"
task dev:
    @needs node npm
    npm run dev

@desc "Install dependencies"
task install:
    @if exists(node_modules)
        echo "Dependencies installed, run 'jake install-fresh' to reinstall"
    @else
        npm install
    @end

@desc "Clean install dependencies"
task install-fresh:
    rm -rf node_modules
    npm install

# === Build ===

@group build
@desc "Compile TypeScript"
file dist/app.js: src/**/*.ts tsconfig.json
    npx tsc

@group build
@desc "Bundle CSS"
file dist/styles.css: src/**/*.css
    npx postcss src/index.css -o dist/styles.css

@group build
@desc "Build everything"
task build: [dist/app.js, dist/styles.css]
    echo "Build complete!"

# === Testing ===

@group test
@desc "Run all tests"
task test:
    npm test

@group test
@desc "Run tests in watch mode"
task test-watch:
    npm test -- --watch

@group test
@desc "Run linter"
task lint:
    npm run lint

@group test
@desc "Type check without emitting"
task typecheck:
    npx tsc --noEmit

@desc "Run all checks"
task check: [lint, typecheck, test]
    echo "All checks passed!"

# === Deployment ===

@group deploy
@desc "Deploy to production"
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
@desc "Deploy to staging"
task deploy-staging: [build]
    rsync -avz dist/ staging:/var/www/{{app_name}}/

# === Utilities ===

@desc "Remove build artifacts"
task clean:
    rm -rf dist/
    rm -rf .cache/

@desc "Remove everything including node_modules"
task clean-all: [clean]
    rm -rf node_modules/

@desc "Format code"
task format:
    npx prettier --write "src/**/*.{ts,css,json}"

# === Docker ===

@group docker
@desc "Build Docker image"
task docker-build:
    @needs docker
    docker build -t {{app_name}}:latest .

@group docker
@desc "Run Docker container"
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
