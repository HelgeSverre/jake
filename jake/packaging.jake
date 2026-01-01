# Packaging & Distribution tasks

version = "0.3.0"

@desc "Build release binary for current platform"
@group packaging
task binary:
    @needs zig
    @pre echo "Building release binary..."
    zig build -Doptimize=ReleaseSafe
    @post echo "Binary: zig-out/bin/jake"

@desc "Build release binaries for all platforms (requires cross-compilation)"
@group packaging
task binaries:
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
task docker:
    @needs docker
    @pre echo "Building Docker image..."
    docker build -t jake:{{version}} -t jake:latest -f packaging/docker/Dockerfile .
    @post docker images jake

@desc "Test Homebrew formula locally"
@group packaging
@only-os macos
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
