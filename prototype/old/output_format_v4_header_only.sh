#!/bin/bash
# Option 4: Show recipe name header, then output, then status
# Similar to how npm/yarn show package names

GREEN="\033[38;2;34;197;94m"
MUTED="\033[38;5;245m"
ROSE="\033[38;2;227;117;210m"
RESET="\033[0m"

echo -e "=== OPTION 4: Header before output ==="
echo -e ""

# Recipe header on its own line
echo -e "${ROSE}→${RESET} ${MUTED}test${RESET}"

# Command output (no indentation)
echo -e "Running tests..."
echo -e "1/10 test.lexer...OK"
echo -e "2/10 test.parser...OK"
echo -e "3/10 test.executor...OK"
echo -e "All tests passed!"

# Status line (back to jake format)
echo -e "   ${GREEN}✓${RESET} test     ${MUTED}1.64s${RESET}"
echo -e ""
echo -e "   Successfully ran 1 task"
echo -e "   Total time: 1.64s"
