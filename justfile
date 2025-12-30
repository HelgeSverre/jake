# jake - a justfile runner written in Zig

# Default: show available recipes
default:
    @just --list

# ─────────────────────────────────────────────────────────────────────────────
# Building
# ─────────────────────────────────────────────────────────────────────────────

# Build the project (debug mode)
[group('build')]
build:
    zig build

# Build with ReleaseFast optimizations
[group('build')]
release:
    zig build -Doptimize=ReleaseFast

# Build smallest binary
[group('build')]
release-small:
    zig build -Doptimize=ReleaseSmall

# Build with safety checks enabled
[group('build')]
release-safe:
    zig build -Doptimize=ReleaseSafe

# ─────────────────────────────────────────────────────────────────────────────
# Running
# ─────────────────────────────────────────────────────────────────────────────

# Build and run the application
[group('run')]
run *ARGS:
    zig build run {{ if ARGS != "" { "-- " + ARGS } else { "" } }}

# ─────────────────────────────────────────────────────────────────────────────
# Testing
# ─────────────────────────────────────────────────────────────────────────────

# Run all tests
[group('test')]
test:
    zig build test --summary all

# Run tests with verbose output
[group('test')]
test-verbose:
    zig build test --summary all

# ─────────────────────────────────────────────────────────────────────────────
# Code Quality
# ─────────────────────────────────────────────────────────────────────────────

# Format all Zig source files
[group('quality')]
fmt:
    zig fmt src/

# Check formatting without modifying files
[group('quality')]
fmt-check:
    zig fmt --check src/

# ─────────────────────────────────────────────────────────────────────────────
# Development
# ─────────────────────────────────────────────────────────────────────────────

# Watch and rebuild on changes (requires entr)
[group('dev')]
watch:
    find src -name '*.zig' | entr -c just build

# Watch and run tests on changes (requires entr)
[group('dev')]
watch-test:
    find src -name '*.zig' | entr -c just test

# ─────────────────────────────────────────────────────────────────────────────
# Maintenance
# ─────────────────────────────────────────────────────────────────────────────

# Remove build artifacts and generated docs
[group('maintenance')]
clean:
    rm -rf .zig-cache zig-out

# Fetch dependencies
[group('maintenance')]
fetch:
    zig build --fetch

# Install to ~/.local/bin
[group('maintenance')]
install:
    zig build --prefix ~/.local

# Generate Zig API documentation (into zig-out/docs)
[group('maintenance')]
docs:
    zig build-lib src/root.zig -femit-docs=zig-out/docs -fno-emit-bin

# ─────────────────────────────────────────────────────────────────────────────
# CI (requires: brew install act)
# ─────────────────────────────────────────────────────────────────────────────

# Run CI workflow locally via act (requires: brew install act)
# Note: May fail if Zig download mirrors are unavailable
[group('ci')]
ci:
    act push -W .github/workflows/ci.yml -P ubuntu-latest=catthehacker/ubuntu:act-latest --container-architecture linux/amd64

# ─────────────────────────────────────────────────────────────────────────────
# Fuzzing
# ─────────────────────────────────────────────────────────────────────────────

# Fuzz the Jakefile parser (dumb fuzzer, no dependencies)
[group('fuzz')]
fuzz ITERATIONS="1000":
    zig build fuzz-parse -Doptimize=ReleaseSafe
    ./scripts/dumb-fuzz.sh {{ ITERATIONS }}

# Fuzz using AFL++ in dumb mode (requires: brew install afl++)
# Use -n because Zig's -ffuzz instrumentation isn't AFL-compatible
[group('fuzz')]
fuzz-afl:
    zig build fuzz-parse -Doptimize=ReleaseSafe
    mkdir -p corpus findings
    cp Jakefile corpus/main.jake 2>/dev/null || true
    find samples -name "Jakefile" -exec sh -c 'cp "$1" "corpus/$(echo $1 | tr / -)"' _ {} \; 2>/dev/null || true
    find samples -name "*.jake" -type f -exec cp {} corpus/ \; 2>/dev/null || true
    AFL_SKIP_CPUFREQ=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 afl-fuzz -n -i corpus -o findings -- ./zig-out/bin/jake-fuzz-parse @@

# ─────────────────────────────────────────────────────────────────────────────
# E2E Tests
# ─────────────────────────────────────────────────────────────────────────────

# Run E2E test suite using jake
[group('test')]
e2e: release
    cd samples && ../zig-out/bin/jake test-all

# ─────────────────────────────────────────────────────────────────────────────
# Benchmarking & Profiling
# ─────────────────────────────────────────────────────────────────────────────

# Benchmark jake vs just (requires: brew install hyperfine)
[group('bench')]
bench: release
    hyperfine --warmup 3 \
      './zig-out/bin/jake -l' \
      'just --list' \
      --export-markdown /dev/stdout

# Benchmark startup time
[group('bench')]
bench-startup: release
    hyperfine --warmup 10 --runs 100 './zig-out/bin/jake --version'

# Benchmark parsing with different file sizes
[group('bench')]
bench-parse: release
    #!/usr/bin/env bash
    for n in 10 50 100 500; do
      python3 -c "for i in range($n): print(f'task t{i}:\n    echo {i}\n')" > /tmp/jake-$n.jake
    done
    hyperfine --warmup 3 \
      './zig-out/bin/jake -f /tmp/jake-10.jake -l' \
      './zig-out/bin/jake -f /tmp/jake-50.jake -l' \
      './zig-out/bin/jake -f /tmp/jake-100.jake -l' \
      './zig-out/bin/jake -f /tmp/jake-500.jake -l'

# Benchmark parallel scaling
[group('bench')]
bench-parallel: release
    hyperfine --warmup 2 \
      './zig-out/bin/jake -j1 -n all' \
      './zig-out/bin/jake -j2 -n all' \
      './zig-out/bin/jake -j4 -n all' \
      './zig-out/bin/jake -j8 -n all'

# Profile with samply (requires: brew install samply)
[group('bench')]
profile: release-safe
    samply record ./zig-out/bin/jake -l

# Check for memory leaks (macOS)
[group('bench')]
leaks: release-safe
    leaks --atExit -- ./zig-out/bin/jake -l

# Show binary sizes for all optimization levels
[group('bench')]
sizes:
    @echo "Building all optimization levels..."
    @zig build -Doptimize=Debug && cp zig-out/bin/jake /tmp/jake-debug
    @zig build -Doptimize=ReleaseSafe && cp zig-out/bin/jake /tmp/jake-safe
    @zig build -Doptimize=ReleaseFast && cp zig-out/bin/jake /tmp/jake-fast
    @zig build -Doptimize=ReleaseSmall && cp zig-out/bin/jake /tmp/jake-small
    @echo ""
    @echo "Binary sizes:"
    @ls -lh /tmp/jake-debug /tmp/jake-safe /tmp/jake-fast /tmp/jake-small

# ─────────────────────────────────────────────────────────────────────────────
# Info
# ─────────────────────────────────────────────────────────────────────────────

# Show project info
[group('info')]
info:
    @echo "Project: jake"
    @echo "Zig version: $(zig version)"
    @echo "Source files:"
    @find src -name '*.zig' | xargs wc -l | tail -1

# Show zig build options
[group('info')]
zig-help:
    zig build --help
