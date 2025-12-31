# Jakefile for building jake itself
# A comprehensive example showcasing jake's features

@import "jake/build.jake"
@import "jake/release.jake" as release
@import "jake/web.jake" as web
@import "jake/perf.jake" as perf
@import "jake/editors.jake" as editors

@dotenv

# Variables
version = "0.3.0"
binary = "jake"
JAKE_FUZZ_PORT = "4455"

# Export version for child processes
@export version

# Global hooks
@on_error echo "Build failed!"

# Targeted hooks for release tasks
@before release.all echo "Starting cross-platform build..."
@after release.all echo "All platforms built successfully!"
@before release.package echo "Preparing release package..."

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

@group test
@desc "Run coverage-guided fuzz testing"
task fuzz:
    @needs zig
    @pre echo "Running fuzz tests with coverage guidance..."
    @pre echo "Web UI: http://127.0.0.1:{{JAKE_FUZZ_PORT}}"
    zig build fuzz --fuzz --webui=127.0.0.1:{{JAKE_FUZZ_PORT}} -Doptimize=ReleaseSafe -j4

@group dev
@desc "Quick pre-commit checks"
task check: [lint, test]
    echo "Pre-commit checks passed!"

@group test
@desc "Test shell completions (bash, zsh, fish)"
task test-completions: [build]
    ./tests/completions_test.sh

@group test
@desc "Test completions in Docker (isolated environment)"
task test-completions-docker:
    @needs docker
    docker build -t jake-completions-test -f tests/Dockerfile.completions .
    docker run --rm jake-completions-test

# ============================================================================
# Benchmarking & Profiling
# ============================================================================

@desc "Benchmark jake vs just (requires hyperfine)"
@group bench
task bench:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    @pre echo "Building release binary..."
    zig build -Doptimize=ReleaseFast
    @post echo "Benchmark complete!"
    hyperfine --warmup 3 \
        './zig-out/bin/jake -l' \
        'just --list' \
        --export-markdown /dev/stdout

@desc "Benchmark startup time"
@group bench
task bench-startup:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    zig build -Doptimize=ReleaseFast
    hyperfine --warmup 10 --runs 100 './zig-out/bin/jake --version'

@desc "Benchmark parsing with different file sizes"
@group bench
task bench-parse:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    @pre echo "Generating test files..."
    zig build -Doptimize=ReleaseFast
    @each 10 50 100 500
        python3 -c "for i in range({{item}}): print(f'task t{i}:\n    echo {i}\n')" > /tmp/jake-{{item}}.jake
    @end
    hyperfine --warmup 3 \
        './zig-out/bin/jake -f /tmp/jake-10.jake -l' \
        './zig-out/bin/jake -f /tmp/jake-50.jake -l' \
        './zig-out/bin/jake -f /tmp/jake-100.jake -l' \
        './zig-out/bin/jake -f /tmp/jake-500.jake -l'

@desc "Benchmark parallel execution scaling"
@group bench
task bench-parallel:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    zig build -Doptimize=ReleaseFast
    hyperfine --warmup 2 \
        './zig-out/bin/jake -j1 -n all' \
        './zig-out/bin/jake -j2 -n all' \
        './zig-out/bin/jake -j4 -n all' \
        './zig-out/bin/jake -j8 -n all'

@desc "Profile with samply (opens flamegraph UI)"
@group bench
task profile:
    @needs zig
    @needs samply "brew install samply"
    @pre echo "Building with debug symbols..."
    zig build -Doptimize=ReleaseSafe
    @post echo "Close the browser tab to exit samply"
    samply record ./zig-out/bin/jake -l

@desc "Check for memory leaks (macOS)"
@group bench
@only-os macos
task leaks:
    @needs zig
    @pre echo "Building release-safe binary..."
    zig build -Doptimize=ReleaseSafe
    @post echo "Leak check complete!"
    leaks --atExit -- ./zig-out/bin/jake -l

@desc "Show binary sizes for all optimization levels"
@group bench
task sizes:
    @needs zig
    @pre echo "Building all optimization levels..."
    @each Debug ReleaseSafe ReleaseFast ReleaseSmall
        zig build -Doptimize={{item}}
        cp zig-out/bin/jake /tmp/jake-{{lowercase(item)}}
    @end
    echo ""
    echo "Binary sizes:"
    ls -lh /tmp/jake-debug /tmp/jake-releasesafe /tmp/jake-releasefast /tmp/jake-releasesmall

@desc "Show peak memory usage"
@group bench
@only-os macos
task memory:
    @needs zig
    zig build -Doptimize=ReleaseFast
    /usr/bin/time -l ./zig-out/bin/jake -l 2>&1 | grep -E "maximum resident|real"

@desc "Run all benchmarks"
@group bench
task bench-all: [bench, bench-startup, bench-parse, sizes]
    echo ""
    echo "All benchmarks complete!"

# ============================================================================
# Private helper for generating large test files
# ============================================================================

task _generate-large-jakefile:
    @quiet
    python3 -c "
for i in range(1000):
    print(f'task task{i}:')
    print(f'    echo \"Running task {i}\"')
    print()
" > /tmp/large.jake
    echo "Generated /tmp/large.jake with 1000 tasks"

# ============================================================================
# Packaging & Distribution
# ============================================================================

@desc "Build release binary for current platform"
@group packaging
task package.binary:
    @needs zig
    @pre echo "Building release binary..."
    zig build -Doptimize=ReleaseSafe
    @post echo "Binary: zig-out/bin/jake"

@desc "Build release binaries for all platforms (requires cross-compilation)"
@group packaging
task package.binaries:
    @needs zig
    @pre echo "Building cross-platform binaries..."
    mkdir -p dist
    @each x86_64-linux aarch64-linux x86_64-macos aarch64-macos
        echo "Building for {{item}}..."
        zig build -Doptimize=ReleaseSafe -Dtarget={{item}}
        cp zig-out/bin/jake dist/jake-{{item}}
    @end
    @post ls -lh dist/

@desc "Build Docker image"
@group packaging
task package.docker:
    @needs docker
    @pre echo "Building Docker image..."
    docker build -t jake:{{version}} -t jake:latest -f packaging/docker/Dockerfile .
    @post docker images jake

@desc "Test Homebrew formula locally"
@group packaging
@only-os macos
task package.homebrew-test:
    @needs brew
    @pre echo "Testing Homebrew formula..."
    brew install --build-from-source ./packaging/homebrew/jake.rb
    @post jake --version

@desc "Build Nix package"
@group packaging
task package.nix:
    @needs nix
    @pre echo "Building Nix package..."
    cd packaging/nix && nix build
    @post ls -lh packaging/nix/result/bin/jake

@desc "Generate AUR source package"
@group packaging
task package.aur:
    @pre echo "Generating AUR source package..."
    cd packaging/aur && makepkg --source
    @post ls -lh packaging/aur/*.src.tar.gz

@desc "Generate checksums for release binaries"
@group packaging
task package.checksums:
    @pre echo "Generating checksums..."
    @if exists(dist)
        cd dist && sha256sum jake-* > SHA256SUMS
        cat dist/SHA256SUMS
    @else
        echo "No dist/ directory. Run: jake package-binaries"
    @end

@desc "Test install script locally"
@group packaging
task package.install-test:
    @pre echo "Testing install script..."
    JAKE_INSTALL=/tmp/jake-test sh packaging/install.sh
    /tmp/jake-test/jake --version
    rm -rf /tmp/jake-test

@desc "Build all packages"
@group packaging
task package.all: [package-binaries, package-docker, package-checksums]
    @post echo "All packages built! See dist/ directory."

# ============================================================================
# Code Statistics
# ============================================================================

@group stats
@desc "Count lines of code in Zig sources"
task loc:
    @pre echo "Lines of code:"
    find src -name "*.zig" | xargs wc -l | tail -1

@group stats
@desc "Find TODO:/FIXME:/HACK: comments in source"
task todos:
    @ignore
    grep -rn "TODO:\|FIXME:\|HACK:\|XXX:" src/ || echo "No TODOs found!"

@group stats
@desc "Show largest source files by line count"
task complexity:
    @pre echo "Largest source files:"
    wc -l src/*.zig | sort -n | tail -10

# ============================================================================
# Git & Release Workflow
# ============================================================================

@group git
@desc "Show changelog since last tag"
task changelog:
    @pre echo "Changes since last release:"
    git log --oneline $(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~10)..HEAD

@group git
@desc "Create and push a git tag for current version"
task tag:
    @confirm Create tag v{{version}} and push to remote?
    git tag -a v{{version}} -m "Release v{{version}}"
    git push origin v{{version}}
    echo "Tagged and pushed v{{version}}"

@group git
@desc "Show project contributors"
task contributors:
    @pre echo "Project contributors:"
    git shortlog -sn

# ============================================================================
# Debugging & Inspection
# ============================================================================

@group debug
@desc "Run jake with verbose tracing"
task trace:
    @needs zig
    zig build -Doptimize=ReleaseFast
    ./zig-out/bin/jake -v {{$1}}

@group debug
@desc "Show environment and system info"
task env-info:
    echo "Jake version: {{version}}"
    echo "Platform: $(uname -s) $(uname -m)"
    echo "Home: {{home()}}"
    echo "Shell: $SHELL"
    echo "PATH contains jake: "
    which jake || echo "jake not in PATH"

# ============================================================================
# Maintenance
# ============================================================================

@group maintenance
@desc "Rebuild and reinstall jake"
task self-update: [build-release]
    @pre echo "Reinstalling jake..."
    # Use atomic replacement to avoid macOS code signature invalidation
    cp zig-out/bin/jake {{local_bin("jake")}}.new
    mv {{local_bin("jake")}}.new {{local_bin("jake")}}
    @post echo "Updated {{local_bin(\"jake\")}}"

@group maintenance
@desc "Remove jake from local bin"
task uninstall:
    rm -f {{local_bin("jake")}}
    echo "Removed {{local_bin(\"jake\")}}"

@group maintenance
@desc "Clear jake cache files"
task cache-clean:
    @ignore
    rm -rf .jake
    echo "Jake cache cleared"

@group maintenance
@desc "Remove all build artifacts and caches"
task prune:
    @ignore
    @pre echo "Pruning build artifacts..."
    rm -rf zig-out .zig-cache .jake dist
    @post echo "All artifacts removed"
