---
title: Benchmarking Workflows
description: Create reproducible performance testing with iteration and tool validation.
---

Build comprehensive benchmarking workflows using Jake's iteration and validation features.

```jake
@desc "Benchmark with different input sizes"
task bench-scaling:
    @needs hyperfine "brew install hyperfine"
    @pre echo "Generating test files..."

    # Generate test files of different sizes
    @each 10 100 1000 10000
        python3 -c "print('data\\n' * {{item}})" > /tmp/test-{{item}}.txt
    @end

    # Run benchmarks
    hyperfine --warmup 3 \
        './app /tmp/test-10.txt' \
        './app /tmp/test-100.txt' \
        './app /tmp/test-1000.txt' \
        './app /tmp/test-10000.txt' \
        --export-markdown bench-results.md

    @post cat bench-results.md

@desc "Benchmark startup time"
task bench-startup:
    @needs hyperfine
    hyperfine --warmup 10 --runs 100 './app --version'

@desc "Compare against competitors"
task bench-compare:
    @needs hyperfine
    @needs ripgrep "brew install ripgrep"
    @pre echo "Comparing search performance..."
    hyperfine --warmup 3 \
        'grep -r "pattern" src/' \
        'rg "pattern" src/' \
        './app search "pattern" src/' \
        --export-json bench-compare.json

@desc "Show binary sizes for all optimization levels"
task sizes:
    @needs zig
    @pre echo "Building all optimization levels..."
    mkdir -p /tmp/sizes
    @each Debug ReleaseSafe ReleaseFast ReleaseSmall
        zig build -Doptimize={{item}}
        cp zig-out/bin/app /tmp/sizes/app-{{lowercase(item)}}
    @end
    @post ls -lh /tmp/sizes/

@desc "Profile CPU usage"
@only-os macos
task profile:
    @needs samply "brew install samply"
    samply record ./app benchmark-workload

@desc "Check for memory leaks"
@only-os macos
task leaks:
    @pre echo "Running with leak detection..."
    leaks --atExit -- ./app benchmark-workload
    @post echo "Leak check complete"

@desc "Show peak memory usage"
@only-os macos
task memory:
    /usr/bin/time -l ./app benchmark-workload 2>&1 | grep -E "maximum resident|real"

@desc "Benchmark parallel execution scaling"
task bench-parallel:
    @needs hyperfine
    zig build -Doptimize=ReleaseFast
    hyperfine --warmup 2 \
        './app -j1 all' \
        './app -j2 all' \
        './app -j4 all' \
        './app -j8 all'

@desc "Run all benchmarks"
task bench-all: [bench-startup, bench-scaling, bench-compare, sizes]
    echo ""
    echo "All benchmarks complete!"
    echo "Results saved to:"
    echo "  - bench-results.md"
    echo "  - bench-compare.json"
```

## Key Features Used

### Generating Test Data with `@each`

```jake
@each 10 100 1000
    # {{item}} is replaced with each value
    generate-data --size {{item}} > /tmp/data-{{item}}.txt
@end
```

### Tool Validation with Install Hints

```jake
@needs hyperfine "brew install hyperfine"
@needs samply "brew install samply"
```

### Platform-Specific Tasks

```jake
@only-os macos
task leaks:
    leaks --atExit -- ./app

@only-os linux
task valgrind:
    valgrind --leak-check=full ./app
```

### Built-in Functions

```jake
@each Debug ReleaseFast
    # {{lowercase(item)}} → debug, releasefast
    cp binary /tmp/app-{{lowercase(item)}}
@end
```

## Usage

```bash
# Run individual benchmarks
jake bench-startup
jake bench-scaling

# Run all benchmarks
jake bench-all

# View binary sizes
jake sizes
```

## Example Output

```
$ jake bench-scaling

Generating test files...
Benchmark 1: ./app /tmp/test-10.txt
  Time (mean ± σ):      2.1 ms ±  0.3 ms
Benchmark 2: ./app /tmp/test-100.txt
  Time (mean ± σ):      3.4 ms ±  0.2 ms
Benchmark 3: ./app /tmp/test-1000.txt
  Time (mean ± σ):     12.1 ms ±  0.8 ms
Benchmark 4: ./app /tmp/test-10000.txt
  Time (mean ± σ):     89.2 ms ±  2.1 ms

Summary
  ./app /tmp/test-10.txt ran
    1.62 ± 0.26 times faster than ./app /tmp/test-100.txt
    5.76 ± 0.92 times faster than ./app /tmp/test-1000.txt
   42.48 ± 6.51 times faster than ./app /tmp/test-10000.txt
```
