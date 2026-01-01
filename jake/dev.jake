# Development workflow tasks

# Variables
version = "0.3.0"
binary = "jake"

@export version

# Default: build and test
@default
@group dev
@desc "Build and test everything"
task all: [build, test]
    echo "Build complete!"

@group dev
@desc "Development build with optional watch mode"
task dev: [build]
    @watch src/*.zig build.zig Jakefile jake/*.jake
    @if is_watching()
        echo "Watching for changes..."
    @else
        echo "Run with 'jake dev -w' for auto-rebuild"
    @end

@group dev
@desc "Show current build info and version"
task info:
    @if exists(zig-out/bin/jake)
        echo "Binary: zig-out/bin/jake"
        ./zig-out/bin/jake --version
    @else
        echo "Binary not built yet. Run: jake build"
    @end

@group dev
@desc "Run all CI checks"
task ci: [lint, test, build]
    echo "CI checks passed!"

@group dev
@desc "Quick pre-commit checks"
task check: [lint, test]
    echo "Pre-commit checks passed!"
