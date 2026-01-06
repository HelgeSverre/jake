#!/bin/bash
# Compare different spinner approaches

RESET="\033[0m"
ROSE="\033[38;2;232;121;153m"
GREEN="\033[32m"
GRAY="\033[90m"
CLEAR_LINE="\033[K"

echo "========================================"
echo "APPROACH A: Current (pause immediately)"
echo "========================================"
echo "Header shows, command runs, status shows"
echo ""
printf "${ROSE}→${RESET} test\n"
echo "Running tests..."
sleep 0.3
echo "Test 1: passed"
sleep 0.2
echo "Test 2: passed"
sleep 0.2
echo "All tests passed!"
printf "\n   ${GREEN}✓${RESET} test     ${GRAY}0.70s${RESET}\n"

sleep 1

echo ""
echo "========================================"
echo "APPROACH B: Spinner until output"
echo "========================================"
echo "Spinner animates until first output line"
echo ""
# Simulate spinner for 0.3s (command starts silently)
for i in {0..3}; do
    printf "\r   ${ROSE}⠋${RESET} test${CLEAR_LINE}"
    sleep 0.08
done
printf "\r${CLEAR_LINE}"
echo "Running tests..."
sleep 0.3
echo "Test 1: passed"
sleep 0.2
echo "Test 2: passed"
sleep 0.2
echo "All tests passed!"
printf "\n   ${GREEN}✓${RESET} test     ${GRAY}0.70s${RESET}\n"

sleep 1

echo ""
echo "========================================"
echo "APPROACH C: Command with NO output"
echo "========================================"
echo "What if command produces no output?"
echo ""
echo "--- Current approach (header only) ---"
printf "${ROSE}→${RESET} silent-task\n"
# silent command
sleep 0.5
printf "\n   ${GREEN}✓${RESET} silent-task     ${GRAY}0.50s${RESET}\n"

echo ""
echo "--- Spinner approach ---"
for i in {0..5}; do
    printf "\r   ${ROSE}⠋${RESET} silent-task${CLEAR_LINE}"
    sleep 0.08
done
printf "\r${CLEAR_LINE}"
# silent command ends
printf "\n   ${GREEN}✓${RESET} silent-task     ${GRAY}0.50s${RESET}\n"

echo ""
echo "========================================"
echo "Which looks better for your use case?"
echo "========================================"
