#!/bin/bash
# Test using scroll regions to keep spinner fixed at top

# ANSI codes
RESET="\033[0m"
ROSE="\033[38;2;232;121;153m"
GREEN="\033[32m"
GRAY="\033[90m"
SAVE_CURSOR="\033[s"
RESTORE_CURSOR="\033[u"
MOVE_TO_TOP="\033[1;1H"
CLEAR_LINE="\033[K"

SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

echo "Testing scroll region approach..."
echo ""

# Get terminal height
LINES=$(tput lines)

# Reserve first line for spinner, scroll region is lines 2 to bottom
# Set scroll region: \033[top;bottom r
printf "\033[2;${LINES}r"

# Move cursor to line 2 for output
printf "\033[2;1H"

# Function to update spinner (runs in background)
update_spinner() {
    local name="$1"
    local i=0
    while true; do
        # Save cursor, move to line 1, draw spinner, restore cursor
        printf "${SAVE_CURSOR}${MOVE_TO_TOP}   ${ROSE}${SPINNER_FRAMES[$((i % 10))]}${RESET} ${name}${CLEAR_LINE}${RESTORE_CURSOR}"
        ((i++))
        sleep 0.08
    done
}

# Start spinner in background
update_spinner "test" &
SPINNER_PID=$!

# Simulate command output (appears in scroll region)
sleep 0.3
echo "Running tests..."
sleep 0.3
echo "Test 1: passed"
sleep 0.3
echo "Test 2: passed"
sleep 0.3
echo "All tests passed!"
sleep 0.2

# Stop spinner
kill $SPINNER_PID 2>/dev/null
wait $SPINNER_PID 2>/dev/null

# Reset scroll region to full terminal
printf "\033[r"

# Clear spinner line and show final status
printf "${MOVE_TO_TOP}${CLEAR_LINE}"
printf "   ${GREEN}✓${RESET} test     ${GRAY}1.20s${RESET}\n"

# Move cursor to end
printf "\033[${LINES};1H"
