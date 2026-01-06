#!/bin/bash
# Option 5: Nx/Turborepo style - task name prefix on output block

GREEN="\033[38;2;34;197;94m"
MUTED="\033[38;5;245m"
ROSE="\033[38;2;227;117;210m"
CYAN="\033[38;5;80m"
RESET="\033[0m"

echo -e "=== OPTION 5: Nx/Turborepo style ==="
echo -e ""

# Task block header
echo -e "${CYAN}test${RESET}:"

# Command output (indented under task)
echo -e "  Running tests..."
echo -e "  1/10 test.lexer...OK"
echo -e "  2/10 test.parser...OK"
echo -e "  3/10 test.executor...OK"
echo -e "  All tests passed!"
echo -e ""

# Status line
echo -e "   ${GREEN}✓${RESET} test     ${MUTED}1.64s${RESET}"
echo -e ""
echo -e "   Successfully ran 1 task"
echo -e "   Total time: 1.64s"
echo -e ""
echo -e "NOTE: Requires capturing output"
