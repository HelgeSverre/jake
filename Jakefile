# Jakefile for building jake itself
# A comprehensive example showcasing jake's features
@import "jake/build.jake"
# Core modules
@import "jake/dev.jake" as dev
@import "jake/test.jake"
@import "jake/release.jake" as release
@import "jake/packaging.jake" as packaging
# Release & packaging
@import "jake/perf.jake" as perf
@import "jake/bench.jake" as bench
@import "jake/stats.jake" as stats
# Performance & benchmarking
@import "jake/git.jake" as git
@import "jake/debug.jake" as debug
@import "jake/maintenance.jake"
# Utilities
@import "jake/web.jake" as web
@import "jake/editors.jake" as editors
#  @import "jake/ai.jake" as ai

@dotenv

@before release.all echo "Starting cross-platform build..."
@before release.package echo "Preparing release package..."
@before build echo "Starting build process..."
@after release.all echo "All platforms built successfully!"
@after build echo "Build process finished."
