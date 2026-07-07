# Packaging & Distribution tasks

# Version is set from git tags at build time, or use VERSION env var
version = "0.6.0"

@desc "Build release binary for current platform"
@group packaging
task binary:
    @needs zig
    @cache src/*.zig build.zig build.zig.zon
    @pre echo "Building release binary..."
    ./scripts/zig build -Doptimize=ReleaseSafe
    @post echo "Binary: zig-out/bin/jake"

# Individual platform build tasks for parallel execution
# Run with: jake packaging.binaries -j4

@group packaging
@timeout 5m
task _pkg-x86_64-linux:
    @needs zig
    mkdir -p dist
    ./scripts/zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux
    cp zig-out/bin/jake dist/jake-x86_64-linux

@group packaging
@timeout 5m
task _pkg-aarch64-linux:
    @needs zig
    mkdir -p dist
    ./scripts/zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-linux
    cp zig-out/bin/jake dist/jake-aarch64-linux

@group packaging
@timeout 5m
task _pkg-x86_64-macos:
    @needs zig
    mkdir -p dist
    ./scripts/zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-macos
    cp zig-out/bin/jake dist/jake-x86_64-macos

@group packaging
@timeout 5m
task _pkg-aarch64-macos:
    @needs zig
    mkdir -p dist
    ./scripts/zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos
    cp zig-out/bin/jake dist/jake-aarch64-macos

@desc "Build release binaries for all platforms (use -j4 for parallel)"
@group packaging
task binaries: [_pkg-x86_64-linux, _pkg-aarch64-linux, _pkg-x86_64-macos, _pkg-aarch64-macos]
    @pre echo "Building cross-platform binaries... (use -j4 for parallel)"
    @post ls -lh dist/

@desc "Build Docker image"
@group packaging
@timeout 10m
task docker:
    @needs docker
    @pre echo "Building Docker image..."
    @if env(VERSION)
        docker build -t jake:$VERSION -t jake:latest -f packaging/docker/Dockerfile .
    @else
        docker build -t jake:{{version}} -t jake:latest -f packaging/docker/Dockerfile .
    @end
    @post docker images jake

@desc "Test Homebrew formula locally"
@group packaging
@platform macos
task homebrew-test:
    @needs brew
    @pre echo "Testing Homebrew formula..."
    brew install --build-from-source ./packaging/homebrew/jake.rb
    @post jake --version

@desc "Build Nix package"
@group packaging
task nix:
    @needs nix
    @pre echo "Building Nix package..."
    cd packaging/nix && nix build
    @post ls -lh packaging/nix/result/bin/jake

@desc "Generate AUR source package"
@group packaging
task aur:
    @pre echo "Generating AUR source package..."
    cd packaging/aur && makepkg --source
    @post ls -lh packaging/aur/*.src.tar.gz

@desc "Generate checksums for release binaries"
@group packaging
task checksums:
    @pre echo "Generating checksums..."
    @if exists(dist)
        cd dist && sha256sum jake-* > SHA256SUMS
        cat dist/SHA256SUMS
    @else
        echo "No dist/ directory. Run: jake packaging.binaries"
    @end

@desc "Test install script locally"
@group packaging
task install-test:
    @pre echo "Testing install script..."
    JAKE_INSTALL=/tmp/jake-test sh packaging/install.sh
    /tmp/jake-test/jake --version
    rm -rf /tmp/jake-test

@desc "Build all packages"
@group packaging
task all: [binaries, docker, checksums]
    @post echo "All packages built! See dist/ directory."
