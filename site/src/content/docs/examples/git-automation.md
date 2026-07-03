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
@desc "Run before every commit"
task pre-commit: [lint, format-check, test-quick]
    echo "Pre-commit checks passed!"

@desc "Run all linters"
task lint:
    @needs npm
    npm run lint

@desc "Check code formatting"
task format-check:
    @needs npm
    npx prettier --check "src/**/*.{ts,tsx,js,json,css}"

@desc "Run fast unit tests only"
task test-quick:
    @needs npm
    npm test -- --testPathPattern="unit" --bail

# === Branch Workflows ===

@desc "Verify clean working directory"
task branch-check:
    # Jake's @if conditions don't evaluate $(...) shell substitutions —
    # do the cleanliness check at shell level and exit non-zero on failure.
    git diff-index --quiet HEAD -- || (echo "Error: working directory is not clean" >&2; git status --short; exit 1)
    echo "Working directory is clean"

@desc "Sync with upstream main"
task branch-sync:
    @pre echo "Syncing with upstream..."
    git fetch origin
    git rebase origin/main
    @post echo "Branch synced with main"

@desc "Delete merged local branches"
task branch-cleanup:
    @confirm "Delete merged branches?"
    git branch --merged main | grep -v "main" | xargs -r git branch -d
    echo "Cleaned up merged branches"

# === Feature Branch Workflow ===

@desc "Start a new feature branch"
task feature-start name:
    git checkout main
    git pull origin main
    git checkout -b "feature/{{name}}"
    echo "Created feature/{{name}}"

@desc "Finish current feature branch"
task feature-finish:
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

@desc "Create a fix commit"
task commit-fix:
    @confirm "Stage all changes and commit as fix?"
    git add -A
    git commit -m "fix: {{$1}}"

@desc "Create a feature commit"
task commit-feat:
    @confirm "Stage all changes and commit as feature?"
    git add -A
    git commit -m "feat: {{$1}}"

@desc "Create a docs commit"
task commit-docs:
    git add -A
    git commit -m "docs: {{$1}}"

@desc "Create a chore commit"
task commit-chore:
    git add -A
    git commit -m "chore: {{$1}}"

# === Tagging ===

@desc "Create version tag"
task tag-version:
    @require VERSION
    @confirm "Create tag v$VERSION?"
    git tag -a "v$VERSION" -m "Release v$VERSION"
    echo "Created tag v$VERSION"

@desc "Push all tags to origin"
task tag-push:
    git push origin --tags
    echo "Tags pushed"

# === Git Hooks Setup ===

@desc "Install git hooks"
task hooks-install:
    mkdir -p .git/hooks

    echo '#!/bin/sh' > .git/hooks/pre-commit
    echo 'jake pre-commit' >> .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit

    echo "Git hooks installed!"

@desc "Remove git hooks"
task hooks-uninstall:
    rm -f .git/hooks/pre-commit
    rm -f .git/hooks/commit-msg
    echo "Git hooks removed"

# === Utility ===

@desc "Show detailed git status"
task status:
    @quiet
    echo "=== Branch ==="
    git branch --show-current
    echo ""
    echo "=== Status ==="
    git status --short
    echo ""
    echo "=== Recent Commits ==="
    git log --oneline -5

@desc "Pretty git log"
task log:
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
    # @if conditions don't evaluate $(...); do the check in the shell.
    git diff-index --quiet HEAD -- || (echo "Working directory not clean" >&2; exit 1)
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
