---
title: Open Source Release
description: Complete release workflow with cross-platform builds, changelogs, and GitHub releases.
---

A comprehensive workflow for managing releases, changelogs, cross-platform builds, and checksums.

## Complete Jakefile

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
    @needs cross
    @pre echo "Building for all platforms..."
    mkdir -p dist
    @each {{targets}}
        echo "Building for {{item}}..."
        @if contains("{{item}}", "windows")
            cross build --release --target {{item}}-gnu
            cp target/{{item}}-gnu/release/{{name}}.exe dist/{{name}}-{{item}}.exe
        @else
            cross build --release --target {{item}}
            cp target/{{item}}/release/{{name}} dist/{{name}}-{{item}}
        @end
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
    @confirm "Create release package for v$VERSION?"
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
    sed -i.bak "s/## \[Unreleased\]/## [Unreleased]\n\n## [$VERSION] - $(date +%Y-%m-%d)/" CHANGELOG.md
    rm CHANGELOG.md.bak
    @post echo "CHANGELOG.md updated"

# === Version Management ===

@group release
task version-bump:
    @description "Bump version in project files"
    @require VERSION
    @confirm "Bump version to $VERSION?"
    sed -i.bak "s/^version = \".*\"/version = \"$VERSION\"/" Cargo.toml
    rm Cargo.toml.bak
    @if exists(package.json)
        npm version $VERSION --no-git-tag-version
    @end
    echo "Version bumped to $VERSION"

@group release
task release: [check, changelog-check]
    @description "Full release workflow"
    @require VERSION
    @confirm "Release v$VERSION to GitHub?"

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
        --notes-file CHANGELOG.md \
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

## Usage

```bash
jake                        # Build and test
jake check                  # Full quality checks
jake release-build          # Cross-compile all platforms
jake checksums              # Generate SHA256 checksums
VERSION=2.0.0 jake release  # Full release workflow
jake ci                     # Simulate CI locally
```

## Key Features

### Cross-Platform Builds

Uses `@each` to iterate over targets:

```jake
@each {{targets}}
    cross build --release --target {{item}}
@end
```

### Changelog Automation

Validates and updates CHANGELOG.md following Keep a Changelog format:

```jake
task changelog-check:
    grep -q "## \[Unreleased\]" CHANGELOG.md
```

### Complete Release Flow

The `release` task orchestrates the entire process:
1. Run quality checks
2. Validate changelog
3. Bump version numbers
4. Update changelog
5. Create Git tag
6. Push to GitHub
7. Create GitHub release with assets

## Customization

Update the metadata at the top:

```jake
name = "myproject"
version = "1.0.0"
repo = "username/myproject"
targets = "x86_64-linux aarch64-linux x86_64-macos aarch64-macos"
```

## See Also

- [Environment Validation](/examples/environment-validation/) - `@require` and `@needs`
- [Parallel Execution](/examples/parallel-execution/) - Speed up cross-platform builds
