#!/bin/bash
# Option 1: Add separator lines before/after command output

GREEN="\033[38;2;34;197;94m"
MUTED="\033[38;5;245m"
ROSE="\033[38;2;227;117;210m"
RESET="\033[0m"

echo -e "=== OPTION 1: Separator lines ==="
echo -e ""

# Recipe header with arrow
echo -e "   ${ROSE}→${RESET} test"

# Separator before output
echo -e "   ${MUTED}───────────────────────────────${RESET}"

# Command output (at col 0)
echo -e "Running tests..."
echo -e "1/10 test.lexer...OK"
echo -e "2/10 test.parser...OK"
echo -e "3/10 test.executor...OK"
echo -e "All tests passed!"

# Separator after output
echo -e "   ${MUTED}───────────────────────────────${RESET}"

# Status line
echo -e "   ${GREEN}✓${RESET} test     ${MUTED}1.64s${RESET}"
echo -e ""
echo -e "   Successfully ran 1 task"
echo -e "   Total time: 1.64s"
