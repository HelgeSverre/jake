#!/bin/bash
# Option 2: Just blank lines for visual separation

GREEN="\033[38;2;34;197;94m"
MUTED="\033[38;5;245m"
ROSE="\033[38;2;227;117;210m"
RESET="\033[0m"

echo -e "=== OPTION 2: Blank lines for separation ==="
echo -e ""

# Recipe header
echo -e "   ${ROSE}→${RESET} test"
echo -e ""

# Command output
echo -e "Running tests..."
echo -e "1/10 test.lexer...OK"
echo -e "2/10 test.parser...OK"
echo -e "3/10 test.executor...OK"
echo -e "All tests passed!"
echo -e ""

# Status line
echo -e "   ${GREEN}✓${RESET} test     ${MUTED}1.64s${RESET}"
echo -e ""
echo -e "   Successfully ran 1 task"
echo -e "   Total time: 1.64s"
