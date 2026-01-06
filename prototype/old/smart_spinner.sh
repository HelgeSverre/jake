#!/bin/bash
# Smart spinner that pauses when output is detected
# Uses a FIFO to coordinate between spinner and output

# ANSI codes
RESET="\033[0m"
ROSE="\033[38;2;232;121;153m"
GREEN="\033[32m"
GRAY="\033[90m"
CLEAR_LINE="\033[K"

SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

echo "===== SMART SPINNER TEST ====="
echo "Spinner runs until output is detected, then pauses"
echo ""

# Create temp file for output detection
OUTPUT_FLAG=$(mktemp)
rm -f "$OUTPUT_FLAG"

# Background spinner that checks for output flag
spinner_with_pause() {
    local name="$1"
    local i=0
    local spinner_shown=false

    while true; do
        # Check if we should stop
        if [[ -f "${OUTPUT_FLAG}.done" ]]; then
            # Clear spinner if it was shown
            if $spinner_shown; then
                printf "\r${CLEAR_LINE}"
            fi
            break
        fi

        # Check if output has started (flag file exists)
        if [[ -f "$OUTPUT_FLAG" ]]; then
            # Output happening - don't show spinner
            if $spinner_shown; then
                # Spinner was showing, need to clear it
                # But we can't easily do this since output may have already printed
                spinner_shown=false
            fi
            sleep 0.05
            continue
        fi

        # No output yet - show spinner
        printf "\r   ${ROSE}${SPINNER_FRAMES[$((i % 10))]}${RESET} ${name}${CLEAR_LINE}"
        spinner_shown=true
        ((i++))
        sleep 0.08
    done
}

# Run command and mark when output starts
run_with_output_detection() {
    local cmd="$1"

    # Use a wrapper that touches the flag on first output
    (
        first_line=true
        while IFS= read -r line; do
            if $first_line; then
                # Clear spinner line before first output
                printf "\r${CLEAR_LINE}"
                touch "$OUTPUT_FLAG"
                first_line=false
            fi
            echo "$line"
        done
    ) < <(eval "$cmd" 2>&1)
}

# Start spinner in background
spinner_with_pause "test" &
SPINNER_PID=$!

# Give spinner a moment to show
sleep 0.3

# Run command with output detection
run_with_output_detection 'echo "Running tests..."; sleep 0.2; echo "Test 1: passed"; sleep 0.2; echo "Test 2: passed"; sleep 0.2; echo "All tests passed!"'

# Signal spinner to stop
touch "${OUTPUT_FLAG}.done"
wait $SPINNER_PID 2>/dev/null

# Clean up
rm -f "$OUTPUT_FLAG" "${OUTPUT_FLAG}.done"

# Final status
printf "\n   ${GREEN}✓${RESET} test     ${GRAY}0.90s${RESET}\n"

echo ""
echo "===== END TEST ====="
