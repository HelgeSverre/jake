# Build tasks for jake

@default
@group build
@desc "Compile jake binary"
task build:
    @needs zig
    @cache src/*.zig build.zig build.zig.zon
    @pre echo "Building jake..."
    zig build
    @post echo "Build successful: zig-out/bin/jake"

@group build
@desc "Optimized release build"
task build-release:
    @needs zig
    zig build -Doptimize=ReleaseFast

@group test
@desc "Run all tests"
task test:
    @needs zig
    @pre echo "Running tests..."
    zig build test --summary all
    @post echo "All tests passed!"

@group test
@desc "Check code formatting"
task lint:
    @needs zig
    zig fmt --check src/

@group test
@desc "Auto-format source code"
task format:
    @needs zig
    zig fmt src/

@group build
@desc "Remove build artifacts"
task clean:
    @ignore
    @pre echo "Cleaning..."
    rm -rf zig-out
    rm -rf .zig-cache
    rm -rf .jake
    @post echo "Clean complete"

@group build
@desc "Clean and rebuild from scratch"
task rebuild: [clean, build]
    echo "Rebuild complete"

# Use: jake dev -w to enable file watching
@group dev
@desc "Development build with watch support"
task dev:
    @needs zig
    @watch src/*.zig build.zig Jakefile lib/*.jake
    echo "Use 'jake dev -w' to auto-rebuild on source changes"
    zig build

@group test
@desc "Run end-to-end tests"
task e2e: [build-release]
    @cd tests/e2e
    ../../zig-out/bin/jake test-all

@group test
@desc "Run tests with code coverage (requires kcov)"
task coverage:
    @needs zig, kcov
    @pre echo "Running tests with coverage..."
    zig build test --test-cmd kcov --test-cmd coverage-out --test-cmd-bin
    @post echo "Coverage report: coverage-out/index.html"

@group test
@desc "Run coverage and open report in browser"
task coverage-open: [coverage]
    @if os(macos)
        open coverage-out/index.html
    @elif os(linux)
        xdg-open coverage-out/index.html
    @end

@group test
@desc "Show coverage summary in terminal"
task coverage-summary:
    @needs zig, kcov
    zig build test --test-cmd kcov --test-cmd coverage-out --test-cmd-bin
    cat coverage-out/kcov-merged/coverage.json 2>/dev/null | grep -o '"percent_covered":"[^"]*"' | head -1 || echo "Run 'jake coverage' first"

@group test
@desc "Clean coverage data"
task coverage-clean:
    @ignore
    rm -rf coverage-out
    echo "Coverage data cleaned"

@group install
@desc "Install jake to ~/.local/bin"
task install: [build-release]
    mkdir -p {{home()}}/.local/bin
    cp zig-out/bin/jake {{local_bin("jake")}}
    echo "Installed to {{local_bin("jake")}}"
    echo "Make sure ~/.local/bin is in your PATH"
