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
    @watch src/*.zig build.zig Jakefile jake/*.jake
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
    # Build tests first, then find and run the test binary with kcov
    # (Zig 0.15+ removed --test-cmd flag, so we run kcov directly)
    zig build test 2>/dev/null || true
    rm -rf coverage-out
    kcov --include-pattern={{absolute_path("src")}}/ coverage-out $(find .zig-cache/o -name "test" -type f -perm +111 -size +2M 2>/dev/null | xargs ls -t | head -1)
    @post echo "Coverage report: coverage-out/index.html"

@group test
@desc "Run coverage and open report in browser"
task coverage-open: [coverage]
    @launch coverage-out/index.html

@group test
@desc "Show coverage summary in terminal"
task coverage-summary: [coverage]
    cat coverage-out/test.*/coverage.json 2>/dev/null | grep '"percent_covered":' | tail -1 | sed 's/.*"percent_covered": "\([^"]*\)".*/Coverage: \1%/' || echo "No coverage data found"

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
