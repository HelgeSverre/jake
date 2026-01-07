#!/bin/bash
# Option 2: Detect output and react (pipe + poll)
# Spinner visible between output bursts

echo "=== OPTION 2: Detect Output & React ==="
echo ""
echo "Spinner pauses when output detected, resumes after each chunk"
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
            if [ ! -f /tmp/spinner_paused ]; then
                frame="${SPINNER_FRAMES[$((i % 10))]}"
                printf "\r   ${ROSE}${frame}${RESET} test\033[K" >&2
            fi
            sleep 0.08
            ((i++))
        done
    ) &
    spinner_pid=$!
    rm -f /tmp/spinner_paused
}

pause_spinner() {
    touch /tmp/spinner_paused
    printf "\r\033[K" >&2
}

resume_spinner() {
    rm -f /tmp/spinner_paused
}

stop_spinner() {
    if [ -n "$spinner_pid" ]; then
        kill $spinner_pid 2>/dev/null
        wait $spinner_pid 2>/dev/null
        printf "\r\033[K" >&2
    fi
    rm -f /tmp/spinner_paused
}

# Run command with output detection
# Pipes output, pauses spinner when data arrives, prints, resumes
run_command_with_detection() {
    local cmd="$1"

    # Create a named pipe for output
    local pipe="/tmp/cmd_output_$$"
    mkfifo "$pipe"

    # Run command, output to pipe
    eval "$cmd" > "$pipe" 2>&1 &
    local cmd_pid=$!

    # Read from pipe, pause/print/resume for each line
    while IFS= read -r line; do
        pause_spinner
        echo "$line"
        sleep 0.05  # Small delay to let user see output
        resume_spinner
        sleep 0.15  # Let spinner show between lines
    done < "$pipe"

    wait $cmd_pid
    rm -f "$pipe"
}

# Demo
start_spinner
sleep 0.3

run_command_with_detection 'echo "Running tests..."; sleep 0.1; echo "Test 1: PASS"; sleep 0.1; echo "Test 2: PASS"; sleep 0.1; echo "All 2 tests passed."'

sleep 0.3
stop_spinner

echo ""
echo "   ${GREEN}✓${RESET} test     ${MUTED}1.20s${RESET}"
echo ""
echo "PROS: Spinner visible between output, real-time feel"
echo "CONS: More complex, slight latency, potential buffering issues"
