---
description: "Perform a new release with version bump, changelog update, git tag, and push"
argument-hint: "[patch|minor|major]"
---

# Release Command

Perform a complete release for Jake. Default bump type is `minor`.

**Argument:** `$ARGUMENTS` (optional: `patch`, `minor`, or `major` - defaults to `minor`)

## Release Workflow

Execute these steps in order:

### 1. Verify Code Quality

Run tests and build to ensure code is not broken:

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

**STOP if either command fails.** Report the error and do not proceed with the release.

### 2. Check for Uncommitted Changes

Run `git status` to check for uncommitted changes.

If there are unstaged or uncommitted changes:

- Review what changed
- Commit them using conventional commit format (e.g., `feat:`, `fix:`, `refactor:`, `test:`, `docs:`)
- Keep commits atomic when feasible

### 3. Determine Version Bump

1. Get the current version from the latest git tag: `git describe --tags --abbrev=0`
2. Parse the bump type from `$ARGUMENTS` (default: `minor`)
3. Calculate the new version (strip the `v` prefix for calculation, add it back for tag):
   - `patch`: v0.6.0 -> v0.7.0 is wrong; v0.6.0 -> v0.6.1
   - `minor`: v0.6.0 -> v0.7.0
   - `major`: v0.6.0 -> v1.0.0

### 4. Update CHANGELOG.md

1. Read `CHANGELOG.md` and check if it already has an entry for the new version
2. If missing, generate changelog entry from git commits since the last tag:
   - Use `git log --oneline $(git describe --tags --abbrev=0)..HEAD` to see commits
   - Group by type: Added (feat), Changed (refactor, other), Fixed (fix)
3. Add new version section under `## [Unreleased]`, following Keep a Changelog format:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added

- New features from feat() commits

### Changed

- Changes from refactor() and other commits

### Fixed

- Bug fixes from fix() commits
```

**Guidelines:**

- Summarize related commits into feature descriptions
- Use bullet points with bold feature names for major additions
- Keep descriptions concise but informative
- Don't include trivial commits (typos, formatting, WIP)

### 5. Create Changelog Commit

Commit the changelog update:

```bash
git add CHANGELOG.md
git commit -m "docs: update changelog for vX.Y.Z"
```

### 6. Create Annotated Tag

Create an annotated tag with the version:

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
```

### 7. Push to Remote

Push both the commit and the tag:

```bash
git push origin main
git push origin vX.Y.Z
```

### 8. GitHub Actions Handles the Rest

The `.github/workflows/release.yml` workflow will automatically:

- Build binaries for all 5 platforms (Linux/macOS/Windows x x86_64/aarch64)
- Generate SHA256 checksums
- Create the GitHub release with all assets
- Mark as prerelease if tag contains hyphen (e.g., v0.7.0-rc1)

## Completion

Report the release summary:

- Previous version -> New version
- Key changes included
- Note that GitHub Actions will create the release automatically
- Provide link: https://github.com/HelgeSverre/jake/actions (to monitor the workflow)
