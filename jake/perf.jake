# Performance & Profiling recipes for jake
#
# This module provides benchmarking, profiling, and fuzzing tasks.
# Import with: @import "jake/perf.jake" as perf

# ============================================================================
# Benchmarking
# ============================================================================

@desc "Run internal zBench benchmarks"
@group perf
task bench-internal:
    @needs zig
    @pre echo "Running internal benchmarks..."
    zig build bench -Doptimize=ReleaseFast
    @post echo "Benchmarks complete!"

@desc "Build benchmark binary without running"
@group perf
task bench-build:
    @needs zig
    zig build bench-build -Doptimize=ReleaseFast
    echo "Benchmark binary: zig-out/bin/jake-bench"

@desc "Run benchmarks with JSON output for CI"
@group perf
task bench-json:
    @needs zig
    zig build bench-build -Doptimize=ReleaseFast
    ./zig-out/bin/jake-bench 2>&1 | tee benchmark-results.txt

# ============================================================================
# Tracy Profiling
# ============================================================================

@desc "Build jake with Tracy instrumentation"
@group perf
task tracy-build:
    @needs zig
    zig build -Doptimize=ReleaseFast -Dtracy=true

@desc "Run jake with Tracy profiling"
@group perf
@needs tracy-capture "Install Tracy: brew install tracy" -> _install-tracy
task tracy: [tracy-build]
    @pre echo "Starting Tracy capture..."
    tracy-capture -o trace.tracy &
    sleep 1
    ./zig-out/bin/jake -l
    sleep 1
    killall tracy-capture 2>/dev/null || true
    @post echo "Trace saved to: trace.tracy"
    @post echo "Open with: tracy trace.tracy"

# Private helper to install Tracy profiler
@quiet
task _install-tracy:
    brew install tracy

# ============================================================================
# Fuzzing
# ============================================================================

@desc "Run coverage-guided fuzz tests"
@group perf
task fuzz:
    @needs zig
    @pre echo "Running coverage-guided fuzz tests..."
    zig build fuzz --fuzz
    @post echo "Fuzzing complete!"

# ============================================================================
# Profiling & Memory Analysis
# ============================================================================

@desc "Profile with samply (flamegraph)"
@group perf
task profile:
    @needs samply "Install samply: brew install samply (macOS) or cargo install samply"
    @needs zig
    zig build -Doptimize=ReleaseFast
    @pre echo "Starting samply profiler..."
    samply record ./zig-out/bin/jake -l

@desc "Memory leak check (macOS)"
@group perf
@only-os macos
task leaks:
    @needs leaks
    @needs zig
    zig build -Doptimize=ReleaseSafe
    @pre echo "Running leak check..."
    leaks --atExit -- ./zig-out/bin/jake -l

@desc "Memory usage analysis"
@group perf
task memory:
    @needs zig
    zig build -Doptimize=ReleaseSafe
    @pre echo "Measuring peak memory usage..."
    /usr/bin/time -l ./zig-out/bin/jake -l 2>&1 | grep -E "(maximum resident|peak memory)"

@desc "Profile with Instruments (macOS)"
@group perf
@only-os macos
task instruments:
    @needs xctrace "Install Xcode Command Line Tools"
    @needs zig
    zig build -Doptimize=ReleaseSafe
    @pre echo "Recording with Instruments..."
    xctrace record --template 'Time Profiler' --launch -- ./zig-out/bin/jake -l
    @post echo "Open the .trace file with Instruments to view results"

# ============================================================================
# Regression Testing
# ============================================================================

@desc "Run performance regression suite"
@group perf
task regression: [bench-json]
    @if exists(.benchmark-baseline.txt)
        echo "Comparing against baseline..."
        diff .benchmark-baseline.txt benchmark-results.txt || echo "Differences detected"
    @else
        echo "No baseline found. Creating baseline..."
        cp benchmark-results.txt .benchmark-baseline.txt
        echo "Baseline saved to .benchmark-baseline.txt"
    @end

@desc "Update performance baseline"
@group perf
task baseline: [bench-json]
    cp benchmark-results.txt .benchmark-baseline.txt
    echo "Baseline updated!"

# ============================================================================
# All-in-one
# ============================================================================

@desc "Run full performance suite (bench + fuzz)"
@group perf
task all: [bench-internal, fuzz]
    echo "Performance suite complete!"
    echo "Run 'jake perf.profile' for profiling"
