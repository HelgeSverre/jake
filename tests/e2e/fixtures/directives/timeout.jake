# Test @timeout directive with various formats

@timeout 30s
task test-seconds:
    echo "Task with 30s timeout"

@timeout 5m
task test-minutes:
    echo "Task with 5m timeout"

@timeout 2h
task test-hours:
    echo "Task with 2h timeout"

# Fast task that completes well within timeout
@timeout 10s
task quick:
    echo "Quick task"

# Task without timeout (default)
task no-timeout:
    echo "No timeout set"

# Multi-command body whose deadline lands mid-loop. The sleep must be killed by
# the watchdog, not left running once jake exits.
@timeout 2s
task fires:
    echo "BEFORE SLEEP"
    sleep 27691
    echo "UNREACHABLE"
