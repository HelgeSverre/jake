---
title: Git Automation
description: Automate commits, branches, and pre-commit checks with Jake.
---

Streamline your Git workflow with automated commits, branch management, and pre-commit hooks.

## Complete Jakefile

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
    @confirm "Delete merged branches?"
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
    @confirm "Merge feature branch?"

    branch=$(git branch --show-current)
    git checkout main
    git pull origin main
    git merge --no-ff "$branch" -m "Merge $branch"
    git branch -d "$branch"
    echo "Merged and cleaned up $branch"

# === Commit Helpers ===

task commit-fix:
    @description "Create a fix commit"
    @confirm "Stage all changes and commit as fix?"
    git add -A
    git commit -m "fix: {{$1}}"

task commit-feat:
    @description "Create a feature commit"
    @confirm "Stage all changes and commit as feature?"
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
    @confirm "Create tag v$VERSION?"
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

## Usage

```bash
jake pre-commit                     # Run before committing
jake feature-start user-auth        # Start feature branch
jake commit-feat "add user login"   # Conventional commit
jake branch-cleanup                 # Delete merged branches
jake hooks-install                  # Set up git hooks
```

## Key Features

### Conventional Commits

Consistent commit messages with helpers:

```jake
task commit-feat:
    git add -A
    git commit -m "feat: {{$1}}"
```

```bash
jake commit-feat "add user authentication"
# Creates: feat: add user authentication
```

### Pre-commit Hooks

Install Jake as your pre-commit hook:

```jake
task hooks-install:
    echo 'jake pre-commit' >> .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
```

### Feature Branch Workflow

Streamlined GitFlow-style workflow:

```bash
jake feature-start login-page  # Create feature/login-page
# ... work on feature ...
jake pre-commit                # Validate changes
jake feature-finish            # Merge back to main
```

### Branch Safety

Check for clean working directory before operations:

```jake
task branch-check:
    @if neq($(git status --porcelain), "")
        echo "Error: Working directory is not clean"
        exit 1
    @end
```

## Customization

### Different Test Runners

Adjust for your stack:

```jake
task test-quick:
    @needs pytest
    pytest tests/unit -x --tb=short
```

### Additional Commit Types

Add more conventional commit types:

```jake
task commit-refactor:
    git add -A
    git commit -m "refactor: {{$1}}"

task commit-perf:
    git add -A
    git commit -m "perf: {{$1}}"

task commit-test:
    git add -A
    git commit -m "test: {{$1}}"
```

## See Also

- [Positional Arguments](/docs/positional-arguments/) - Using `{{$1}}`
- [Conditionals](/docs/conditionals/) - `@if` and `neq()`
