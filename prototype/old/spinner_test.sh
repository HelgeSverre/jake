#!/bin/bash
# Test different spinner approaches to find the cleanest solution

# ANSI codes
RESET="\033[0m"
ROSE="\033[38;2;232;121;153m"
GREEN="\033[32m"
GRAY="\033[90m"
CLEAR_LINE="\033[K"

SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# Simulated command output
simulate_output() {
    echo "Running tests..."
    sleep 0.3
    echo "Test 1: passed"
    sleep 0.2
    echo "Test 2: passed"
    sleep 0.2
    echo "All tests passed!"
}

echo "======================================"
echo "APPROACH 1: Spinner runs ABOVE output"
echo "======================================"
echo "Spinner shows briefly, then moves up and output appears below"
echo ""

# Show spinner for 0.5s
for i in {0..5}; do
    printf "\r   ${ROSE}${SPINNER_FRAMES[$((i % 10))]}${RESET} test${CLEAR_LINE}"
    sleep 0.08
done

# Move to new line, output appears below
echo ""
simulate_output

# Final status
printf "\n   ${GREEN}✓${RESET} test     ${GRAY}0.70s${RESET}\n"

echo ""
echo "======================================"
echo "APPROACH 2: Pause during output"
echo "======================================"
echo "Spinner pauses (clears), output flows, then status appears"
echo ""

# Show spinner briefly
for i in {0..3}; do
    printf "\r   ${ROSE}${SPINNER_FRAMES[$((i % 10))]}${RESET} test${CLEAR_LINE}"
    sleep 0.08
done

# Clear spinner line before output
printf "\r${CLEAR_LINE}"

# Output flows normally
simulate_output

# Final status (with blank line separator)
printf "\n   ${GREEN}✓${RESET} test     ${GRAY}0.70s${RESET}\n"

echo ""
echo "======================================"
echo "APPROACH 3: Spinner BELOW output"
echo "======================================"
echo "Output appears, spinner updates on last line"
echo ""

# This requires saving/restoring cursor position
# Output first
echo "Running tests..."
sleep 0.1

# Show spinner below
for i in {0..3}; do
    printf "\r   ${ROSE}${SPINNER_FRAMES[$((i % 10))]}${RESET} test${CLEAR_LINE}"
    sleep 0.08
done

# More output (need to handle this carefully)
printf "\r${CLEAR_LINE}"
echo "Test 1: passed"
for i in {4..7}; do
    printf "\r   ${ROSE}${SPINNER_FRAMES[$((i % 10))]}${RESET} test${CLEAR_LINE}"
    sleep 0.08
done

printf "\r${CLEAR_LINE}"
echo "Test 2: passed"
echo "All tests passed!"

printf "\n   ${GREEN}✓${RESET} test     ${GRAY}0.70s${RESET}\n"

echo ""
echo "======================================"
echo "APPROACH 4: Header + spinner on same line"
echo "======================================"
echo "→ test [spinner] then output below"
echo ""

# Header with spinner
for i in {0..5}; do
    printf "\r${ROSE}→${RESET} test ${ROSE}${SPINNER_FRAMES[$((i % 10))]}${RESET}${CLEAR_LINE}"
    sleep 0.08
done

# Clear and output below
printf "\r${ROSE}→${RESET} test${CLEAR_LINE}\n"
simulate_output

printf "\n   ${GREEN}✓${RESET} test     ${GRAY}0.70s${RESET}\n"

echo ""
echo "======================================"
echo "APPROACH 5: Spinner only when NO output"
echo "======================================"
echo "Detect output, switch modes dynamically"
echo ""

echo "(This would require piping output and detecting it)"
echo "Spinner shows if command is quiet, hides if output detected"

echo ""
echo "======================================"
echo "CURRENT IMPLEMENTATION (blank lines v2)"
echo "======================================"
echo ""

# What we have now
printf "${ROSE}→${RESET} test\n"
simulate_output
printf "\n   ${GREEN}✓${RESET} test     ${GRAY}0.70s${RESET}\n"
