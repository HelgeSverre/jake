#!/bin/bash
# Option 7: Box style - clear visual boundary around output

GREEN="\033[38;2;34;197;94m"
MUTED="\033[38;5;245m"
ROSE="\033[38;2;227;117;210m"
RESET="\033[0m"

echo -e "=== OPTION 7: Box style ==="
echo -e ""

# Recipe header with top border
echo -e "   ${MUTED}┌─${RESET} ${ROSE}test${RESET}"
echo -e "   ${MUTED}│${RESET}"

# Command output
echo -e "Running tests..."
echo -e "1/10 test.lexer...OK"
echo -e "2/10 test.parser...OK"
echo -e "3/10 test.executor...OK"
echo -e "All tests passed!"

# Bottom border with status
echo -e "   ${MUTED}│${RESET}"
echo -e "   ${MUTED}└─${RESET} ${GREEN}✓${RESET} ${MUTED}1.64s${RESET}"
echo -e ""
echo -e "   Successfully ran 1 task"
echo -e "   Total time: 1.64s"
