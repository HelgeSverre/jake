#!/bin/bash
# Prototype: Group/Recipe color differentiation options
# Run: ./prototype/output.sh

# Reset
R="\x1b[0m"

# Colors
JAKE_ROSE="\x1b[38;2;244;63;94m"      # #f43f5e
ORANGE="\x1b[38;2;249;115;22m"        # #f97316 (Tailwind Orange 500)
MUTED_GRAY="\x1b[38;2;113;113;122m"   # #71717a
BOLD="\x1b[1m"

echo ""
echo -e "${BOLD}=== Option A: Orange for groups ===${R}"
echo ""
echo -e "${BOLD}Available recipes:${R}"
echo ""
echo -e "${ORANGE}ai:${R}"
echo -e "  ${JAKE_ROSE}ai.validate-docs${R} [task]  ${MUTED_GRAY}# AI validates README, CHANGELOG, TODO against codebase${R}"
echo -e "  ${JAKE_ROSE}ai.suggest-doc-updates${R} [task]  ${MUTED_GRAY}# AI suggests documentation updates${R}"
echo ""
echo -e "${ORANGE}dev:${R}"
echo -e "  ${JAKE_ROSE}build${R} [task]  ${MUTED_GRAY}# Build the project${R}"
echo -e "  ${JAKE_ROSE}test${R} [task]  ${MUTED_GRAY}# Run all tests${R}"
echo -e "  ${JAKE_ROSE}lint${R} [task]  ${MUTED_GRAY}# Check code formatting${R}"

echo ""
echo ""
echo -e "${BOLD}=== Option B: Dim recipes (muted gray) ===${R}"
echo ""
echo -e "${BOLD}Available recipes:${R}"
echo ""
echo -e "${JAKE_ROSE}ai:${R}"
echo -e "  ${MUTED_GRAY}ai.validate-docs${R} [task]  ${MUTED_GRAY}# AI validates README, CHANGELOG, TODO against codebase${R}"
echo -e "  ${MUTED_GRAY}ai.suggest-doc-updates${R} [task]  ${MUTED_GRAY}# AI suggests documentation updates${R}"
echo ""
echo -e "${JAKE_ROSE}dev:${R}"
echo -e "  ${MUTED_GRAY}build${R} [task]  ${MUTED_GRAY}# Build the project${R}"
echo -e "  ${MUTED_GRAY}test${R} [task]  ${MUTED_GRAY}# Run all tests${R}"
echo -e "  ${MUTED_GRAY}lint${R} [task]  ${MUTED_GRAY}# Check code formatting${R}"

echo ""
echo ""
echo -e "${BOLD}=== Option C: Bold groups only ===${R}"
echo ""
echo -e "${BOLD}Available recipes:${R}"
echo ""
echo -e "${BOLD}${JAKE_ROSE}ai:${R}"
echo -e "  ${JAKE_ROSE}ai.validate-docs${R} [task]  ${MUTED_GRAY}# AI validates README, CHANGELOG, TODO against codebase${R}"
echo -e "  ${JAKE_ROSE}ai.suggest-doc-updates${R} [task]  ${MUTED_GRAY}# AI suggests documentation updates${R}"
echo ""
echo -e "${BOLD}${JAKE_ROSE}dev:${R}"
echo -e "  ${JAKE_ROSE}build${R} [task]  ${MUTED_GRAY}# Build the project${R}"
echo -e "  ${JAKE_ROSE}test${R} [task]  ${MUTED_GRAY}# Run all tests${R}"
echo -e "  ${JAKE_ROSE}lint${R} [task]  ${MUTED_GRAY}# Check code formatting${R}"

echo ""
