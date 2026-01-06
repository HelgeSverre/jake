#!/bin/bash
# Option 6: Minimal - just output then status (no header during execution)
# The status line at the end tells you what ran

GREEN="\033[38;2;34;197;94m"
MUTED="\033[38;5;245m"
RESET="\033[0m"

echo -e "=== OPTION 6: Minimal (output then status) ==="
echo -e ""

# Just command output, no header
echo -e "Running tests..."
echo -e "1/10 test.lexer...OK"
echo -e "2/10 test.parser...OK"
echo -e "3/10 test.executor...OK"
echo -e "All tests passed!"

# Status line tells you what ran
echo -e ""
echo -e "   ${GREEN}✓${RESET} test     ${MUTED}1.64s${RESET}"
echo -e ""
echo -e "   Successfully ran 1 task"
echo -e "   Total time: 1.64s"
