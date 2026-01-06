# Test Jakefile for spinner/output demos

# Quick command - minimal output
task quick:
    echo "Quick task done"

# Multiple lines of output
task verbose:
    echo "Line 1: Starting..."
    echo "Line 2: Processing..."
    echo "Line 3: More work..."
    echo "Line 4: Almost done..."
    echo "Line 5: Complete!"

# Slow with streaming output (simulates real build tool)
task slow-stream:
    echo "Starting slow task..."
    sleep 0.1
    echo "Step 1 complete"
    sleep 0.1
    echo "Step 2 complete"
    sleep 0.1
    echo "Step 3 complete"
    sleep 0.1
    echo "All done!"

# Simulates a tool that does its own spinner/progress
task animated-tool:
    echo "Running animated tool..."
    for i in 1 2 3 4 5; do printf "\rProgress: %d/5" $i; sleep 0.15; done
    echo ""
    echo "Animated tool complete"

# stderr output
task with-stderr:
    echo "Normal output"
    echo "Error output" >&2
    echo "More normal output"

# Mixed stdout/stderr interleaved
task mixed-output:
    echo "stdout 1"
    echo "stderr 1" >&2
    echo "stdout 2"
    echo "stderr 2" >&2
    echo "stdout 3"

# Rapid fire output
task rapid:
    for i in $(seq 1 20); do echo "Line $i"; done

# Nested jake call
task nested:
    echo "Outer task starting..."
    ./zig-out/bin/jake -f prototypes/test.jake quick
    echo "Outer task complete"
