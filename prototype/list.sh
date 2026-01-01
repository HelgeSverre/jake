#!/bin/bash
# Jake List Output Variations
# Run: bash prototype/list.sh

# ============================================================================
# COLORS
# ============================================================================

R="\x1b[0m"
BOLD="\x1b[1m"
DIM="\x1b[2m"

ROSE="\x1b[38;2;244;63;94m"
GREEN="\x1b[38;2;34;197;94m"
BLUE="\x1b[38;2;96;165;250m"
MUTED="\x1b[38;2;113;113;122m"
CYAN="\x1b[38;2;6;182;212m"

# ============================================================================
# HELPERS
# ============================================================================

divider() {
    echo ""
    echo ""
    echo -e "${CYAN}$(printf '%180s' | tr ' ' '─')${R}"
    echo ""
    echo ""
}

section() {
    echo -e "${BOLD}$1${R}"
    echo ""
}

prompt() {
    echo -e " ${MUTED}prototype [main] :${R} $1"
}

# ============================================================================
# DESIGN INSIGHTS FROM EXPERTS
# ============================================================================
#
# UI/UX Designer:
#   - Compact hierarchy is best for most cases
#   - Groups as headers, recipes indented
#   - Ungrouped recipes at the end
#   - Don't show [task]/[file] for every recipe
#
# UX Semantics:
#   - Keep "groupname:" style with color
#   - Use "private:" for hidden section (not "hidden")
#   - Keep "# description" format - familiar to Make/Just users
#   - Type badges are noise (only show [file] if ambiguous)
#
# Linus (Good Taste):
#   - Remove type badges entirely - implementation detail leaked to UI
#   - A recipe is a recipe. The name tells you what you need.
#   - The minimal approach is best
#   - "dist/app.js" is obviously a file - you don't need [file]
#
# ============================================================================

echo ""
section "JAKE LIST OUTPUT VARIATIONS"
echo -e "${MUTED}Brainstorming the best list format${R}"

divider

# ============================================================================
# VARIATION A: Minimal with Branding
# ============================================================================

section "VARIATION A: Minimal with Branding"
echo -e "${MUTED}Clean, focused, no noise${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "   ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e " ${BOLD}${ROSE}test${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# VARIATION B: Colon Groups (Current Style + Branding)
# ============================================================================

section "VARIATION B: Colon Groups (Current Style + Branding)"
echo -e "${MUTED}Groups with colon suffix, like current implementation${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${ROSE}build:${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "   ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e " ${ROSE}test:${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# VARIATION C: Bracketed Groups
# ============================================================================

section "VARIATION C: Bracketed Groups"
echo -e "${MUTED}Better for NO_COLOR mode, clearer structure${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${MUTED}[${R}${ROSE}build${R}${MUTED}]${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "   ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e " ${MUTED}[${R}${ROSE}test${R}${MUTED}]${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# VARIATION D: Ultra Minimal (Names Only)
# ============================================================================

section "VARIATION D: Ultra Minimal (Names Only)"
echo -e "${MUTED}Maximum density, descriptions via jake -s${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}  ${ROSE}build${R}  ${ROSE}clean${R}  ${ROSE}dist/app.js${R}"
echo -e " ${BOLD}${ROSE}test${R}   ${ROSE}test${R}  ${ROSE}test-unit${R}  ${ROSE}bench${R}"
echo ""
echo -e " ${ROSE}deploy${R}  ${ROSE}ci${R}  ${ROSE}fmt${R}  ${ROSE}lint${R}"

divider

# ============================================================================
# VARIATION E: Two-Line Branding
# ============================================================================

section "VARIATION E: Two-Line Branding"
echo -e "${MUTED}Full branding like --help header${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo -e " ${MUTED}The best of Make and Just, combined.${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo ""
echo -e " ${BOLD}${ROSE}test${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"

divider

# ============================================================================
# VARIATION F: Muted Groups, Bright Recipes
# ============================================================================

section "VARIATION F: Muted Groups, Bright Recipes"
echo -e "${MUTED}Groups fade into background, recipes pop${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${MUTED}build${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "   ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e " ${MUTED}test${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# VARIATION G: Subtle Separator
# ============================================================================

section "VARIATION G: Subtle Separator Lines"
echo -e "${MUTED}Horizontal rules between groups${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${MUTED}─── build ───${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo ""
echo -e " ${MUTED}─── test ───${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# VARIATION H: Comment-Style Descriptions
# ============================================================================

section "VARIATION H: Comment-Style Descriptions"
echo -e "${MUTED}# prefix for descriptions (like Justfile)${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}# Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}# Remove build artifacts${R}"
echo -e "   ${ROSE}dist/app.js${R}  ${MUTED}# Bundle JavaScript${R}"
echo ""
echo -e " ${BOLD}${ROSE}test${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}# Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}# Run unit tests only${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}# Deploy to production${R}"
echo -e " ${ROSE}ci${R}             ${MUTED}# Run CI pipeline${R}"

divider

# ============================================================================
# VARIATION I: No Header, Pure List
# ============================================================================

section "VARIATION I: No Header, Pure List"
echo -e "${MUTED}Branding only, no 'Available recipes'${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo ""
echo -e " ${BOLD}${ROSE}test${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# VARIATION J: With Recipe Count
# ============================================================================

section "VARIATION J: With Recipe Count Footer"
echo -e "${MUTED}Summary at bottom for large Jakefiles${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "   ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e " ${BOLD}${ROSE}test${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"
echo ""
echo -e " ${MUTED}8 recipes${R}"

divider

# ============================================================================
# VARIATION K: With Hidden/Private Section
# ============================================================================

section "VARIATION K: With Private Section (jake -la)"
echo -e "${MUTED}Showing hidden recipes when --all is used${R}"
echo ""

prompt "jake -la"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo ""
echo -e " ${BOLD}${ROSE}test${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo ""
echo -e " ${MUTED}private${R}"
echo -e "   ${MUTED}_setup${R}       ${MUTED}Internal setup task${R}"
echo -e "   ${MUTED}_helper${R}      ${MUTED}Test helper${R}"

divider

# ============================================================================
# MY RECOMMENDATION
# ============================================================================

section "RECOMMENDED: Minimal + Branding + Bold Groups"
echo -e "${MUTED}Based on expert feedback - clean, scannable, good taste${R}"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "   ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e " ${BOLD}${ROSE}test${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo -e "   ${ROSE}bench${R}        ${MUTED}Run benchmarks${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"
echo -e " ${ROSE}fmt${R}            ${MUTED}Format source files${R}"

echo ""
echo -e "${MUTED}Key decisions:${R}"
echo -e "${MUTED}  • Branding at top (one line)${R}"
echo -e "${MUTED}  • Groups are bold rose (stand out)${R}"
echo -e "${MUTED}  • Recipes are regular rose${R}"
echo -e "${MUTED}  • Descriptions are muted (no # prefix)${R}"
echo -e "${MUTED}  • No type badges - the name tells you${R}"
echo -e "${MUTED}  • Ungrouped recipes at the end${R}"
echo -e "${MUTED}  • 1-char inset for polish${R}"

echo ""
