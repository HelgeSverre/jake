#!/bin/bash
# =============================================================================
# Jake CLI Design v3 - Cargo-Inspired Style
# =============================================================================
# A completely different approach: action verbs instead of symbols
# Inspired by: cargo, go build, rustc
#
# Run: bash prototype/design-v3-cargo-style.sh
# =============================================================================

R="\x1b[0m"
BOLD="\x1b[1m"
DIM="\x1b[2m"

# Brand colors
ROSE="\x1b[38;2;244;63;94m"
GREEN="\x1b[38;2;34;197;94m"
RED="\x1b[38;2;239;68;68m"
YELLOW="\x1b[38;2;234;179;8m"
BLUE="\x1b[38;2;96;165;250m"
MUTED="\x1b[38;2;113;113;122m"
CYAN="\x1b[38;2;34;211;238m"

divider() {
    echo ""
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R}"
    echo ""
}

section() {
    echo ""
    echo -e "${BOLD}$1${R}"
    echo ""
}

prompt() {
    echo -e "${MUTED}\$${R} $1"
}

# =============================================================================
echo ""
echo -e "${ROSE}{j}${R} ${BOLD}DESIGN V3: CARGO-INSPIRED STYLE${R}"
echo -e "${MUTED}Action verbs instead of symbols • Familiar to Rust/Go developers${R}"

divider

# =============================================================================
# CORE CONCEPT
# =============================================================================

section "💡 CORE CONCEPT"

echo "Instead of symbols (→✓✗), use clear action verbs:"
echo ""
echo -e "  ${GREEN}Running${R}   recipe    ${MUTED}← starting${R}"
echo -e "  ${GREEN}Finished${R}  recipe    ${MUTED}← success${R}"
echo -e "  ${RED}Failed${R}    recipe    ${MUTED}← failure${R}"
echo -e "  ${YELLOW}Skipped${R}   recipe    ${MUTED}← up to date${R}"
echo -e "  ${BLUE}Watching${R}  pattern   ${MUTED}← watch mode${R}"
echo ""
echo "Benefits:"
echo -e "  - No Unicode symbols that might not render"
echo -e "  - Self-documenting output"
echo -e "  - Matches cargo's proven UX"

divider

# =============================================================================
# TASK EXECUTION
# =============================================================================

section "TASK EXECUTION"

prompt "jake build"
echo -e "   ${GREEN}Running${R} build"
echo -e "           zig build"
echo -e "  ${GREEN}Finished${R} build in 1.8s"

echo ""
echo -e "${MUTED}With dependencies:${R}"
echo ""

prompt "jake dev.ci"
echo -e "   ${GREEN}Running${R} lint"
echo -e "           zig fmt --check src/"
echo -e "  ${GREEN}Finished${R} lint in 0.12s"
echo -e "   ${GREEN}Running${R} test"
echo -e "           zig build test"
echo -e "  ${GREEN}Finished${R} test in 3.4s"
echo -e "   ${GREEN}Running${R} build"
echo -e "           zig build -Doptimize=ReleaseFast"
echo -e "  ${GREEN}Finished${R} build in 2.1s"
echo -e "   ${GREEN}Running${R} e2e"
echo -e "           ./zig-out/bin/jake -f tests/e2e/Jakefile test-all"
echo -e "  ${GREEN}Finished${R} e2e in 4.7s"
echo ""
echo -e "  ${GREEN}Finished${R} ${BOLD}dev.ci${R} in 10.3s (4 tasks)"

echo ""
echo -e "${MUTED}On failure:${R}"
echo ""

prompt "jake test"
echo -e "   ${GREEN}Running${R} test"
echo -e "           zig build test"
echo -e "           ${MUTED}src/parser.zig:142: error: expected ')' after argument${R}"
echo -e "    ${RED}Failed${R} test"
echo ""
echo -e "${RED}error:${R} recipe 'test' failed with exit code 1"

divider

# =============================================================================
# QUIET MODE (DEFAULT?)
# =============================================================================

section "QUIET MODE (could be default)"

echo -e "${MUTED}Only show what's running, collapse success:${R}"
echo ""

prompt "jake dev.ci"
echo -e "   ${GREEN}Running${R} lint, test, build, e2e"
echo -e "  ${GREEN}Finished${R} dev.ci in 10.3s"

echo ""
echo -e "${MUTED}Verbose (-v) would show the full details above${R}"

divider

# =============================================================================
# LIST OUTPUT
# =============================================================================

section "LIST OUTPUT (jake -l)"

prompt "jake -l"
echo ""
echo -e "${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— 98 recipes in 14 groups${R}"
echo ""
echo -e "${BOLD}build${R}"
echo -e "    build             ${MUTED}Compile jake binary${R}"
echo -e "    build-release     ${MUTED}Optimized release build${R}"
echo -e "    clean             ${MUTED}Remove build artifacts${R}"
echo -e "    rebuild           ${MUTED}Clean and rebuild${R}"
echo ""
echo -e "${BOLD}test${R}"
echo -e "    test              ${MUTED}Run all tests${R}"
echo -e "    lint              ${MUTED}Check code formatting${R}"
echo -e "    e2e               ${MUTED}Run end-to-end tests${R}"
echo -e "    coverage          ${MUTED}Run with code coverage${R}"
echo ""
echo -e "${BOLD}dev${R}"
echo -e "    dev               ${MUTED}Development build with watch${R}"
echo -e "    dev.ci            ${MUTED}Run all CI checks${R}"
echo -e "    dev.check         ${MUTED}Quick pre-commit checks${R}"
echo ""
echo -e "${BOLD}release${R}"
echo -e "    release.build     ${MUTED}Build for current platform${R}"
echo -e "    release.all       ${MUTED}Build for all platforms${R}"
echo ""
echo -e "${MUTED}Run${R} jake -la ${MUTED}for all recipes including hidden${R}"

divider

# =============================================================================
# PARALLEL EXECUTION
# =============================================================================

section "PARALLEL EXECUTION"

prompt "jake -j4 release.all"
echo -e "   ${GREEN}Running${R} release.linux, release.macos, release.windows"
echo -e "  ${GREEN}Finished${R} release.macos in 3.2s"
echo -e "  ${GREEN}Finished${R} release.linux in 3.8s"
echo -e "  ${GREEN}Finished${R} release.windows in 4.1s"
echo -e "   ${GREEN}Running${R} release.checksums"
echo -e "  ${GREEN}Finished${R} release.checksums in 0.02s"
echo ""
echo -e "  ${GREEN}Finished${R} ${BOLD}release.all${R} in 4.2s (4 tasks)"

divider

# =============================================================================
# WATCH MODE
# =============================================================================

section "WATCH MODE"

prompt "jake -w dev"
echo -e "  ${BLUE}Watching${R} src/**/*.zig"
echo ""
echo -e "   ${GREEN}Running${R} dev"
echo -e "           zig build"
echo -e "  ${GREEN}Finished${R} dev in 1.82s"
echo ""
echo -e "   ${YELLOW}Changed${R} src/parser.zig"
echo -e "   ${GREEN}Running${R} dev"
echo -e "           zig build"
echo -e "  ${GREEN}Finished${R} dev in 0.34s"
echo ""
echo -e "${MUTED}Press Ctrl+C to stop${R}"

divider

# =============================================================================
# DRY RUN
# =============================================================================

section "DRY RUN"

prompt "jake -n release.all"
echo -e "  ${BLUE}Dry run${R} — no commands will be executed"
echo ""
echo -e "     ${MUTED}Would run${R} release.linux"
echo -e "               zig build -Dtarget=x86_64-linux"
echo -e "     ${MUTED}Would run${R} release.macos"
echo -e "               zig build -Dtarget=aarch64-macos"
echo -e "     ${MUTED}Would run${R} release.windows"
echo -e "               zig build -Dtarget=x86_64-windows"
echo -e "     ${MUTED}Would run${R} release.checksums"
echo -e "               sha256sum zig-out/bin/*"
echo ""
echo -e "${MUTED}4 tasks would run${R}"

divider

# =============================================================================
# FILE TARGETS
# =============================================================================

section "FILE TARGETS"

echo -e "${MUTED}Needs rebuild:${R}"
echo ""
prompt "jake zig-out/bin/jake"
echo -e "   ${GREEN}Running${R} zig-out/bin/jake ${MUTED}(outdated)${R}"
echo -e "           zig build"
echo -e "  ${GREEN}Finished${R} zig-out/bin/jake in 1.8s"

echo ""
echo -e "${MUTED}Already up to date:${R}"
echo ""
prompt "jake zig-out/bin/jake"
echo -e "   ${YELLOW}Skipped${R} zig-out/bin/jake ${MUTED}(up to date)${R}"

divider

# =============================================================================
# ERRORS
# =============================================================================

section "ERROR MESSAGES"

echo -e "${MUTED}Recipe not found:${R}"
echo ""
prompt "jake buld"
echo -e "${RED}error:${R} recipe 'buld' not found"
echo -e "       ${MUTED}did you mean:${R} build"

echo ""
echo -e "${MUTED}Missing dependency:${R}"
echo ""
prompt "jake perf.tracy"
echo -e "${RED}error:${R} required command 'tracy' not found"
echo -e "  ${BLUE}help:${R} brew install tracy"

echo ""
echo -e "${MUTED}Parse error:${R}"
echo ""
prompt "jake build"
echo -e "${RED}error:${R} parse error in Jakefile"
echo -e "  ${MUTED}-->  Jakefile:24${R}"
echo -e "   ${MUTED}|${R}"
echo -e "23 ${MUTED}|${R} task build"
echo -e "24 ${MUTED}|${R}     zig build"
echo -e "   ${MUTED}|${R}     ${RED}^ expected ':' after task name${R}"

divider

# =============================================================================
# VERSION & HELP
# =============================================================================

section "VERSION & HELP"

prompt "jake --version"
echo -e "${ROSE}{j}${R} jake 0.3.0"

echo ""
prompt "jake --help"
echo -e "${ROSE}{j}${R} ${BOLD}jake${R} — modern command runner"
echo ""
echo -e "${BOLD}Usage:${R} jake [OPTIONS] [RECIPE] [ARGS...]"
echo ""
echo -e "${BOLD}Options:${R}"
echo -e "  -l, --list        List available recipes"
echo -e "  -s, --show RECIPE Show recipe details"
echo -e "  -n, --dry-run     Show what would run"
echo -e "  -w, --watch       Watch files and re-run"
echo -e "  -j, --jobs N      Run N tasks in parallel"
echo -e "  -q, --quiet       Minimal output"
echo -e "  -v, --verbose     Detailed output"
echo -e "  -h, --help        Show this help"
echo ""
echo -e "${BOLD}Examples:${R}"
echo -e "  jake build            Run the build recipe"
echo -e "  jake -w dev           Watch and rebuild"
echo -e "  jake release.all -j4  Parallel release builds"

divider

# =============================================================================
# RECIPE INSPECTION
# =============================================================================

section "RECIPE INSPECTION (jake -s)"

prompt "jake -s release.build"
echo ""
echo -e "${BOLD}release.build${R} — Build optimized release for current platform"
echo ""
echo -e "  ${MUTED}Group:${R}    release"
echo -e "  ${MUTED}Params:${R}   platform=\"native\""
echo -e "  ${MUTED}Depends:${R}  (none)"
echo ""
echo -e "  ${MUTED}Commands:${R}"
echo -e "    zig build -Doptimize=ReleaseFast -Dstrip=true"

divider

# =============================================================================
# COMPARISON
# =============================================================================

section "COMPARISON: V2 (Symbols) vs V3 (Verbs)"

echo -e "${BOLD}V2 Arrow Style:${R}"
echo -e "  ${ROSE}→ build${R}"
echo -e "    zig build"
echo -e "  ${GREEN}✓ build${R} ${MUTED}1.8s${R}"
echo ""
echo -e "${BOLD}V3 Cargo Style:${R}"
echo -e "   ${GREEN}Running${R} build"
echo -e "           zig build"
echo -e "  ${GREEN}Finished${R} build in 1.8s"
echo ""
echo -e "${MUTED}V3 is more verbose but clearer for newcomers${R}"
echo -e "${MUTED}V2 is more compact, good for experienced users${R}"

divider

echo -e "${ROSE}{j}${R} ${MUTED}End of Design v3${R}"
echo ""
