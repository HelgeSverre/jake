# The Complete Guide to Jakefiles: From Chaos to Workflow Mastery

_Tame your build system, automate everything, and actually enjoy your development workflows._

---

**Time to complete:** 45-60 minutes (or jump to specific sections)
**Prerequisites:** Basic command-line knowledge, familiarity with build tools (Make, npm scripts, etc.)
**What you'll build:** A complete understanding of Jake, with real-world Jakefiles you can adapt to your projects

---

## Table of Contents

1. [Why Jake? The Build Tool You Didn't Know You Needed](#why-jake)
2. [Installation](#installation)
3. [Your First Jakefile in 60 Seconds](#your-first-jakefile)
4. [Core Concepts: Tasks, Files, and Dependencies](#core-concepts)
5. [Real-World Scenarios](#real-world-scenarios)
   - [Web Development Workflows](#web-development-workflows)
   - [Open Source Project Maintenance](#open-source-project-maintenance)
   - [Git Workflow Automation](#git-workflow-automation)
   - [Docker and Container Workflows](#docker-and-container-workflows)
   - [CI/CD Integration](#cicd-integration)
   - [Database and Backend Tasks](#database-and-backend-tasks)
   - [Monorepo Management](#monorepo-management)
6. [Advanced Patterns](#advanced-patterns)
7. [Migrating from Make or Just](#migrating-from-make-or-just)
8. [Tips and Best Practices](#tips-and-best-practices)
9. [Quick Reference Card](#quick-reference-card)

---

## Why Jake? The Build Tool You Didn't Know You Needed {#why-jake}

Let's be honest: build tools are not exciting. But a _bad_ build tool? That's hours of your life you'll never get back, staring at cryptic error messages or waiting for unnecessary rebuilds.

**Make** has been around since 1976. It's powerful, battle-tested, and... arcane. Tab vs. spaces matters. `$@` and `$<` are "intuitive." Error messages feel like riddles from a sphinx.

**Just** came along and said "what if Makefiles were actually readable?" It's wonderful for task running, but it doesn't track file dependencies. Every rebuild is a full rebuild.

**Jake** asks: "Why not both?"

| Feature                   | Make | Just | Jake |
| ------------------------- | :--: | :--: | :--: |
| File-based dependencies   | Yes  |  No  | Yes  |
| Clean, readable syntax    |  No  | Yes  | Yes  |
| Parallel execution        | Yes  |  No  | Yes  |
| Glob patterns (`**/*.ts`) |  No  |  No  | Yes  |
| Import system             |  No  | Yes  | Yes  |
| Conditionals              |  No  | Yes  | Yes  |
| Pre/post hooks            |  No  |  No  | Yes  |
| `.env` loading            |  No  | Yes  | Yes  |
| Helpful error messages    |  No  | Yes  | Yes  |

Jake gives you Make's power with Just's ergonomics, then adds features neither has. Let's dive in.

---

## Installation {#installation}

### Pre-built Binaries (Easiest)

Download from [GitHub Releases](https://github.com/HelgeSverre/jake/releases):

```bash
# Linux (x86_64)
curl -L https://github.com/HelgeSverre/jake/releases/latest/download/jake-x86_64-linux -o jake
chmod +x jake
sudo mv jake /usr/local/bin/

# macOS (Apple Silicon)
curl -L https://github.com/HelgeSverre/jake/releases/latest/download/jake-aarch64-macos -o jake
chmod +x jake
sudo mv jake /usr/local/bin/

# macOS (Intel)
curl -L https://github.com/HelgeSverre/jake/releases/latest/download/jake-x86_64-macos -o jake
chmod +x jake
sudo mv jake /usr/local/bin/
```

### From Source

Requires [Zig](https://ziglang.org/) 0.15.2 or later:

```bash
git clone https://github.com/HelgeSverre/jake.git
cd jake
zig build -Doptimize=ReleaseFast
cp zig-out/bin/jake ~/.local/bin/
```

### Verify Installation

```bash
$ jake --version
jake 0.3.0
```

---

## Your First Jakefile in 60 Seconds {#your-first-jakefile}

Create a file named `Jakefile` (no extension) in your project root:

```jake
# My first Jakefile
task hello:
    echo "Hello from Jake!"
```

Run it:

```bash
$ jake hello
-> hello
Hello from Jake!
```

That's it. No tabs vs. spaces headaches. No `.PHONY` declarations. Just define a task and run it.

> **Pro Tip:** You can run `jake` from any subdirectory of your project. Jake automatically searches parent directories for a `Jakefile` and runs from that directory. This means `jake build` works whether you're in `~/project/` or `~/project/src/components/`.

### Adding a Default Task

```jake
@default
task build:
    echo "Building..."
    mkdir -p dist
    echo "Build complete!"

task test: [build]
    echo "Running tests..."
    echo "All tests passed!"
```

Now `jake` with no arguments runs `build`. And `jake test` automatically runs `build` first because of the `[build]` dependency.

```bash
$ jake test
-> build
Building...
Build complete!
-> test
Running tests...
All tests passed!
```

> **Key Insight:** Dependencies in `[brackets]` run _before_ the task. Jake figures out the right order, skips duplicates, and can even run independent tasks in parallel.

---

## Core Concepts: Tasks, Files, and Dependencies {#core-concepts}

Jake has three fundamental building blocks. Understanding when to use each is the key to effective Jakefiles.

### Task Recipes: "Do This Every Time"

Use `task` for commands that should _always_ execute when called:

```jake
task clean:
    rm -rf dist/
    rm -rf node_modules/

task lint:
    npm run lint

task deploy:
    ./scripts/deploy.sh
```

Tasks are your workhorses: running tests, deploying, cleaning up, anything that doesn't produce a specific output file.

### File Recipes: "Build This If Needed"

Use `file` for commands that produce an output file. Jake will skip the recipe if the output is newer than all inputs:

```jake
file dist/bundle.js: src/index.ts src/utils.ts src/app.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js
```

This only runs if:

- `dist/bundle.js` doesn't exist, OR
- Any of the source files are newer than `dist/bundle.js`

This is Make's superpower, now with readable syntax.

### Glob Patterns: Don't List Every File

Instead of listing every source file, use globs:

```jake
file dist/bundle.js: src/**/*.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js
```

The `**` matches any directory depth. If _any_ TypeScript file in `src/` changes, the bundle rebuilds.

Supported patterns:

- `*` - Match any characters except `/`
- `**` - Match any characters including `/` (recursive)
- `?` - Match single character
- `[abc]` - Match character class
- `[a-z]` - Match character range

### Dependencies: Orchestrating Workflows

Dependencies come in two forms:

**Task dependencies** (in brackets) run other recipes first:

```jake
task build: [compile, bundle, minify]
    echo "Build complete!"
```

**File dependencies** (after the colon) are source files:

```jake
file dist/app.css: src/**/*.scss
    sass src/main.scss dist/app.css
```

You can combine both:

```jake
file dist/bundle.min.js: [generate-types] dist/bundle.js
    terser dist/bundle.js -o dist/bundle.min.js
```

This runs `generate-types` first, then checks if `dist/bundle.js` is newer than the output.

### Dependency Chains

File recipes can depend on other file recipes. Jake resolves the chain automatically:

```jake
file dist/compiled.js: src/**/*.ts
    tsc --outFile dist/compiled.js

file dist/bundle.js: dist/compiled.js
    rollup dist/compiled.js -o dist/bundle.js

file dist/bundle.min.js: dist/bundle.js
    terser dist/bundle.js -o dist/bundle.min.js

task build: [dist/bundle.min.js]
    echo "Production build ready!"
```

Running `jake build` triggers the entire chain, but only the steps that need to run.

---

## Real-World Scenarios {#real-world-scenarios}

Let's build complete, copy-paste-ready Jakefiles for common development workflows.

---

### Web Development Workflows {#web-development-workflows}

A modern web project needs: TypeScript compilation, CSS processing, development servers, and production optimization.

```jake
# Web Development Jakefile
# ========================

@dotenv
@export NODE_ENV=development

# Configuration
src_dir = "src"
dist_dir = "dist"
port = "3000"

# === Development ===

@default
task dev:
    @description "Start development server with hot reload"
    @needs node npm
    @pre echo "Starting development server on port {{port}}..."
    npm run dev

task dev-watch:
    @description "Build and watch for changes"
    @watch src/**/*.ts src/**/*.tsx src/**/*.css
    npm run build

# === Build Pipeline ===

@group build
task build: [clean, build-ts, build-css, build-assets]
    @description "Production build"
    echo "Build complete! Output in {{dist_dir}}/"

@group build
file dist/app.js: src/**/*.ts src/**/*.tsx
    @description "Compile TypeScript"
    @needs npx
    @pre echo "Compiling TypeScript..."
    mkdir -p dist
    npx esbuild src/index.tsx \
        --bundle \
        --minify \
        --sourcemap \
        --target=es2020 \
        --outfile=dist/app.js
    @post echo "TypeScript compiled: dist/app.js"

@group build
file dist/app.css: src/**/*.css tailwind.config.js
    @description "Build Tailwind CSS"
    @needs npx
    @pre echo "Processing CSS..."
    mkdir -p dist
    npx tailwindcss -i src/styles/main.css -o dist/app.css --minify
    @post echo "CSS built: dist/app.css"

# Convenience task that depends on the file targets
task build-ts: [dist/app.js]
    @echo "TypeScript build complete"

task build-css: [dist/app.css]
    @echo "CSS build complete"

task build-assets:
    @description "Copy static assets"
    mkdir -p dist/assets
    @if exists(public)
        cp -r public/* dist/
    @end
    @if exists(src/assets)
        cp -r src/assets/* dist/assets/
    @end

# === Cache Busting ===

task build-production: [build]
    @description "Production build with cache busting"
    @export NODE_ENV=production
    @cd dist
        # Add hash to filenames
        for f in *.js *.css; do \
            hash=$(shasum -a 256 "$f" | cut -c1-8); \
            mv "$f" "${f%.*}.$hash.${f##*.}"; \
        done
    echo "Cache-busted assets ready for deployment"

# === Development Utilities ===

@group dev
task lint:
    @description "Run ESLint"
    @needs npx
    npx eslint src/ --ext .ts,.tsx

@group dev
task format:
    @description "Format code with Prettier"
    @needs npx
    npx prettier --write "src/**/*.{ts,tsx,css,json}"

@group dev
task typecheck:
    @description "Type-check without emitting"
    @needs npx
    npx tsc --noEmit

task check: [lint, typecheck]
    @description "Run all code quality checks"
    echo "All checks passed!"

# === Cleanup ===

task clean:
    @description "Remove build artifacts"
    rm -rf dist/
    rm -rf .cache/
    rm -rf node_modules/.cache/
    echo "Cleaned build artifacts"

task clean-all: [clean]
    @description "Remove everything including dependencies"
    rm -rf node_modules/
    echo "Removed node_modules/"

# === Testing ===

@group test
task test:
    @description "Run all tests"
    @needs npm
    npm test

@group test
task test-watch:
    @description "Run tests in watch mode"
    @needs npm
    npm test -- --watch

@group test
task test-coverage:
    @description "Run tests with coverage report"
    @needs npm
    npm test -- --coverage
    @post echo "Coverage report: coverage/lcov-report/index.html"
```

**Usage:**

```bash
jake                    # Start dev server
jake build              # Production build
jake -j4 build          # Parallel build (4 workers)
jake -w build-ts        # Watch and rebuild TypeScript
jake check              # Lint + typecheck
jake test-coverage      # Tests with coverage
```

---

### Open Source Project Maintenance {#open-source-project-maintenance}

Managing releases, changelogs, cross-platform builds, and checksums.

```jake
# Open Source Project Jakefile
# ============================

@dotenv
@require GITHUB_TOKEN

# Project metadata
name = "myproject"
version = "1.0.0"
repo = "username/myproject"

# Cross-compilation targets
targets = "x86_64-linux aarch64-linux x86_64-macos aarch64-macos x86_64-windows"

# === Core Development ===

@default
task all: [build, test]
    echo "Development build complete!"

task build:
    @needs cargo
    @pre echo "Building {{name}} v{{version}}..."
    cargo build --release
    @post echo "Binary: target/release/{{name}}"

task test:
    @needs cargo
    @pre echo "Running tests..."
    cargo test --all
    @post echo "All tests passed!"

task lint:
    @needs cargo
    cargo clippy -- -D warnings
    cargo fmt --check

task format:
    @needs cargo
    cargo fmt

task check: [lint, test]
    echo "All checks passed - ready to commit!"

# === Documentation ===

@group docs
task docs:
    @description "Generate documentation"
    @needs cargo
    cargo doc --no-deps --open

@group docs
task docs-build:
    @description "Build docs for publishing"
    @needs cargo
    cargo doc --no-deps
    echo "Documentation built: target/doc/"

# === Release Pipeline ===

@group release
task release-build:
    @description "Build release binaries for all platforms"
    @needs cargo
    @pre echo "Building for all platforms..."
    mkdir -p dist
    @each {{targets}}
        echo "Building for {{item}}..."
        @if eq({{item}}, x86_64-windows)
            cross build --release --target {{item}}-gnu
            cp target/{{item}}-gnu/release/{{name}}.exe dist/{{name}}-{{item}}.exe
        @else
            cross build --release --target {{item}}
            cp target/{{item}}/release/{{name}} dist/{{name}}-{{item}}
        @end
    @post echo "All platforms built!"

@group release
task checksums: [release-build]
    @description "Generate SHA256 checksums"
    @cd dist
        shasum -a 256 {{name}}-* > checksums.txt
    echo "Checksums: dist/checksums.txt"

@group release
task release-package: [checksums]
    @description "Create release archive"
    @require VERSION
    @confirm Create release package for v$VERSION?
    mkdir -p releases/v$VERSION
    cp dist/* releases/v$VERSION/
    cp CHANGELOG.md releases/v$VERSION/
    cp LICENSE releases/v$VERSION/
    echo "Release packaged: releases/v$VERSION/"

# === Changelog Management ===

@group release
task changelog-check:
    @description "Verify CHANGELOG has unreleased changes"
    @if exists(CHANGELOG.md)
        grep -q "## \[Unreleased\]" CHANGELOG.md && \
        grep -A 100 "## \[Unreleased\]" CHANGELOG.md | grep -q "^### " || \
        (echo "Error: No unreleased changes in CHANGELOG.md" && exit 1)
        echo "Changelog has unreleased changes - good!"
    @else
        echo "Error: CHANGELOG.md not found"
        exit 1
    @end

@group release
task changelog-release:
    @description "Convert Unreleased to version entry"
    @require VERSION
    @needs sed
    @pre echo "Updating CHANGELOG.md for v$VERSION..."
    # Add new Unreleased section and date the current one
    sed -i.bak "s/## \[Unreleased\]/## [Unreleased]\n\n## [$VERSION] - $(date +%Y-%m-%d)/" CHANGELOG.md
    rm CHANGELOG.md.bak
    @post echo "CHANGELOG.md updated"

# === Version Management ===

@group release
task version-bump:
    @description "Bump version in project files"
    @require VERSION
    @confirm Bump version to $VERSION?
    # Update Cargo.toml
    sed -i.bak "s/^version = \".*\"/version = \"$VERSION\"/" Cargo.toml
    rm Cargo.toml.bak
    # Update any other version files
    @if exists(package.json)
        npm version $VERSION --no-git-tag-version
    @end
    echo "Version bumped to $VERSION"

@group release
task release: [check, changelog-check]
    @description "Full release workflow"
    @require VERSION
    @confirm Release v$VERSION to GitHub?

    # Prepare release
    echo "Preparing release v$VERSION..."
    jake version-bump VERSION=$VERSION
    jake changelog-release VERSION=$VERSION
    jake release-package VERSION=$VERSION

    # Git operations
    git add -A
    git commit -m "chore: release v$VERSION"
    git tag -a "v$VERSION" -m "Release v$VERSION"

    # Push
    git push origin main
    git push origin "v$VERSION"

    # Create GitHub release
    gh release create "v$VERSION" \
        --title "v$VERSION" \
        --notes-file <(sed -n "/## \[$VERSION\]/,/## \[/p" CHANGELOG.md | head -n -1) \
        releases/v$VERSION/*

    echo "Released v$VERSION!"

# === CI Helpers ===

task ci: [lint, test, docs-build]
    @description "Run CI checks locally"
    echo "CI simulation passed!"

# === Cleanup ===

task clean:
    cargo clean
    rm -rf dist/
    rm -rf releases/
    echo "Cleaned all build artifacts"
```

**Usage:**

```bash
jake                        # Build and test
jake check                  # Full quality checks
jake release-build          # Cross-compile all platforms
jake checksums              # Generate SHA256 checksums
VERSION=2.0.0 jake release  # Full release workflow
jake ci                     # Simulate CI locally
```

---

### Git Workflow Automation {#git-workflow-automation}

Automate commits, branches, and pre-commit checks.

```jake
# Git Workflow Jakefile
# =====================

@dotenv

# === Pre-commit Checks ===

@default
task pre-commit: [lint, format-check, test-quick]
    @description "Run before every commit"
    echo "Pre-commit checks passed!"

task lint:
    @description "Run all linters"
    @needs npm
    npm run lint

task format-check:
    @description "Check code formatting"
    @needs npm
    npx prettier --check "src/**/*.{ts,tsx,js,json,css}"

task test-quick:
    @description "Run fast unit tests only"
    @needs npm
    npm test -- --testPathPattern="unit" --bail

# === Branch Workflows ===

task branch-check:
    @description "Verify clean working directory"
    @if neq($(git status --porcelain), "")
        echo "Error: Working directory is not clean"
        git status --short
        exit 1
    @end
    echo "Working directory is clean"

task branch-sync:
    @description "Sync with upstream main"
    @pre echo "Syncing with upstream..."
    git fetch origin
    git rebase origin/main
    @post echo "Branch synced with main"

task branch-cleanup:
    @description "Delete merged local branches"
    @confirm Delete merged branches?
    git branch --merged main | grep -v "main" | xargs -r git branch -d
    echo "Cleaned up merged branches"

# === Feature Branch Workflow ===

task feature-start name:
    @description "Start a new feature branch"
    git checkout main
    git pull origin main
    git checkout -b "feature/{{name}}"
    echo "Created feature/{{name}}"

task feature-finish:
    @description "Finish current feature branch"
    @pre echo "Running final checks..."
    jake pre-commit
    @confirm Merge feature branch?

    # Get current branch name
    branch=$(git branch --show-current)

    git checkout main
    git pull origin main
    git merge --no-ff "$branch" -m "Merge $branch"
    git branch -d "$branch"
    echo "Merged and cleaned up $branch"

# === Commit Helpers ===

task commit-fix:
    @description "Create a fix commit"
    @confirm Stage all changes and commit as fix?
    git add -A
    git commit -m "fix: {{$1}}"

task commit-feat:
    @description "Create a feature commit"
    @confirm Stage all changes and commit as feature?
    git add -A
    git commit -m "feat: {{$1}}"

task commit-docs:
    @description "Create a docs commit"
    git add -A
    git commit -m "docs: {{$1}}"

task commit-chore:
    @description "Create a chore commit"
    git add -A
    git commit -m "chore: {{$1}}"

# === Tagging ===

task tag-version:
    @description "Create version tag"
    @require VERSION
    @confirm Create tag v$VERSION?
    git tag -a "v$VERSION" -m "Release v$VERSION"
    echo "Created tag v$VERSION"

task tag-push:
    @description "Push all tags to origin"
    git push origin --tags
    echo "Tags pushed"

# === Git Hooks Setup ===

task hooks-install:
    @description "Install git hooks"
    mkdir -p .git/hooks

    # Pre-commit hook
    echo '#!/bin/sh' > .git/hooks/pre-commit
    echo 'jake pre-commit' >> .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit

    echo "Git hooks installed!"

task hooks-uninstall:
    @description "Remove git hooks"
    rm -f .git/hooks/pre-commit
    rm -f .git/hooks/commit-msg
    echo "Git hooks removed"

# === Utility ===

task status:
    @description "Show detailed git status"
    @quiet
    echo "=== Branch ==="
    git branch --show-current
    echo ""
    echo "=== Status ==="
    git status --short
    echo ""
    echo "=== Recent Commits ==="
    git log --oneline -5

task log:
    @description "Pretty git log"
    git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit -20
```

**Usage:**

```bash
jake pre-commit                     # Run before committing
jake feature-start user-auth        # Start feature branch
jake commit-feat "add user login"   # Conventional commit
jake branch-cleanup                 # Delete merged branches
jake hooks-install                  # Set up git hooks
```

---

### Docker and Container Workflows {#docker-and-container-workflows}

Building, pushing, and managing Docker containers.

```jake
# Docker Workflow Jakefile
# ========================

@dotenv
@require DOCKER_REGISTRY

# Configuration
app_name = "myapp"
registry = "${DOCKER_REGISTRY}"
tag = "latest"

# === Building ===

@default
@group docker
task build:
    @description "Build Docker image"
    @needs docker
    @pre echo "Building {{app_name}}:{{tag}}..."
    docker build -t {{app_name}}:{{tag}} .
    docker tag {{app_name}}:{{tag}} {{registry}}/{{app_name}}:{{tag}}
    @post echo "Built: {{registry}}/{{app_name}}:{{tag}}"

@group docker
task build-no-cache:
    @description "Build without cache"
    @needs docker
    docker build --no-cache -t {{app_name}}:{{tag}} .

@group docker
task build-multi-platform:
    @description "Build for multiple architectures"
    @needs docker
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        -t {{registry}}/{{app_name}}:{{tag}} \
        --push \
        .
    echo "Multi-platform image pushed"

# === Registry Operations ===

@group registry
task login:
    @description "Login to Docker registry"
    @require DOCKER_USERNAME DOCKER_PASSWORD
    echo $DOCKER_PASSWORD | docker login {{registry}} -u $DOCKER_USERNAME --password-stdin
    echo "Logged in to {{registry}}"

@group registry
task push: [build]
    @description "Push image to registry"
    @needs docker
    @confirm Push {{app_name}}:{{tag}} to {{registry}}?
    docker push {{registry}}/{{app_name}}:{{tag}}
    @post echo "Pushed: {{registry}}/{{app_name}}:{{tag}}"

@group registry
task pull:
    @description "Pull latest image"
    @needs docker
    docker pull {{registry}}/{{app_name}}:{{tag}}

# === Local Development ===

@group dev
task up:
    @description "Start services with docker-compose"
    @needs docker-compose
    docker-compose up -d
    @post echo "Services started"

@group dev
task down:
    @description "Stop services"
    @needs docker-compose
    docker-compose down
    @post echo "Services stopped"

@group dev
task restart: [down, up]
    @description "Restart all services"
    echo "Services restarted"

@group dev
task logs:
    @description "Follow container logs"
    @needs docker-compose
    docker-compose logs -f

@group dev
task shell:
    @description "Open shell in app container"
    @needs docker
    docker-compose exec app /bin/sh

@group dev
task ps:
    @description "List running containers"
    docker-compose ps

# === Database Containers ===

@group db
task db-start:
    @description "Start database container only"
    docker-compose up -d db
    @post echo "Database started"

@group db
task db-stop:
    @description "Stop database container"
    docker-compose stop db

@group db
task db-shell:
    @description "Open database CLI"
    docker-compose exec db psql -U postgres

@group db
task db-reset:
    @description "Reset database (DESTRUCTIVE)"
    @confirm This will DELETE all data. Continue?
    docker-compose stop db
    docker-compose rm -f db
    docker volume rm $(docker volume ls -q | grep db-data) 2>/dev/null || true
    docker-compose up -d db
    @post echo "Database reset complete"

# === Cleanup ===

@group cleanup
task clean-containers:
    @description "Remove stopped containers"
    docker container prune -f
    echo "Removed stopped containers"

@group cleanup
task clean-images:
    @description "Remove dangling images"
    docker image prune -f
    echo "Removed dangling images"

@group cleanup
task clean-volumes:
    @description "Remove unused volumes"
    @confirm Remove unused volumes?
    docker volume prune -f
    echo "Removed unused volumes"

@group cleanup
task clean-all: [clean-containers, clean-images]
    @description "Full Docker cleanup"
    @confirm This will remove all unused Docker resources. Continue?
    docker system prune -af
    echo "Full cleanup complete"

# === Production ===

@group prod
task deploy: [build, push]
    @description "Build and deploy to production"
    @confirm Deploy to production?
    @require DEPLOY_HOST
    ssh $DEPLOY_HOST "docker pull {{registry}}/{{app_name}}:{{tag}} && docker-compose up -d"
    @post echo "Deployed to production!"

@group prod
task rollback:
    @description "Rollback to previous version"
    @require DEPLOY_HOST PREVIOUS_TAG
    @confirm Rollback to $PREVIOUS_TAG?
    ssh $DEPLOY_HOST "docker pull {{registry}}/{{app_name}}:$PREVIOUS_TAG && docker-compose up -d"
    echo "Rolled back to $PREVIOUS_TAG"

# === Utility ===

task version:
    @description "Show current image version"
    @quiet
    docker images {{app_name}} --format "{{.Repository}}:{{.Tag}} - {{.Size}} ({{.CreatedSince}})"
```

**Usage:**

```bash
jake build                      # Build Docker image
jake build tag=v1.2.3           # Build with specific tag
jake up                         # Start docker-compose services
jake logs                       # Follow logs
jake push                       # Push to registry
jake deploy                     # Deploy to production
jake clean-all                  # Full Docker cleanup
```

---

### CI/CD Integration {#cicd-integration}

Jake works seamlessly with GitHub Actions and other CI systems.

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
    @require STAGING_URL
    @needs npx
    npx vercel deploy --prebuilt --token=$VERCEL_TOKEN
    echo "Deployed to staging: $STAGING_URL"

task deploy-production:
    @description "Deploy to production"
    @require PRODUCTION_URL
    @confirm Deploy to production?
    @needs npx
    npx vercel deploy --prebuilt --prod --token=$VERCEL_TOKEN
    @post echo "Deployed to production: $PRODUCTION_URL"

task deploy-preview:
    @description "Deploy preview environment"
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

# === Rollback ===

task rollback:
    @description "Rollback production deployment"
    @require PREVIOUS_DEPLOY_ID
    @confirm Rollback production to $PREVIOUS_DEPLOY_ID?
    npx vercel rollback $PREVIOUS_DEPLOY_ID --token=$VERCEL_TOKEN
    echo "Rolled back to $PREVIOUS_DEPLOY_ID"

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

**GitHub Actions workflow (`.github/workflows/ci.yml`):**

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
          curl -L https://github.com/HelgeSverre/jake/releases/latest/download/jake-x86_64-linux -o jake
          chmod +x jake
          sudo mv jake /usr/local/bin/

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
```

---

### Database and Backend Tasks {#database-and-backend-tasks}

Migrations, seeding, backups, and API testing.

```jake
# Database & Backend Jakefile
# ===========================

@dotenv
@require DATABASE_URL

# === Migrations ===

@group db
task migrate:
    @description "Run pending migrations"
    @needs npx
    @pre echo "Running migrations..."
    npx prisma migrate deploy
    @post echo "Migrations complete"

@group db
task migrate-create name:
    @description "Create a new migration"
    @needs npx
    npx prisma migrate dev --name {{name}}
    echo "Created migration: {{name}}"

@group db
task migrate-reset:
    @description "Reset database and run all migrations"
    @confirm This will DELETE all data. Continue?
    @needs npx
    npx prisma migrate reset --force
    @post echo "Database reset complete"

@group db
task migrate-status:
    @description "Show migration status"
    @needs npx
    npx prisma migrate status

# === Seeding ===

@group db
task seed:
    @description "Seed database with sample data"
    @needs npx
    @pre echo "Seeding database..."
    npx prisma db seed
    @post echo "Database seeded"

@group db
task seed-prod:
    @description "Seed production essentials only"
    @confirm Seed production database?
    @needs npx
    NODE_ENV=production npx prisma db seed -- --production
    echo "Production seed complete"

# === Backups ===

@group backup
task backup:
    @description "Create database backup"
    @needs pg_dump
    backup_file="backups/db-$(date +%Y%m%d-%H%M%S).sql"
    mkdir -p backups
    pg_dump $DATABASE_URL > $backup_file
    gzip $backup_file
    @post echo "Backup created: ${backup_file}.gz"

@group backup
task backup-list:
    @description "List available backups"
    @quiet
    ls -lah backups/*.sql.gz 2>/dev/null || echo "No backups found"

@group backup
task restore file:
    @description "Restore from backup file"
    @confirm Restore from {{file}}? This will overwrite current data.
    @needs psql gunzip
    gunzip -c {{file}} | psql $DATABASE_URL
    @post echo "Database restored from {{file}}"

@group backup
task backup-s3:
    @description "Backup to S3"
    @require AWS_BUCKET
    @needs aws pg_dump
    backup_file="db-$(date +%Y%m%d-%H%M%S).sql.gz"
    pg_dump $DATABASE_URL | gzip | aws s3 cp - s3://$AWS_BUCKET/backups/$backup_file
    @post echo "Backup uploaded to s3://$AWS_BUCKET/backups/$backup_file"

# === Schema ===

@group schema
task schema-push:
    @description "Push schema changes (dev only)"
    @needs npx
    npx prisma db push
    echo "Schema pushed"

@group schema
task schema-pull:
    @description "Pull schema from database"
    @needs npx
    npx prisma db pull
    echo "Schema pulled"

@group schema
task schema-generate:
    @description "Generate Prisma client"
    @needs npx
    npx prisma generate
    echo "Client generated"

@group schema
task schema-studio:
    @description "Open Prisma Studio"
    @needs npx
    npx prisma studio

# === API Testing ===

@group api
task api-test:
    @description "Run API tests"
    @needs npm
    npm run test:api

@group api
task api-health:
    @description "Check API health"
    @require API_URL
    @pre echo "Checking $API_URL..."
    curl -sf "$API_URL/health" | jq .
    @post echo "API is healthy"

@group api
task api-docs:
    @description "Generate API documentation"
    @needs npx
    npx swagger-jsdoc -d swaggerDef.js -o docs/api.json src/**/*.ts
    echo "API docs generated: docs/api.json"

# === Performance ===

@group perf
task analyze-queries:
    @description "Analyze slow queries"
    @needs psql
    psql $DATABASE_URL -c "SELECT query, calls, mean_time, total_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

@group perf
task vacuum:
    @description "Run VACUUM ANALYZE"
    @needs psql
    @pre echo "Running VACUUM ANALYZE..."
    psql $DATABASE_URL -c "VACUUM ANALYZE;"
    @post echo "Vacuum complete"

# === Setup ===

task setup: [schema-generate, migrate, seed]
    @description "Full database setup"
    echo "Database setup complete!"

task reset: [migrate-reset, seed]
    @description "Reset and reseed database"
    echo "Database reset complete!"
```

**Usage:**

```bash
jake setup                          # Full database setup
jake migrate                        # Run migrations
jake migrate-create add-users       # Create new migration
jake seed                           # Seed data
jake backup                         # Create backup
jake restore file=backups/db.sql.gz # Restore backup
jake api-health                     # Check API
```

---

### Monorepo Management {#monorepo-management}

Organizing a monorepo with imports and namespacing.

**Project structure:**

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

**Root `Jakefile`:**

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
    # Run in parallel using background processes
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
    # Check which packages have changes
    @if exists(packages/web)
        git diff --name-only HEAD~1 | grep -q "^packages/web" && jake web.test
    @end
    @if exists(packages/api)
        git diff --name-only HEAD~1 | grep -q "^packages/api" && jake api.test
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
    @confirm Deploy ALL packages to production?
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
    echo "All dependencies installed!"

task deps-update:
    @description "Update dependencies in all packages"
    @needs npx
    npx ncu -u
    @each packages/web packages/api packages/mobile packages/shared
        @cd {{item}}
            npx ncu -u
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

**`jake/web.jake`:**

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
    @confirm Deploy web to production?
    @cd {{root}}
        npm run deploy:production
    echo "Web deployed to production"
```

**`jake/api.jake`:**

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
    @confirm Deploy API to production?
    @cd {{root}}
        npm run deploy:production
    echo "API deployed to production"
```

**Usage:**

```bash
jake                        # Build all packages
jake -j4 all                # Build all in parallel
jake dev                    # Start all dev servers
jake web.build              # Build just web
jake api.test               # Test just API
jake test-affected          # Test only changed packages
jake deploy-production      # Deploy everything
```

---

## Advanced Patterns {#advanced-patterns}

### Pattern 1: Conditional Platform Handling

```jake
@only-os linux macos
task install-unix:
    ./install.sh

@only-os windows
task install-windows:
    install.bat

# Cross-platform task that delegates
task install:
    @if exists(/bin/bash)
        jake install-unix
    @else
        jake install-windows
    @end
```

### Pattern 2: Tool Availability Checks

Use `command()` to check if tools are installed before using them:

```jake
task containerize:
    @description "Build container image"
    @if command(docker)
        docker build -t myapp .
    @elif command(podman)
        podman build -t myapp .
    @else
        echo "Error: No container runtime found (docker or podman required)"
        exit 1
    @end

task deploy:
    @description "Deploy to Kubernetes"
    @if command(kubectl)
        kubectl apply -f k8s/
    @else
        echo "kubectl not found - install it first"
        exit 1
    @end

task format:
    @description "Format code with available formatter"
    @if command(prettier)
        prettier --write "src/**/*.{js,ts,json}"
    @elif command(deno)
        deno fmt src/
    @end
```

### Pattern 3: Cache-Based Optimization

Skip expensive operations when inputs haven't changed:

```jake
task typecheck:
    @description "Type-check with caching"
    @cache src/**/*.ts tsconfig.json
    npx tsc --noEmit
    echo "Type-check complete (or skipped - no changes)"

task lint:
    @description "Lint with caching"
    @cache src/**/*.ts .eslintrc.js
    npx eslint src/
```

### Pattern 4: Iterating Over Files

Process multiple items with `@each`:

```jake
services = "web api worker scheduler"

task build-all:
    @each {{services}}
        echo "Building {{item}}..."
        @cd services/{{item}}
            npm run build
    echo "All services built!"

task test-all:
    @each {{services}}
        @cd services/{{item}}
            npm test

# Iterate over files with globs
task check-configs:
    @each config/*.json
        echo "Validating {{item}}..."
        node scripts/validate-config.js {{item}}
```

### Pattern 5: Error Recovery with Hooks

```jake
@on_error echo "Build failed! Check logs above."
@on_error ./scripts/notify-failure.sh

task deploy: [build, test]
    @pre echo "Creating backup..."
    @pre ./scripts/backup.sh

    ./scripts/deploy.sh

    @post echo "Running health check..."
    @post ./scripts/health-check.sh || jake rollback

task rollback:
    @description "Emergency rollback"
    ./scripts/rollback.sh
```

### Pattern 6: Environment-Aware Builds

```jake
@dotenv
@dotenv ".env.local"

task build:
    @if env(PRODUCTION)
        @export NODE_ENV=production
        npm run build -- --minify
    @elif env(STAGING)
        @export NODE_ENV=staging
        npm run build
    @else
        @export NODE_ENV=development
        npm run build -- --sourcemap
    @end

task deploy:
    @require DEPLOY_ENV
    @confirm Deploy to $DEPLOY_ENV?

    @if eq($DEPLOY_ENV, production)
        @require PRODUCTION_KEY
        @pre echo "Production deployment starting..."
        ./deploy.sh production
    @elif eq($DEPLOY_ENV, staging)
        ./deploy.sh staging
    @else
        echo "Unknown environment: $DEPLOY_ENV"
        exit 1
    @end
```

### Pattern 7: Private Helper Tasks

Use underscore prefix to hide implementation details:

```jake
# Public interface
task build: [_setup, _compile, _bundle]
    echo "Build complete!"

# Hidden implementation tasks
task _setup:
    mkdir -p dist
    mkdir -p .cache

task _compile:
    tsc

task _bundle:
    esbuild dist/index.js --bundle --outfile=dist/bundle.js
```

### Pattern 8: Aliases for Convenience

```jake
# Full name with short aliases
task build | b:
    cargo build

task test | t:
    cargo test

task release | r | rel:
    cargo build --release

# Now all of these work:
# jake build, jake b
# jake test, jake t
# jake release, jake r, jake rel
```

---

## Migrating from Make or Just {#migrating-from-make-or-just}

### From Make

| Make             | Jake                       |
| ---------------- | -------------------------- |
| `target: deps`   | `task target: [deps]`      |
| `$(VAR)`         | `{{VAR}}`                  |
| `.PHONY: target` | `task target:` (automatic) |
| Tab required     | 4 spaces or tab            |
| `$@` (target)    | Use explicit name          |
| `$<` (first dep) | Use explicit name          |
| `%.o: %.c`       | Write explicit rules       |

**Before (Makefile):**

```make
CC = gcc
CFLAGS = -Wall -O2

.PHONY: all clean test

all: build test

build: main.o utils.o
	$(CC) -o app main.o utils.o

%.o: %.c
	$(CC) $(CFLAGS) -c $<

test: build
	./test_runner

clean:
	rm -f *.o app
```

**After (Jakefile):**

```jake
cc = "gcc"
cflags = "-Wall -O2"

@default
task all: [build, test]
    echo "Done"

file app: main.o utils.o
    {{cc}} -o app main.o utils.o

file main.o: main.c
    {{cc}} {{cflags}} -c main.c -o main.o

file utils.o: utils.c
    {{cc}} {{cflags}} -c utils.c -o utils.o

task test: [build]
    ./test_runner

task clean:
    rm -f *.o app
```

### From Just

| Just              | Jake               |
| ----------------- | ------------------ |
| `recipe:`         | `task recipe:`     |
| `{{var}}`         | `{{var}}` (same!)  |
| `set dotenv-load` | `@dotenv`          |
| `@recipe` (quiet) | `@quiet` decorator |
| `[group: 'x']`    | `@group x`         |
| `[confirm]`       | `@confirm`         |

**Before (justfile):**

```just
set dotenv-load

default:
    @just --list

build:
    cargo build

test: build
    cargo test

[confirm("Deploy to production?")]
deploy: test
    ./deploy.sh
```

**After (Jakefile):**

```jake
@dotenv

@default
task list:
    jake --list

task build:
    cargo build

task test: [build]
    cargo test

task deploy: [test]
    @confirm Deploy to production?
    ./deploy.sh
```

### What Jake Adds

Features you get by migrating:

1. **File targets**: `file dist/bundle.js: src/**/*.ts` - skip rebuilds when nothing changed
2. **Glob patterns**: `src/**/*.ts` instead of listing every file
3. **Parallel execution**: `jake -j4 all` to build faster
4. **Pre/post hooks**: Setup and cleanup that always runs
5. **Watch mode**: `jake -w build` for development
6. **Better imports**: Namespace with `@import "x.jake" as x`

---

## Tips and Best Practices {#tips-and-best-practices}

### 1. Use File Targets for Build Artifacts

```jake
# Good: Only rebuilds when sources change
file dist/bundle.js: src/**/*.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js

# Avoid: Rebuilds every time
task build:
    esbuild src/index.ts --bundle --outfile=dist/bundle.js
```

### 2. Always Set a Default Task

```jake
@default
task dev:
    npm run dev
```

Users can just type `jake` instead of remembering the task name.

### 3. Use Descriptive Task Names

```jake
# Good
task build-frontend:
    npm run build

# Avoid
task bf:
    npm run build
```

But offer aliases for power users:

```jake
task build-frontend | bf:
    npm run build
```

### 4. Group Related Tasks

Use imports for organization:

```
project/
├── Jakefile
└── jake/
    ├── build.jake
    ├── test.jake
    ├── deploy.jake
    └── docker.jake
```

```jake
@import "jake/build.jake" as build
@import "jake/test.jake" as test
@import "jake/deploy.jake" as deploy
@import "jake/docker.jake" as docker
```

### 5. Document Complex Tasks

```jake
# Deploy to production
# Requires: AWS credentials configured, SSH key for bastion
# Usage: VERSION=1.2.3 jake deploy
task deploy:
    @description "Deploy application to production cluster"
    @require VERSION AWS_ACCESS_KEY_ID
    @confirm Deploy v$VERSION to production?
    # ... deployment logic
```

### 6. Use @needs for Dependencies

```jake
task build:
    @needs node npm esbuild
    npm run build
```

This fails fast with a helpful message if tools are missing.

### 7. Use @require for Environment Variables

```jake
@require DATABASE_URL API_KEY
```

Catches missing configuration before commands fail mysteriously.

### 8. Leverage Parallel Execution

```jake
# Independent tasks can run in parallel
task all: [frontend, backend, docs, tests]
    echo "Done!"
```

Run with `jake -j4 all` for 4 parallel workers.

### 9. Use Watch Mode for Development

```jake
task dev:
    @watch src/**/*.ts tests/**/*.ts
    npm run build
```

```bash
jake -w dev  # Rebuilds on any TypeScript change
```

### 10. Handle Errors Gracefully

```jake
@on_error ./scripts/notify-slack.sh "Build failed"

task deploy:
    @pre ./scripts/backup.sh
    ./scripts/deploy.sh
    @post ./scripts/health-check.sh
```

---

## Quick Reference Card {#quick-reference-card}

### Jakefile Syntax

```jake
# Variables
name = "value"
version = "1.0.0"

# Global directives
@dotenv                          # Load .env file
@dotenv ".env.local"             # Load specific file
@export VAR=value                # Export environment variable
@require VAR1 VAR2               # Require env vars
@import "file.jake"              # Import recipes
@import "file.jake" as name      # Import with namespace
@pre command                     # Global pre-hook
@post command                    # Global post-hook
@on_error command                # Error handler

# Task recipe (always runs)
task name: [deps]
    commands

# Task with parameters
task greet name="World":
    echo "Hello, {{name}}!"

# File recipe (runs if output missing or inputs changed)
file output: input1 input2
    commands

# File with glob patterns
file dist/bundle.js: src/**/*.ts
    commands

# Recipe metadata
@default                         # Set as default task
@group groupname                 # Group in listings
@quiet                           # Suppress command echo
@only-os linux macos             # Platform-specific
task name | alias1 | alias2:     # Aliases
task _private:                   # Hidden from --list
    @description "Description"   # Task description
```

### Command Directives

```jake
task example:
    @needs cmd1 cmd2             # Verify commands exist
    @require VAR1 VAR2           # Verify env vars set
    @confirm "Proceed?"          # Ask for confirmation
    @ignore                      # Continue on failure
    @cache file1 file2           # Skip if unchanged
    @watch pattern               # Watch files in -w mode
    @cd directory                # Change directory
    @shell zsh                   # Use different shell
    @pre command                 # Run before task
    @post command                # Run after task (even on failure)

    # Loops
    @each item1 item2 item3
        echo "Processing {{item}}"
    @end

    @each src/**/*.ts
        echo "File: {{item}}"
    @end

    # Conditionals
    @if env(CI)
        echo "In CI"
    @elif exists(file)
        echo "File exists"
    @else
        echo "Default"
    @end
```

### Built-in Functions

```jake
{{uppercase(var)}}               # HELLO
{{lowercase(var)}}               # hello
{{trim(var)}}                    # Remove whitespace
{{dirname(path)}}                # /a/b from /a/b/c.txt
{{basename(path)}}               # c.txt from /a/b/c.txt
{{extension(path)}}              # .txt from file.txt
{{without_extension(path)}}      # file from file.txt
{{absolute_path(path)}}          # Full path
```

### Condition Functions

```jake
env(VAR)                         # True if VAR is set
exists(path)                     # True if path exists
command(name)                    # True if command exists in PATH
eq(a, b)                         # True if a equals b
neq(a, b)                        # True if a not equals b
```

### CLI Options

```bash
jake                             # Run default task
jake task                        # Run specific task
jake task name=value             # With parameter
jake task arg1 arg2              # Positional arguments ({{$1}}, {{$2}})

jake -l, --list                  # List available tasks
jake -n, --dry-run               # Show commands without running
jake -v, --verbose               # Verbose output
jake -y, --yes                   # Auto-confirm prompts
jake -f, --jakefile FILE         # Use specific Jakefile
jake -j, --jobs N                # Parallel execution (N workers)
jake -j                          # Parallel (CPU count)
jake -w, --watch                 # Watch mode
jake -w "pattern" task           # Watch specific files
```

### Common Patterns

```jake
# Rebuild from scratch
task rebuild: [clean, build]
    echo "Rebuild complete"

# CI pipeline
task ci: [lint, test, build]
    echo "CI passed"

# Parallel builds
jake -j4 frontend backend docs

# Watch and rebuild
jake -w build

# Environment-specific
@if env(PRODUCTION)
    npm run build:prod
@else
    npm run build:dev
@end

# Platform-specific
@only-os macos
task macos-setup:
    brew install dependencies

@only-os linux
task linux-setup:
    apt-get install dependencies
```

---

## Conclusion

Jake takes the best ideas from Make and Just, combines them, and adds features neither has. You get:

- **Make's file tracking** without the cryptic syntax
- **Just's readability** without sacrificing dependency graphs
- **Parallel execution** that respects dependencies
- **Glob patterns** so you never list files manually
- **Hooks** for setup, cleanup, and error handling
- **Watch mode** for development workflows
- **Imports** for organizing large projects

The result is a build tool that's actually pleasant to use. Your Jakefiles are readable, your builds are fast, and your automation just works.

Start with a simple `Jakefile`, grow it as your project grows, and never fight your build system again.

---

_Happy automating!_

---

**Resources:**

- [Jake on GitHub](https://github.com/HelgeSverre/jake)
- [Full User Guide](https://github.com/HelgeSverre/jake/blob/main/GUIDE.md)
- [E2E Test Jakefiles](https://github.com/HelgeSverre/jake/tree/main/tests/e2e)

---

_Jake v0.3.0 - MIT License_
