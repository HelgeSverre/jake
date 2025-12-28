# jake - a justfile runner written in Zig

# Default: show available recipes
default:
    @just --list

# ─────────────────────────────────────────────────────────────────────────────
# Building
# ─────────────────────────────────────────────────────────────────────────────

# Build the project (debug mode)
[group('build')]
build:
    zig build

# Build with ReleaseFast optimizations
[group('build')]
release:
    zig build -Doptimize=ReleaseFast

# Build smallest binary
[group('build')]
release-small:
    zig build -Doptimize=ReleaseSmall

# Build with safety checks enabled
[group('build')]
release-safe:
    zig build -Doptimize=ReleaseSafe

# ─────────────────────────────────────────────────────────────────────────────
# Running
# ─────────────────────────────────────────────────────────────────────────────

# Build and run the application
[group('run')]
run *ARGS:
    zig build run {{ if ARGS != "" { "-- " + ARGS } else { "" } }}

# ─────────────────────────────────────────────────────────────────────────────
# Testing
# ─────────────────────────────────────────────────────────────────────────────

# Run all tests
[group('test')]
test:
    zig build test

# Run tests with verbose output
[group('test')]
test-verbose:
    zig build test --summary all

# ─────────────────────────────────────────────────────────────────────────────
# Code Quality
# ─────────────────────────────────────────────────────────────────────────────

# Format all Zig source files
[group('quality')]
fmt:
    zig fmt src/

# Check formatting without modifying files
[group('quality')]
fmt-check:
    zig fmt --check src/

# ─────────────────────────────────────────────────────────────────────────────
# Development
# ─────────────────────────────────────────────────────────────────────────────

# Watch and rebuild on changes (requires entr)
[group('dev')]
watch:
    find src -name '*.zig' | entr -c just build

# Watch and run tests on changes (requires entr)
[group('dev')]
watch-test:
    find src -name '*.zig' | entr -c just test

# ─────────────────────────────────────────────────────────────────────────────
# Maintenance
# ─────────────────────────────────────────────────────────────────────────────

# Remove build artifacts and generated docs
[group('maintenance')]
clean:
    rm -rf .zig-cache zig-out docs

# Fetch dependencies
[group('maintenance')]
fetch:
    zig build --fetch

# Install to ~/.local/bin
[group('maintenance')]
install:
    zig build --prefix ~/.local

# Generate documentation
[group('maintenance')]
docs:
    zig build-lib src/root.zig -femit-docs -fno-emit-bin

# ─────────────────────────────────────────────────────────────────────────────
# CI (requires: brew install act)
# ─────────────────────────────────────────────────────────────────────────────

# Run CI workflow locally via act (requires: brew install act)
# Note: May fail if Zig download mirrors are unavailable
[group('ci')]
ci:
    act push -W .github/workflows/ci.yml -P ubuntu-latest=catthehacker/ubuntu:act-latest --container-architecture linux/amd64

# ─────────────────────────────────────────────────────────────────────────────
# E2E Tests
# ─────────────────────────────────────────────────────────────────────────────

# Run E2E test suite using jake
[group('test')]
e2e: release
    cd samples && ../zig-out/bin/jake test-all

# ─────────────────────────────────────────────────────────────────────────────
# Info
# ─────────────────────────────────────────────────────────────────────────────

# Show project info
[group('info')]
info:
    @echo "Project: jake"
    @echo "Zig version: $(zig version)"
    @echo "Source files:"
    @find src -name '*.zig' | xargs wc -l | tail -1

# Show zig build options
[group('info')]
zig-help:
    zig build --help
