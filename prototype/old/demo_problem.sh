#!/bin/bash
# Demo: The PROBLEM - spinner racing with command output
# This shows what's currently happening - interleaved/corrupted output

echo "=== PROBLEM DEMO: Spinner + Command Output Race ==="
echo ""
echo "Watch how the spinner overwrites command output..."
echo ""

SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
ROSE="\033[38;2;227;117;210m"
RESET="\033[0m"

# Start spinner in background
spinner_pid=""
start_spinner() {
    (
        i=0
        while true; do
            frame="${SPINNER_FRAMES[$((i % 10))]}"
            # This is what Jake does: \r + spinner + clear-to-EOL
            printf "\r   ${ROSE}${frame}${RESET} test\033[K" >&2
            sleep 0.08
            ((i++))
        done
    ) &
    spinner_pid=$!
}

stop_spinner() {
    if [ -n "$spinner_pid" ]; then
        kill $spinner_pid 2>/dev/null
        wait $spinner_pid 2>/dev/null
        printf "\r\033[K" >&2  # Clear spinner line
    fi
}

# Simulate a command that produces output
simulate_command() {
    echo "Running tests..."
    sleep 0.15
    echo "Test 1: PASS"
    sleep 0.1
    echo "Test 2: PASS"
    sleep 0.1
    echo "All 2 tests passed."
}

# Run the demo
start_spinner
simulate_command
stop_spinner

echo ""
echo "   ✓ test     0.35s"
echo ""
echo "Notice how spinner frames appear mixed with the output!"
