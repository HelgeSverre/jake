# Jakefile for building jake itself
# A comprehensive example showcasing jake's features

# Core modules
@import "jake/build.jake"
@import "jake/dev.jake" as dev
@import "jake/test.jake" as test

# Release & packaging
@import "jake/release.jake" as release
@import "jake/packaging.jake" as packaging

# Performance & benchmarking
@import "jake/perf.jake" as perf
@import "jake/bench.jake" as bench

# Utilities
@import "jake/stats.jake" as stats
@import "jake/git.jake" as git
@import "jake/debug.jake" as debug
@import "jake/maintenance.jake" as maintenance

# Other
@import "jake/web.jake" as web
@import "jake/editors.jake" as editors
@import "jake/ai.jake" as ai

@dotenv

# Targeted hooks for release tasks
@before release.all echo "Starting cross-platform build..."
@after release.all echo "All platforms built successfully!"
@before release.package echo "Preparing release package..."

# Build hooks
@before build echo "Starting build process..."
@after build echo "Build process finished."
