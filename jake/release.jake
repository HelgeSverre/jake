# Release and cross-compilation tasks

# Cross-compilation targets
targets = "x86_64-linux aarch64-linux x86_64-macos aarch64-macos x86_64-windows"

@group release
@desc "Build optimized release for current platform"
task build:
    @needs zig
    @cache src/*.zig build.zig build.zig.zon
    ./scripts/zig build -Doptimize=ReleaseFast
    echo "Release build complete"

# Individual platform build tasks for parallel execution
# Run with: jake release.all -j5

@group release
@desc "Build for x86_64-linux"
@timeout 5m
task _build-x86_64-linux:
    @needs zig
    mkdir -p dist
    ./scripts/zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux
    cp zig-out/bin/jake dist/jake-x86_64-linux

@group release
@desc "Build for aarch64-linux"
@timeout 5m
task _build-aarch64-linux:
    @needs zig
    mkdir -p dist
    ./scripts/zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux
    cp zig-out/bin/jake dist/jake-aarch64-linux

@group release
@desc "Build for x86_64-macos"
@timeout 5m
task _build-x86_64-macos:
    @needs zig
    mkdir -p dist
    ./scripts/zig build -Doptimize=ReleaseFast -Dtarget=x86_64-macos
    cp zig-out/bin/jake dist/jake-x86_64-macos

@group release
@desc "Build for aarch64-macos"
@timeout 5m
task _build-aarch64-macos:
    @needs zig
    mkdir -p dist
    ./scripts/zig build -Doptimize=ReleaseFast -Dtarget=aarch64-macos
    cp zig-out/bin/jake dist/jake-aarch64-macos

@group release
@desc "Build for x86_64-windows"
@timeout 5m
task _build-x86_64-windows:
    @needs zig
    mkdir -p dist
    ./scripts/zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows
    cp zig-out/bin/jake.exe dist/jake-x86_64-windows.exe

@group release
@desc "Build for all platforms (use -j5 for parallel builds)"
task all: [_build-x86_64-linux, _build-aarch64-linux, _build-x86_64-macos, _build-aarch64-macos, _build-x86_64-windows]
    @pre echo "Building for all 5 platforms... (use -j5 for parallel)"
    @post echo "All platforms built! See dist/"
    @post ls -lh dist/

@group release
@platform linux
@desc "Native Linux release build"
task linux:
    @needs zig
    echo "Building native Linux release..."
    ./scripts/zig build -Doptimize=ReleaseFast

@group release
@platform macos
@desc "Native macOS release build"
task macos:
    @needs zig
    echo "Building native macOS release..."
    ./scripts/zig build -Doptimize=ReleaseFast

@group release
@desc "Generate SHA256 checksums for all builds"
task checksums: [all]
    @needs shasum "Standard on macOS/Linux, or install coreutils"
    @cd dist
        @if exists(checksums.txt)
            rm checksums.txt
        @end
        shasum -a 256 jake-* > checksums.txt
    echo "Checksums generated: dist/checksums.txt"

@group release
@desc "Create versioned release package"
task package: [checksums]
    @confirm Create release package?
    @if env(VERSION)
        echo "Creating release v$VERSION..."
        mkdir -p releases/v$VERSION
        cp dist/* releases/v$VERSION/
        echo "Release packaged: releases/v$VERSION/"
    @else
        echo "Error: VERSION not set. Use VERSION=x.y.z jake release.package"
    @end
