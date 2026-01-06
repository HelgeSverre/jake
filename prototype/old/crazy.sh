#!/bin/bash
# Jake CLI - CRAZY EDITION
# Run: bash prototype/crazy.sh
#
# Going absolutely nuts with terminal design ideas.
# Some of these are terrible. Some might spark something good.

# ============================================================================
# COLORS - ALL OF THEM
# ============================================================================

R="\x1b[0m"
BOLD="\x1b[1m"
DIM="\x1b[2m"
ITALIC="\x1b[3m"
UNDERLINE="\x1b[4m"
BLINK="\x1b[5m"
INVERSE="\x1b[7m"

# Brand
ROSE="\x1b[38;2;244;63;94m"
GREEN="\x1b[38;2;34;197;94m"
RED="\x1b[38;2;239;68;68m"
YELLOW="\x1b[38;2;234;179;8m"
BLUE="\x1b[38;2;96;165;250m"
MUTED="\x1b[38;2;113;113;122m"
CYAN="\x1b[38;2;6;182;212m"

# Extra colors
ORANGE="\x1b[38;2;249;115;22m"
PURPLE="\x1b[38;2;168;85;247m"
PINK="\x1b[38;2;236;72;153m"
LIME="\x1b[38;2;132;204;22m"
TEAL="\x1b[38;2;20;184;166m"
INDIGO="\x1b[38;2;99;102;241m"
WHITE="\x1b[38;2;250;250;250m"

# Backgrounds
BG_ROSE="\x1b[48;2;244;63;94m"
BG_DARK="\x1b[48;2;24;24;27m"
BG_DARKER="\x1b[48;2;9;9;11m"

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
echo ""
section "🔥 JAKE CLI - CRAZY EDITION 🔥"
echo -e "${MUTED}Wild experiments. Some good. Some terrible. All fun.${R}"

divider

# ============================================================================
# CRAZY 1: ASCII Art Banner
# ============================================================================

section "CRAZY 1: ASCII Art Banner"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}     ██╗ █████╗ ██╗  ██╗███████╗${R}"
echo -e " ${ROSE}     ██║██╔══██╗██║ ██╔╝██╔════╝${R}"
echo -e " ${ROSE}     ██║███████║█████╔╝ █████╗  ${R}"
echo -e " ${ROSE}██   ██║██╔══██║██╔═██╗ ██╔══╝  ${R}"
echo -e " ${ROSE}╚█████╔╝██║  ██║██║  ██╗███████╗${R}"
echo -e " ${ROSE} ╚════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝${R}"
echo -e " ${MUTED}modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}  ${ROSE}test${R}  ${ROSE}deploy${R}  ${ROSE}clean${R}  ${ROSE}ci${R}"

divider

# ============================================================================
# CRAZY 2: Boxed Cards
# ============================================================================

section "CRAZY 2: Boxed Cards"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${MUTED}╭─────────────────────────────────────╮${R}"
echo -e " ${MUTED}│${R} ${BOLD}${ROSE}build${R}                                ${MUTED}│${R}"
echo -e " ${MUTED}├─────────────────────────────────────┤${R}"
echo -e " ${MUTED}│${R}   ${ROSE}build${R}        Build the application ${MUTED}│${R}"
echo -e " ${MUTED}│${R}   ${ROSE}clean${R}        Remove artifacts       ${MUTED}│${R}"
echo -e " ${MUTED}│${R}   ${ROSE}dist/app.js${R}  Bundle JavaScript      ${MUTED}│${R}"
echo -e " ${MUTED}╰─────────────────────────────────────╯${R}"
echo ""
echo -e " ${MUTED}╭─────────────────────────────────────╮${R}"
echo -e " ${MUTED}│${R} ${BOLD}${ROSE}test${R}                                 ${MUTED}│${R}"
echo -e " ${MUTED}├─────────────────────────────────────┤${R}"
echo -e " ${MUTED}│${R}   ${ROSE}test${R}         Run all tests         ${MUTED}│${R}"
echo -e " ${MUTED}│${R}   ${ROSE}test-unit${R}    Unit tests only       ${MUTED}│${R}"
echo -e " ${MUTED}╰─────────────────────────────────────╯${R}"

divider

# ============================================================================
# CRAZY 3: Emoji Madness
# ============================================================================

section "CRAZY 3: Emoji Everything"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ✨ ${MUTED}modern command runner${R}"
echo ""
echo -e " 📦 ${BOLD}${ROSE}build${R}"
echo -e "    🔨 ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "    🧹 ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "    📄 ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e " 🧪 ${BOLD}${ROSE}test${R}"
echo -e "    ✅ ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "    🔬 ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " 🚀 ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ⚡ ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# CRAZY 4: Nerd Font Icons
# ============================================================================

section "CRAZY 4: Nerd Font Icons (if you have them)"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e "  ${BOLD}${ROSE}build${R}"
echo -e "     ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "     ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "    󰈙 ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e "  ${BOLD}${ROSE}test${R}"
echo -e "    󰙨 ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "    󰙨 ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e "  ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e "  ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# CRAZY 5: Two Column Layout
# ============================================================================

section "CRAZY 5: Two Column Layout"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}                              ${BOLD}${ROSE}test${R}"
echo -e "   ${ROSE}build${R}      Build application          ${ROSE}test${R}       Run all tests"
echo -e "   ${ROSE}clean${R}      Remove artifacts            ${ROSE}test-unit${R}  Unit tests only"
echo -e "   ${ROSE}dist/app${R}   Bundle JS                   ${ROSE}bench${R}      Benchmarks"
echo ""
echo -e " ${BOLD}${ROSE}deploy${R}                             ${BOLD}${ROSE}dev${R}"
echo -e "   ${ROSE}staging${R}    Deploy to staging           ${ROSE}watch${R}      Watch mode"
echo -e "   ${ROSE}prod${R}       Deploy to production        ${ROSE}fmt${R}        Format code"

divider

# ============================================================================
# CRAZY 6: Rainbow Gradient
# ============================================================================

section "CRAZY 6: Rainbow Gradient Names"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}"
echo -e "   ${RED}b${ORANGE}u${YELLOW}i${LIME}l${GREEN}d${R}        ${MUTED}Build the application${R}"
echo -e "   ${CYAN}c${BLUE}l${INDIGO}e${PURPLE}a${PINK}n${R}        ${MUTED}Remove build artifacts${R}"
echo ""
echo -e " ${BOLD}${ROSE}test${R}"
echo -e "   ${RED}t${ORANGE}e${YELLOW}s${LIME}t${R}         ${MUTED}Run all tests${R}"

divider

# ============================================================================
# CRAZY 7: Progress Bar Style
# ============================================================================

section "CRAZY 7: Progress Bar Aesthetic"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${ROSE}▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓${R} ${BOLD}build${R}"
echo -e " ${MUTED}░░${R} ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e " ${MUTED}░░${R} ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo ""
echo -e " ${ROSE}▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓${R} ${BOLD}test${R}"
echo -e " ${MUTED}░░${R} ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e " ${MUTED}░░${R} ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"

divider

# ============================================================================
# CRAZY 8: Tree View with Fancy Lines
# ============================================================================

section "CRAZY 8: Fancy Tree View"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${MUTED}┌──${R} ${BOLD}${ROSE}build${R}"
echo -e " ${MUTED}│   ├──${R} ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e " ${MUTED}│   ├──${R} ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e " ${MUTED}│   └──${R} ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo -e " ${MUTED}│${R}"
echo -e " ${MUTED}├──${R} ${BOLD}${ROSE}test${R}"
echo -e " ${MUTED}│   ├──${R} ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e " ${MUTED}│   └──${R} ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo -e " ${MUTED}│${R}"
echo -e " ${MUTED}└──${R} ${ROSE}deploy${R}           ${MUTED}Deploy to production${R}"

divider

# ============================================================================
# CRAZY 9: Inline Badges
# ============================================================================

section "CRAZY 9: Inline Badges"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}    ${BG_ROSE}${WHITE} default ${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "   ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}        ${BG_DARK}${BLUE} file ${R}"
echo ""
echo -e " ${BOLD}${ROSE}test${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}            ${BG_DARK}${YELLOW} slow ${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"

divider

# ============================================================================
# CRAZY 10: Sparkles & Decorations
# ============================================================================

section "CRAZY 10: Sparkles & Decorations"
echo ""

prompt "jake -l"
echo ""
echo -e " ✦ ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R} ✦"
echo ""
echo -e " ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
echo -e " ┃                                         ┃"
echo -e " ┃  ◆ ${BOLD}${ROSE}build${R}                                ┃"
echo -e " ┃    › ${ROSE}build${R}        ${MUTED}Build the app${R}        ┃"
echo -e " ┃    › ${ROSE}clean${R}        ${MUTED}Remove artifacts${R}     ┃"
echo -e " ┃                                         ┃"
echo -e " ┃  ◆ ${BOLD}${ROSE}test${R}                                 ┃"
echo -e " ┃    › ${ROSE}test${R}         ${MUTED}Run all tests${R}        ┃"
echo -e " ┃    › ${ROSE}test-unit${R}    ${MUTED}Unit tests only${R}      ┃"
echo -e " ┃                                         ┃"
echo -e " ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"

divider

# ============================================================================
# CRAZY 11: Retro Terminal
# ============================================================================

section "CRAZY 11: Retro Terminal / CRT Vibes"
echo ""

prompt "jake -l"
echo ""
echo -e " ${GREEN}╔══════════════════════════════════════╗${R}"
echo -e " ${GREEN}║  {j} JAKE v0.2.0                      ║${R}"
echo -e " ${GREEN}║  MODERN COMMAND RUNNER               ║${R}"
echo -e " ${GREEN}╠══════════════════════════════════════╣${R}"
echo -e " ${GREEN}║                                      ║${R}"
echo -e " ${GREEN}║  > BUILD                             ║${R}"
echo -e " ${GREEN}║    - build        Build application  ║${R}"
echo -e " ${GREEN}║    - clean        Remove artifacts   ║${R}"
echo -e " ${GREEN}║                                      ║${R}"
echo -e " ${GREEN}║  > TEST                              ║${R}"
echo -e " ${GREEN}║    - test         Run all tests      ║${R}"
echo -e " ${GREEN}║    - test-unit    Unit tests only    ║${R}"
echo -e " ${GREEN}║                                      ║${R}"
echo -e " ${GREEN}╚══════════════════════════════════════╝${R}"

divider

# ============================================================================
# CRAZY 12: Minimalist with Dots
# ============================================================================

section "CRAZY 12: Minimalist with Dots"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R}"
echo ""
echo -e " ${MUTED}·${R} ${BOLD}${ROSE}build${R}"
echo -e "   ${MUTED}·${R} ${ROSE}build${R} ${MUTED}...${R} Build the application"
echo -e "   ${MUTED}·${R} ${ROSE}clean${R} ${MUTED}...${R} Remove build artifacts"
echo ""
echo -e " ${MUTED}·${R} ${BOLD}${ROSE}test${R}"
echo -e "   ${MUTED}·${R} ${ROSE}test${R} ${MUTED}....${R} Run all tests"
echo -e "   ${MUTED}·${R} ${ROSE}test-unit${R} ${MUTED}${R} Unit tests only"
echo ""
echo -e " ${MUTED}·${R} ${ROSE}deploy${R} ${MUTED}..${R} Deploy to production"

divider

# ============================================================================
# CRAZY 13: Keyboard Style
# ============================================================================

section "CRAZY 13: Keyboard Keys Style"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BOLD}${ROSE}build${R}"
echo -e "   ${MUTED}┌───────┐${R}"
echo -e "   ${MUTED}│${R} ${ROSE}build${R} ${MUTED}│${R} Build the application"
echo -e "   ${MUTED}└───────┘${R}"
echo -e "   ${MUTED}┌───────┐${R}"
echo -e "   ${MUTED}│${R} ${ROSE}clean${R} ${MUTED}│${R} Remove build artifacts"
echo -e "   ${MUTED}└───────┘${R}"

divider

# ============================================================================
# CRAZY 14: Status Dashboard
# ============================================================================

section "CRAZY 14: Status Dashboard"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo -e " ${MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"
echo ""
echo -e " ${GREEN}●${R} ${BOLD}${ROSE}build${R}              ${MUTED}3 recipes${R}"
echo -e "   ${GREEN}●${R} ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${GREEN}●${R} ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "   ${YELLOW}●${R} ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R} ${MUTED}(file)${R}"
echo ""
echo -e " ${GREEN}●${R} ${BOLD}${ROSE}test${R}               ${MUTED}2 recipes${R}"
echo -e "   ${GREEN}●${R} ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${GREEN}●${R} ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"
echo -e " ${MUTED}8 recipes • 2 groups • 1 file target${R}"

divider

# ============================================================================
# CRAZY 15: Pill/Tag Style
# ============================================================================

section "CRAZY 15: Pill/Tag Style Groups"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${BG_ROSE}${WHITE} build ${R}"
echo -e "   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "   ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e " ${BG_ROSE}${WHITE} test ${R}"
echo -e "   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# CRAZY 16: Arrow Flow
# ============================================================================

section "CRAZY 16: Arrow Flow Style"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${ROSE}▶${R} ${BOLD}build${R}"
echo -e "   ${MUTED}├▷${R} ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "   ${MUTED}├▷${R} ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "   ${MUTED}└▷${R} ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e " ${ROSE}▶${R} ${BOLD}test${R}"
echo -e "   ${MUTED}├▷${R} ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "   ${MUTED}└▷${R} ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${ROSE}▷${R} ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${ROSE}▷${R} ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# CRAZY 17: Indented Blocks
# ============================================================================

section "CRAZY 17: Block Indent Style"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${ROSE}█${R} ${BOLD}build${R}"
echo -e " ${ROSE}┃${R}   ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e " ${ROSE}┃${R}   ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e " ${ROSE}┃${R}   ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo ""
echo -e " ${ROSE}█${R} ${BOLD}test${R}"
echo -e " ${ROSE}┃${R}   ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e " ${ROSE}┃${R}   ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e " ${MUTED}○${R} ${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e " ${MUTED}○${R} ${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# CRAZY 18: Cyberpunk Aesthetic
# ============================================================================

section "CRAZY 18: Cyberpunk / Neon"
echo ""

prompt "jake -l"
echo ""
echo -e " ${PINK}╭${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}╮${R}"
echo -e " ${PINK}│${R} ${CYAN}{j}${R} ${BOLD}${PINK}J${CYAN}A${PINK}K${CYAN}E${R}                             ${PINK}│${R}"
echo -e " ${PINK}│${R} ${MUTED}>> COMMAND_RUNNER.exe${R}              ${PINK}│${R}"
echo -e " ${PINK}╰${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}─${CYAN}─${PINK}╯${R}"
echo ""
echo -e " ${CYAN}[${PINK}BUILD${CYAN}]${R}"
echo -e "   ${CYAN}>${R} ${PINK}build${R}        ${MUTED}// Build application${R}"
echo -e "   ${CYAN}>${R} ${PINK}clean${R}        ${MUTED}// Remove artifacts${R}"
echo ""
echo -e " ${CYAN}[${PINK}TEST${CYAN}]${R}"
echo -e "   ${CYAN}>${R} ${PINK}test${R}         ${MUTED}// Run all tests${R}"

divider

# ============================================================================
# CRAZY 19: Git-style Branches
# ============================================================================

section "CRAZY 19: Git Branch Style"
echo ""

prompt "jake -l"
echo ""
echo -e " ${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e " ${GREEN}*${R} ${BOLD}${ROSE}build${R} ${MUTED}(3 recipes)${R}"
echo -e " ${GREEN}│${R} ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e " ${GREEN}│${R} ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e " ${GREEN}│${R} ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript${R}"
echo -e " ${GREEN}│${R}"
echo -e " ${GREEN}*${R} ${BOLD}${ROSE}test${R} ${MUTED}(2 recipes)${R}"
echo -e " ${GREEN}│${R} ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e " ${GREEN}│${R} ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo -e " ${GREEN}│${R}"
echo -e " ${MUTED}○${R} ${ROSE}deploy${R}       ${MUTED}Deploy to production${R}"
echo -e " ${MUTED}○${R} ${ROSE}ci${R}           ${MUTED}Run CI pipeline${R}"

divider

# ============================================================================
# CRAZY 20: Just the Vibes
# ============================================================================

section "CRAZY 20: Pure Aesthetic (form over function)"
echo ""

prompt "jake -l"
echo ""
echo -e "                                                    "
echo -e "        ${DIM}░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░${R}        "
echo -e "        ${DIM}░${R}                                  ${DIM}░${R}        "
echo -e "        ${DIM}░${R}    ${ROSE}{j}${R} ${BOLD}jake${R}                      ${DIM}░${R}        "
echo -e "        ${DIM}░${R}    ${MUTED}modern command runner${R}        ${DIM}░${R}        "
echo -e "        ${DIM}░${R}                                  ${DIM}░${R}        "
echo -e "        ${DIM}░${R}    ${ROSE}build${R}   ${ROSE}test${R}   ${ROSE}deploy${R}       ${DIM}░${R}        "
echo -e "        ${DIM}░${R}    ${ROSE}clean${R}   ${ROSE}ci${R}     ${ROSE}fmt${R}          ${DIM}░${R}        "
echo -e "        ${DIM}░${R}                                  ${DIM}░${R}        "
echo -e "        ${DIM}░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░${R}        "
echo ""

divider

echo -e "${MUTED}Which ones spark joy? Which are absolute garbage?${R}"
echo -e "${MUTED}Mix and match elements to find the right vibe.${R}"
echo ""
