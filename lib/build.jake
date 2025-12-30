# Build tasks for jake

@default
@desc "Compile jake binary"
task build:
    @needs zig
    @pre echo "Building jake..."
    zig build
    @post echo "Build successful: zig-out/bin/jake"

@desc "Optimized release build"
task build-release:
    @needs zig
    zig build -Doptimize=ReleaseFast

@desc "Run all tests"
task test:
    @needs zig
    @pre echo "Running tests..."
    zig build test --summary all
    @post echo "All tests passed!"

@desc "Check code formatting"
task lint:
    @needs zig
    zig fmt --check src/

@desc "Auto-format source code"
task format:
    @needs zig
    zig fmt src/

@desc "Remove build artifacts"
task clean:
    @pre echo "Cleaning..."
    rm -rf zig-out
    rm -rf .zig-cache
    rm -rf .jake
    @post echo "Clean complete"

@desc "Clean and rebuild from scratch"
task rebuild: [clean, build]
    echo "Rebuild complete"

# Use: jake dev -w to enable file watching
@desc "Development build with watch support"
task dev:
    @needs zig
    echo "Use 'jake dev -w' to auto-rebuild on source changes"
    zig build

@desc "Run end-to-end tests"
task e2e: [build-release]
    @pre echo "Running E2E tests..."
    @cd samples
    ../zig-out/bin/jake test-all
    @post echo "E2E tests passed!"

@desc "Install jake to ~/.local/bin"
task install: [build-release]
    mkdir -p {{home()}}/.local/bin
    cp zig-out/bin/jake {{local_bin("jake")}}
    echo "Installed to {{local_bin("jake")}}"
    echo "Make sure ~/.local/bin is in your PATH"
