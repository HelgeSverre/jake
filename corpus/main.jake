# Jakefile for building jake itself
# A comprehensive example showcasing jake's features

@import "lib/build.jake"
@import "lib/release.jake" as release

@dotenv

# Variables
version = "0.2.0"
binary = "jake"

# Global hooks
@pre echo "=== Jake Build System v{{version}} ==="
@on_error echo "Build failed!"

# Default: build and test
@default
@desc "Build and test everything"
task all: [build, test]
    echo "Build complete!"

@desc "Development build with optional watch mode"
task dev: [build]
    @if is_watching()
        echo "Watching for changes..."
    @else
        echo "Run with 'jake dev -w' for auto-rebuild"
    @end

@desc "Show current build info and version"
task info:
    @if exists(zig-out/bin/jake)
        echo "Binary: zig-out/bin/jake"
        ./zig-out/bin/jake --version
    @else
        echo "Binary not built yet. Run: jake build"
    @end

@desc "Run all CI checks"
task ci: [lint, test, build]
    echo "CI checks passed!"

@desc "Fuzz the Jakefile parser (1000 iterations)"
task fuzz:
    @needs zig
    zig build fuzz-parse -Doptimize=ReleaseSafe
    ./scripts/dumb-fuzz.sh 1000

@desc "Fuzz using AFL++ (requires afl++)"
task fuzz-afl:
    @needs zig
    @needs afl-fuzz
    zig build fuzz-parse -Doptimize=ReleaseSafe
    mkdir -p corpus findings
    cp Jakefile corpus/ 2>/dev/null || true
    find samples -name "Jakefile" -exec cp {} corpus/ \; 2>/dev/null || true
    find samples -name "*.jake" -exec cp {} corpus/ \; 2>/dev/null || true
    afl-fuzz -i corpus -o findings -- ./zig-out/bin/jake-fuzz-parse @@

@desc "Quick pre-commit checks"
task check: [lint, test]
    echo "Pre-commit checks passed!"
