# Release and cross-compilation tasks

# Cross-compilation targets
targets = "x86_64-linux aarch64-linux x86_64-macos aarch64-macos x86_64-windows"

@group release
@desc "Build optimized release for current platform"
task build:
    @needs zig
    zig build -Doptimize=ReleaseFast
    echo "Release build complete"

@group release
@desc "Build for all platforms"
task all:
    @needs zig
    @pre echo "Building for all platforms..."
    mkdir -p dist
    @each {{targets}}
        echo "Building for {{item}}..."
        zig build -Doptimize=ReleaseFast -Dtarget={{item}}
        @if eq({{item}}, x86_64-windows)
            cp zig-out/bin/jake.exe dist/jake-{{item}}.exe
        @else
            cp zig-out/bin/jake dist/jake-{{item}}
        @end
    @post echo "All platforms built!"

@group release
@only-os linux
@desc "Native Linux release build"
task linux:
    @needs zig
    echo "Building native Linux release..."
    zig build -Doptimize=ReleaseFast

@group release
@only-os macos
@desc "Native macOS release build"
task macos:
    @needs zig
    echo "Building native macOS release..."
    zig build -Doptimize=ReleaseFast

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
