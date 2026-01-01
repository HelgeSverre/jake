# Benchmarking tasks

@desc "Benchmark jake vs just (requires hyperfine)"
@group bench
task bench:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    @pre echo "Building release binary..."
    zig build -Doptimize=ReleaseFast
    @post echo "Benchmark complete!"
    hyperfine --warmup 3 \
        './zig-out/bin/jake -l' \
        'just --list' \
        --export-markdown /dev/stdout

@desc "Benchmark startup time"
@group bench
task bench-startup:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    zig build -Doptimize=ReleaseFast
    hyperfine --warmup 10 --runs 100 './zig-out/bin/jake --version'

@desc "Benchmark parsing with different file sizes"
@group bench
task bench-parse:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    @pre echo "Generating test files..."
    zig build -Doptimize=ReleaseFast
    @each 10 50 100 500
        python3 -c "for i in range({{item}}): print(f'task t{i}:\n    echo {i}\n')" > /tmp/jake-{{item}}.jake
    @end
    hyperfine --warmup 3 \
        './zig-out/bin/jake -f /tmp/jake-10.jake -l' \
        './zig-out/bin/jake -f /tmp/jake-50.jake -l' \
        './zig-out/bin/jake -f /tmp/jake-100.jake -l' \
        './zig-out/bin/jake -f /tmp/jake-500.jake -l'

@desc "Benchmark parallel execution scaling"
@group bench
task bench-parallel:
    @needs zig
    @needs hyperfine "brew install hyperfine"
    zig build -Doptimize=ReleaseFast
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
    zig build -Doptimize=ReleaseSafe
    @post echo "Close the browser tab to exit samply"
    samply record ./zig-out/bin/jake -l

@desc "Check for memory leaks (macOS)"
@group bench
@only-os macos
task leaks:
    @needs zig
    @pre echo "Building release-safe binary..."
    zig build -Doptimize=ReleaseSafe
    @post echo "Leak check complete!"
    leaks --atExit -- ./zig-out/bin/jake -l

@desc "Show binary sizes for all optimization levels"
@group bench
task sizes:
    @needs zig
    @pre echo "Building all optimization levels..."
    @each Debug ReleaseSafe ReleaseFast ReleaseSmall
        zig build -Doptimize={{item}}
        cp zig-out/bin/jake /tmp/jake-{{lowercase(item)}}
    @end
    echo ""
    echo "Binary sizes:"
    ls -lh /tmp/jake-debug /tmp/jake-releasesafe /tmp/jake-releasefast /tmp/jake-releasesmall

@desc "Show peak memory usage"
@group bench
@only-os macos
task memory:
    @needs zig
    zig build -Doptimize=ReleaseFast
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
