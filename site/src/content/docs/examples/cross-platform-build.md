---
title: Cross-Platform Builds
description: Build binaries for multiple platforms using iteration and conditionals.
---

Build release binaries for multiple operating systems and architectures from a single machine using Zig's cross-compilation.

```jake
# Define target platforms as a variable
targets = "x86_64-linux aarch64-linux x86_64-macos aarch64-macos x86_64-windows"

@desc "Build for all platforms"
task release-all:
    @needs zig
    @pre echo "Building for all platforms..."
    mkdir -p dist
    @each {{targets}}
        echo "Building for {{item}}..."
        zig build -Doptimize=ReleaseFast -Dtarget={{item}}
        @if eq({{item}}, x86_64-windows)
            cp zig-out/bin/app.exe dist/app-{{item}}.exe
        @else
            cp zig-out/bin/app dist/app-{{item}}
        @end
    @post echo "All platforms built!"

@desc "Generate checksums for release binaries"
task checksums: [release-all]
    @cd dist
        shasum -a 256 app-* > checksums.txt
    echo "Checksums: dist/checksums.txt"

@desc "Create versioned release package"
task package: [checksums]
    @confirm Create release package?
    @if env(VERSION)
        mkdir -p releases/v$VERSION
        cp dist/* releases/v$VERSION/
        echo "Release packaged: releases/v$VERSION/"
    @else
        echo "Error: VERSION not set"
        echo "Usage: VERSION=1.0.0 jake package"
    @end
```

## Key Features Used

- **`@each`** - Iterate over a list of items
- **`{{item}}`** - Access current iteration value
- **`@if eq()`** - Conditional logic based on string equality
- **`@cd`** - Change directory for subsequent commands
- **`@confirm`** - Require user confirmation before proceeding
- **`env()`** - Check if an environment variable is set

## Usage

```bash
# Build for all platforms
jake release-all

# Build and generate checksums
jake checksums

# Create versioned release (prompts for confirmation)
VERSION=1.0.0 jake package
```
