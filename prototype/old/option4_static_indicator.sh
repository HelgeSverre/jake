#!/bin/bash
# Option 4: No spinner during commands - just static indicator
# Simplest approach - no animation at all during execution

echo "=== OPTION 4: Static Indicator (No Animation) ==="
echo ""
echo "Shows static indicator during execution, no spinner animation"
echo ""

ROSE="\033[38;2;227;117;210m"
GREEN="\033[38;2;34;197;94m"
MUTED="\033[38;5;245m"
RESET="\033[0m"

# Static indicator (arrow or dot)
RUNNING="→"

# Show static "running" indicator
show_running() {
    printf "   ${ROSE}${RUNNING}${RESET} test\n" >&2
}

# Run command with static indicator
run_command_static() {
    local cmd="$1"

    # Show static indicator
    show_running

    # Run command directly (output goes to terminal)
    eval "$cmd"
}

# Demo
run_command_static 'echo "Running tests..."; sleep 0.15; echo "Test 1: PASS"; sleep 0.1; echo "Test 2: PASS"; sleep 0.1; echo "All 2 tests passed."'

echo "   ${GREEN}✓${RESET} test     ${MUTED}0.35s${RESET}"
echo ""

echo "PROS: Simplest implementation, no race conditions, clean output"
echo "CONS: No visual feedback that something is running"
echo "      Less engaging than animated spinner"
