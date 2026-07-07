# Benchmarking tasks

# Benchmark configuration
BENCH_WARMUP = "3"
BENCH_RUNS = "100"

@desc "Benchmark jake vs just (requires hyperfine)"
@group bench
@timeout 3m
task bench:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    @pre echo "Building release binary..."
    ./scripts/zig build -Doptimize=ReleaseFast
    @post echo "Benchmark complete!"
    hyperfine --warmup {{BENCH_WARMUP}} \
        './zig-out/bin/jake -l' \
        'just --list' \
        --export-markdown /dev/stdout

@desc "Benchmark startup time"
@group bench
@timeout 2m
task bench-startup:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    ./scripts/zig build -Doptimize=ReleaseFast
    hyperfine --warmup 10 --runs {{BENCH_RUNS}} './zig-out/bin/jake --version'

@desc "Benchmark parsing with different file sizes"
@group bench
@timeout 5m
task bench-parse:
    @needs zig python3
    @needs hyperfine "brew install hyperfine"
    @pre echo "Generating test files..."
    ./scripts/zig build -Doptimize=ReleaseFast
    @each 10 50 100 500
        python3 -c "for i in range({{item}}): print(f'task t{i}:\n    echo {i}\n')" > /tmp/jake-{{item}}.jake
    @end
    hyperfine --warmup {{BENCH_WARMUP}} \
        './zig-out/bin/jake -f /tmp/jake-10.jake -l' \
        './zig-out/bin/jake -f /tmp/jake-50.jake -l' \
        './zig-out/bin/jake -f /tmp/jake-100.jake -l' \
        './zig-out/bin/jake -f /tmp/jake-500.jake -l'

@desc "Benchmark parallel execution scaling"
@group bench
@timeout 3m
task bench-parallel:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    ./scripts/zig build -Doptimize=ReleaseFast
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
    ./scripts/zig build -Doptimize=ReleaseSafe
    @post echo "Close the browser tab to exit samply"
    samply record ./zig-out/bin/jake -l

@desc "Check for memory leaks (macOS)"
@group bench
@platform macos
task leaks:
    @needs zig
    @pre echo "Building release-safe binary..."
    ./scripts/zig build -Doptimize=ReleaseSafe
    @post echo "Leak check complete!"
    leaks --atExit -- ./zig-out/bin/jake -l

# Individual build tasks for parallel size comparison
# Run with: jake bench.sizes -j4

@group bench
@timeout 3m
task _size-debug:
    @needs zig
    ./scripts/zig build -Doptimize=Debug
    cp zig-out/bin/jake /tmp/jake-debug

@group bench
@timeout 3m
task _size-releasesafe:
    @needs zig
    ./scripts/zig build -Doptimize=ReleaseSafe
    cp zig-out/bin/jake /tmp/jake-releasesafe

@group bench
@timeout 3m
task _size-releasefast:
    @needs zig
    ./scripts/zig build -Doptimize=ReleaseFast
    cp zig-out/bin/jake /tmp/jake-releasefast

@group bench
@timeout 3m
task _size-releasesmall:
    @needs zig
    ./scripts/zig build -Doptimize=ReleaseSmall
    cp zig-out/bin/jake /tmp/jake-releasesmall

@desc "Show binary sizes for all optimization levels (use -j4 for parallel)"
@group bench
task sizes: [_size-debug, _size-releasesafe, _size-releasefast, _size-releasesmall]
    @pre echo "Building all optimization levels... (use -j4 for parallel)"
    echo ""
    echo "Binary sizes:"
    ls -lh /tmp/jake-debug /tmp/jake-releasesafe /tmp/jake-releasefast /tmp/jake-releasesmall

@desc "Show peak memory usage"
@group bench
@platform macos
task memory:
    @needs zig
    ./scripts/zig build -Doptimize=ReleaseFast
    /usr/bin/time -l ./zig-out/bin/jake -l 2>&1 | grep -E "maximum resident|real"

@desc "Run all benchmarks"
@group bench
task bench-all: [bench, bench-startup, bench-parse, sizes]
    echo ""
    echo "All benchmarks complete!"

# Private helper for generating large test files
task _generate-large-jakefile:
    @quiet
    python3 -c "
for i in range(1000):
    print(f'task task{i}:')
    print(f'    echo \"Running task {i}\"')
    print()
" > /tmp/large.jake
    echo "Generated /tmp/large.jake with 1000 tasks"
