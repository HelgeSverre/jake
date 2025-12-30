# Profiling and Benchmarking Jake

This document covers tools and techniques for profiling, benchmarking, and optimizing jake.

## Quick Reference

| Tool | Purpose | Install |
|------|---------|---------|
| hyperfine | CLI benchmarking | `brew install hyperfine` |
| samply | CPU profiling with flamegraphs | `brew install samply` |
| leaks | Memory leak detection (macOS) | Built-in |
| Instruments | Full profiling suite (macOS) | Xcode |
| Zig GPA | Allocation tracking | Built-in |

## Benchmarking with Hyperfine

Hyperfine runs commands multiple times and provides statistical analysis.

### Compare jake vs just vs make

```sh
# Benchmark listing tasks
hyperfine --warmup 3 \
  './zig-out/bin/jake -l' \
  'just --list' \
  'make -n' \
  --export-markdown bench-list.md

# Benchmark dry-run execution
hyperfine --warmup 3 \
  './zig-out/bin/jake -n all' \
  'just --dry-run all'

# Benchmark with different optimization levels
hyperfine --warmup 3 \
  './zig-out/bin/jake-debug -l' \
  './zig-out/bin/jake-release -l' \
  './zig-out/bin/jake-small -l'
```

### Benchmark parsing speed

```sh
# Create a large Jakefile for stress testing
python3 -c "
for i in range(100):
    print(f'task task{i}:')
    print(f'    echo \"Running task {i}\"')
    print()
" > /tmp/large.jake

hyperfine --warmup 5 \
  './zig-out/bin/jake -f /tmp/large.jake -l'
```

### Export results

```sh
# JSON for programmatic analysis
hyperfine './zig-out/bin/jake -l' --export-json bench.json

# Markdown for documentation
hyperfine './zig-out/bin/jake -l' --export-markdown bench.md
```

## CPU Profiling with Samply

Samply generates flamegraphs showing where CPU time is spent.

### Install

```sh
brew install samply
```

### Profile jake

```sh
# Build with debug symbols (important for readable profiles)
zig build -Doptimize=ReleaseSafe

# Profile task listing
samply record ./zig-out/bin/jake -l

# Profile parsing a large file
samply record ./zig-out/bin/jake -f /tmp/large.jake -n all

# Profile with more samples (longer runs)
samply record --rate 10000 ./zig-out/bin/jake -l
```

Samply opens an interactive web UI showing:
- Flamegraph (which functions take time)
- Call tree
- Timeline view

### What to look for

- **Hot functions**: Functions taking >10% of time
- **Deep stacks**: Excessive recursion or abstraction
- **Allocation patterns**: Time spent in allocator functions

## Memory Profiling

### Using Zig's GeneralPurposeAllocator

Jake already uses GPA in debug builds with leak detection:

```sh
# Build debug version
zig build -Doptimize=Debug

# Run and check for leaks (reported on exit)
./zig-out/bin/jake -j4 -n all
```

If you see `error(gpa): memory address ... leaked`, there's a leak.

### Using macOS `leaks` tool

```sh
# Check for leaks after execution
leaks --atExit -- ./zig-out/bin/jake -l

# More verbose output
leaks --atExit --list -- ./zig-out/bin/jake -n all
```

### Using macOS `heap` tool

```sh
# Show heap statistics
heap ./zig-out/bin/jake -l

# Show all allocations by size
heap --addresses ./zig-out/bin/jake -l
```

## Stack Size Analysis

Zig can report stack usage per function:

```sh
# Build with stack reporting
zig build-exe src/main.zig -fstack-report 2>&1 | head -50

# Or via build.zig (add to exe definition):
# exe.stack_report = true;
```

This helps identify functions with large stack frames that might cause stack overflow on deeply recursive inputs.

## Compile Time Analysis

### Measure build times

```sh
# Time a clean build
rm -rf zig-out .zig-cache
time zig build

# Time incremental build
time zig build

# Compare optimization levels
time zig build -Doptimize=Debug
time zig build -Doptimize=ReleaseSafe
time zig build -Doptimize=ReleaseFast
time zig build -Doptimize=ReleaseSmall
```

### Binary size analysis

```sh
# Compare binary sizes
ls -lh zig-out/bin/jake*

# Detailed section sizes (requires bloaty or similar)
size zig-out/bin/jake

# On macOS, use otool
otool -l zig-out/bin/jake | grep -A2 LC_SEGMENT
```

## Thread Sanitizer

Detect data races in parallel execution:

```sh
# Build with thread sanitizer
zig build-exe src/main.zig -fsanitize-thread -o jake-tsan

# Run parallel workload
./jake-tsan -j4 all
```

## Valgrind (Linux only)

Valgrind doesn't work on macOS ARM, but on Linux:

```sh
# Build with valgrind client requests
zig build -Doptimize=Debug

# Memory check
valgrind --leak-check=full ./zig-out/bin/jake -l

# Cache profiling
valgrind --tool=cachegrind ./zig-out/bin/jake -l

# Call graph profiling
valgrind --tool=callgrind ./zig-out/bin/jake -l
kcachegrind callgrind.out.*
```

## macOS Instruments

For deep profiling, use Xcode Instruments:

```sh
# Open Instruments with jake
xcrun xctrace record --template 'Time Profiler' --launch -- ./zig-out/bin/jake -l

# Or open Instruments.app manually and attach to process
open -a Instruments
```

Templates to try:
- **Time Profiler**: CPU usage and call stacks
- **Allocations**: Memory allocation patterns
- **Leaks**: Memory leak detection
- **System Trace**: Syscalls and scheduling

## Practical Benchmarking Tasks

### 1. Startup time (important for CLI tools)

```sh
hyperfine --warmup 10 './zig-out/bin/jake --version'
```

### 2. Parse time vs file size

```sh
# Generate files of different sizes
for n in 10 50 100 500; do
  python3 -c "
for i in range($n):
    print(f'task t{i}:')
    print(f'    echo {i}')
" > /tmp/jake-$n.jake
done

# Benchmark each
hyperfine \
  './zig-out/bin/jake -f /tmp/jake-10.jake -l' \
  './zig-out/bin/jake -f /tmp/jake-50.jake -l' \
  './zig-out/bin/jake -f /tmp/jake-100.jake -l' \
  './zig-out/bin/jake -f /tmp/jake-500.jake -l'
```

### 3. Parallel execution scaling

```sh
# Benchmark different thread counts
hyperfine \
  './zig-out/bin/jake -j1 -n all' \
  './zig-out/bin/jake -j2 -n all' \
  './zig-out/bin/jake -j4 -n all' \
  './zig-out/bin/jake -j8 -n all'
```

### 4. Memory usage

```sh
# Peak memory during execution
/usr/bin/time -l ./zig-out/bin/jake -l 2>&1 | grep "maximum resident"
```

## Adding Benchmarks to CI

Example GitHub Actions step:

```yaml
- name: Benchmark
  run: |
    hyperfine --warmup 3 --export-json bench.json \
      './zig-out/bin/jake -l'
    
- name: Upload benchmark
  uses: actions/upload-artifact@v3
  with:
    name: benchmark
    path: bench.json
```

## Tips

1. **Always use warmup runs** (`--warmup 3`) to account for disk cache
2. **Build with symbols** for readable profiles (`-Doptimize=ReleaseSafe`)
3. **Profile realistic workloads** (actual Jakefiles, not synthetic)
4. **Compare against baseline** (previous version, or just/make)
5. **Check different hardware** (CI machines differ from dev machines)
