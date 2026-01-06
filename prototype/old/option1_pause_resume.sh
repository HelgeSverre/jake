#!/bin/bash
# Option 1: Pause spinner during command execution
# Simple approach - spinner stops while command runs, resumes after

echo "=== OPTION 1: Pause/Resume Spinner ==="
echo ""
echo "Spinner pauses during command, resumes between commands"
echo ""

SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
ROSE="\033[38;2;227;117;210m"
GREEN="\033[38;2;34;197;94m"
MUTED="\033[38;5;245m"
RESET="\033[0m"

spinner_pid=""
spinner_paused=false

start_spinner() {
    (
        i=0
        while true; do
            # Check if pause file exists (simple IPC)
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
    printf "\r\033[K" >&2  # Clear the spinner line
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

# Simulate running a command
run_command() {
    local cmd="$1"
    pause_spinner
    eval "$cmd"
    resume_spinner
}

# Demo
start_spinner
sleep 0.3  # Let spinner animate a bit

run_command 'echo "Running tests..."; sleep 0.15; echo "Test 1: PASS"; sleep 0.1; echo "Test 2: PASS"; sleep 0.1; echo "All 2 tests passed."'

sleep 0.3  # Let spinner animate after command
stop_spinner

echo ""
echo "   ${GREEN}✓${RESET} test     ${MUTED}0.65s${RESET}"
echo ""
echo "PROS: Simple, clean output, real-time streaming"
echo "CONS: Spinner disappears during command execution"
