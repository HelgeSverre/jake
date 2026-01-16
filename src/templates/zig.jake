# Jakefile - Zig Template
# For Zig projects using the Zig build system

# -----------------------------------------------------------------------------
# Default
# -----------------------------------------------------------------------------

# Default task - runs when you type just `jake`
task default: build

# -----------------------------------------------------------------------------
# Build
# -----------------------------------------------------------------------------

@group build
@desc "Build in debug mode"
task build:
    zig build

@group build
@desc "Build with optimizations"
task release:
    zig build -Doptimize=ReleaseFast

@group build
@desc "Build with size optimizations"
task release-small:
    zig build -Doptimize=ReleaseSmall

@group build
@desc "Build with safety checks"
task release-safe:
    zig build -Doptimize=ReleaseSafe

# -----------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------

@group dev
@desc "Build and run"
task run:
    zig build run

@group dev
@desc "Run with arguments"
task run-args *args:
    zig build run -- {{args}}

@group dev
@desc "Run in release mode"
task run-release:
    zig build run -Doptimize=ReleaseFast

# -----------------------------------------------------------------------------
# Test
# -----------------------------------------------------------------------------

@group test
@desc "Run all tests"
task test:
    zig build test

@group test
@desc "Run tests with summary"
task test-v:
    zig build test --summary all

@group test
@desc "Run specific test filter"
task test-filter filter:
    zig build test -- --test-filter "{{filter}}"

# -----------------------------------------------------------------------------
# Code Quality
# -----------------------------------------------------------------------------

@group lint
@desc "Format source files"
task fmt:
    zig fmt src/

@group lint
@desc "Check formatting"
task fmt-check:
    zig fmt --check src/

@group lint
@desc "Format all Zig files"
task fmt-all:
    find . -name "*.zig" -not -path "./.zig-cache/*" | xargs zig fmt

# -----------------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------------

@group clean
@desc "Clean build artifacts"
task clean:
    rm -rf zig-out/
    rm -rf .zig-cache/

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------

@group util
@desc "Fetch build.zig.zon dependencies"
task fetch:
    zig fetch --save

@group util
@desc "Show build options"
task options:
    zig build --help
