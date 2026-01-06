#!/bin/bash
# Current output format - shows the alignment issue

GREEN="\033[38;2;34;197;94m"
MUTED="\033[38;5;245m"
RESET="\033[0m"

echo -e "=== CURRENT FORMAT (alignment issue) ==="
echo -e ""

# Command output starts at column 0
echo -e "Running tests..."
echo -e "1/10 test.lexer...OK"
echo -e "2/10 test.parser...OK"
echo -e "3/10 test.executor...OK"
echo -e "All tests passed!"

# But jake status is indented 3 spaces
echo -e "   ${GREEN}✓${RESET} test     ${MUTED}1.64s${RESET}"
echo -e ""
echo -e "   Successfully ran 1 task"
echo -e "   Total time: 1.64s"
echo -e ""
echo -e "Notice: command output at col 0, jake output at col 3"
