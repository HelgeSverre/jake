#!/bin/bash
# Option 3: Buffer all output, print after command completes
# Like parallel mode - spinner animates entire time, output shown after

echo "=== OPTION 3: Buffer Output, Print After ==="
echo ""
echo "Spinner animates continuously, output shown after command finishes"
echo ""

SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
ROSE="\033[38;2;227;117;210m"
GREEN="\033[38;2;34;197;94m"
MUTED="\033[38;5;245m"
RESET="\033[0m"

spinner_pid=""

start_spinner() {
    (
        i=0
        while true; do
            frame="${SPINNER_FRAMES[$((i % 10))]}"
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
        printf "\r\033[K" >&2
    fi
}

# Run command and buffer all output
run_command_buffered() {
    local cmd="$1"

    # Capture all output to a variable
    local output
    output=$(eval "$cmd" 2>&1)
    local exit_code=$?

    # Return the buffered output
    echo "$output"
    return $exit_code
}

# Demo
start_spinner

# Command runs while spinner animates (user sees only spinner)
buffered_output=$(run_command_buffered 'echo "Running tests..."; sleep 0.15; echo "Test 1: PASS"; sleep 0.1; echo "Test 2: PASS"; sleep 0.1; echo "All 2 tests passed."')

stop_spinner

# Print completion status first
echo "   ${GREEN}✓${RESET} test     ${MUTED}0.35s${RESET}"

# Then print buffered output
echo "$buffered_output"
echo ""

echo "PROS: Clean spinner animation, no interleaving"
echo "CONS: No real-time output - user waits until command finishes"
echo "      Bad for long-running commands with progress output"
