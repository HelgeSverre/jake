#!/bin/bash
# =============================================================================
# Jake CLI Design v5 - Animated Demo
# =============================================================================
# Animated demonstration of Jake's actual CLI output.
# Shows typing effects, real spinner animations, and realistic timing.
# Run: bash prototype/design-v5-animated.sh
# =============================================================================

R="\x1b[0m"
BOLD="\x1b[1m"
DIM="\x1b[2m"

# Brand colors (24-bit true color) - from src/color.zig
ROSE="\x1b[38;2;244;63;94m"      # #f43f5e - Jake Rose
GREEN="\x1b[38;2;34;197;94m"     # #22c55e - Success Green
RED="\x1b[38;2;239;68;68m"       # #ef4444 - Error Red
YELLOW="\x1b[38;2;234;179;8m"    # #eab308 - Warning Yellow
BLUE="\x1b[38;2;96;165;250m"     # #60a5fa - Info Blue
MUTED="\x1b[38;2;113;113;122m"   # #71717a - Muted Gray

# Animation speeds
FAST=0.03
MED=0.08
SLOW=0.4
PAUSE=1.5

clear

# Typing effect for commands
type_line() {
    local text="$1"
    local delay="${2:-$FAST}"
    for ((i=0; i<${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep "$delay"
    done
    echo ""
}

# Instant line
line() {
    echo -e "$1"
}

# Section with description
section() {
    echo ""
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R} ${BLUE}$1${R}"
    echo ""
    sleep $SLOW
}

# Animated spinner (runs for specified duration)
spinner() {
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local text="$1"
    local duration="$2"
    local end_time=$((SECONDS + duration))
    local i=0

    while [ $SECONDS -lt $end_time ]; do
        printf "\r   ${ROSE}%s${R} %s" "${frames[$i]}" "$text"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.08
    done
}

# =============================================================================
# START
# =============================================================================

line "${ROSE}{j}${R} ${BOLD}JAKE CLI DESIGN v5 - ANIMATED DEMO${R}"
line "${MUTED}Animated demonstration of actual CLI output${R}"
sleep $PAUSE

# =============================================================================
# VERSION OUTPUT
# =============================================================================

section "VERSION OUTPUT"

line "${MUTED}\$${R} jake --version"
sleep $MED
line "${ROSE}{j}${R} jake ${MUTED}0.5.0${R}"
sleep $PAUSE

# =============================================================================
# HELP OUTPUT
# =============================================================================

section "HELP OUTPUT"

line "${MUTED}\$${R} jake --help"
sleep $MED
line ""
line "${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
line ""
line "${BOLD}Usage:${R} jake [options] [recipe] [args...]"
line ""
line "${BOLD}General:${R}"
line "  -h, --help              Show this help message"
line "  -V, --version           Show version"
line ""
line "${BOLD}Output:${R}"
line "  -l, --list              List available recipes"
line "  -s, --show RECIPE       Show detailed recipe information"
line ""
line "${BOLD}Execution:${R}"
line "  -n, --dry-run           Print commands without executing"
line "  -v, --verbose           Show verbose output"
line "  -w, --watch [PATTERN]   Watch files and re-run"
line "  -j, --jobs [N]          Run N recipes in parallel"
line ""
line "${BOLD}Examples:${R}"
line "  jake build            ${MUTED}Run the build recipe${R}"
line "  jake test -v          ${MUTED}Run tests with verbose output${R}"
line "  jake -w dev           ${MUTED}Watch and rebuild on changes${R}"
sleep $PAUSE

# =============================================================================
# SINGLE TASK EXECUTION
# =============================================================================

section "SINGLE TASK EXECUTION"

line "${MUTED}\$${R} jake build"
sleep $MED
spinner "build" 2
printf "\r\x1b[K"
line ""
line "   ${GREEN}✓${R} build     ${MUTED}1.82s${R}"
line ""
line "   ${GREEN}Successfully ran 1 task${R}"
line "   ${MUTED}Total time: 1.82s${R}"
sleep $PAUSE

# =============================================================================
# SEQUENTIAL TASKS WITH DEPENDENCIES
# =============================================================================

section "SEQUENTIAL TASKS (with dependencies)"

line "${MUTED}\$${R} jake dev.ci"
sleep $MED
line ""

# lint
spinner "lint" 1
printf "\r\x1b[K"
line ""
line "   ${GREEN}✓${R} lint      ${MUTED}0.12s${R}"
sleep 0.1

# test
spinner "test" 2
printf "\r\x1b[K"
line ""
line "   ${GREEN}✓${R} test      ${MUTED}3.40s${R}"
sleep 0.1

# build
spinner "build" 1
printf "\r\x1b[K"
line ""
line "   ${GREEN}✓${R} build     ${MUTED}2.10s${R}"
sleep 0.1

# e2e
spinner "e2e" 2
printf "\r\x1b[K"
line ""
line "   ${GREEN}✓${R} e2e       ${MUTED}4.70s${R}"
sleep 0.2

line ""
line "   ${GREEN}Successfully ran 4 tasks${R}"
line "   ${MUTED}Total time: 10.32s${R}"
sleep $PAUSE

# =============================================================================
# PARALLEL EXECUTION
# =============================================================================

section "PARALLEL EXECUTION (-j4)"

line "${MUTED}\$${R} jake -j4 release.all"
sleep $MED
line ""

# Parallel execution with box separators
line "   ${MUTED}┌─────────────────────────────────────────────────────┐${R}"

# Animate all three spinners together
frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
for i in {1..20}; do
    f="${frames[$((i % 10))]}"
    printf "\r   ${MUTED}│${R} ${ROSE}%s${R} release.linux ${MUTED}│${R} ${ROSE}%s${R} release.macos ${MUTED}│${R} ${ROSE}%s${R} release.windows ${MUTED}│${R}" "$f" "$f" "$f"
    sleep 0.08
done

# macos finishes first
for i in {1..8}; do
    f="${frames[$((i % 10))]}"
    printf "\r   ${MUTED}│${R} ${ROSE}%s${R} release.linux ${MUTED}│${R} ${GREEN}✓${R} release.macos ${MUTED}│${R} ${ROSE}%s${R} release.windows ${MUTED}│${R}" "$f" "$f"
    sleep 0.08
done

# linux finishes
for i in {1..6}; do
    f="${frames[$((i % 10))]}"
    printf "\r   ${MUTED}│${R} ${GREEN}✓${R} release.linux ${MUTED}│${R} ${GREEN}✓${R} release.macos ${MUTED}│${R} ${ROSE}%s${R} release.windows ${MUTED}│${R}" "$f"
    sleep 0.08
done

# all done
printf "\r   ${MUTED}│${R} ${GREEN}✓${R} release.linux ${MUTED}│${R} ${GREEN}✓${R} release.macos ${MUTED}│${R} ${GREEN}✓${R} release.windows ${MUTED}│${R}\n"
line "   ${MUTED}└─────────────────────────────────────────────────────┘${R}"
line ""
line "   ${GREEN}✓${R} release.linux     ${MUTED}3.8s${R}"
line "   ${GREEN}✓${R} release.macos     ${MUTED}3.2s${R}"
line "   ${GREEN}✓${R} release.windows   ${MUTED}4.1s${R}"
line ""

spinner "release.checksums" 1
printf "\r\x1b[K"
line "   ${GREEN}✓${R} release.checksums ${MUTED}0.02s${R}"

line ""
line "   ${GREEN}Successfully ran 4 tasks${R}"
line "   ${MUTED}Total time: 4.12s${R}"
sleep $PAUSE

# =============================================================================
# TASK FAILURE
# =============================================================================

section "TASK FAILURE"

line "${MUTED}\$${R} jake test"
sleep $MED
line ""
spinner "test" 2
printf "\r\x1b[K"
line ""
line "   ${RED}✗${R} test      ${MUTED}2.34s${R}"
line ""
line "   ${MUTED}src/parser.zig:142:25${R}"
line "   ${RED}error:${R} expected ')' after argument"
line ""
line "   ${RED}Failed to run 1 task${R}"
line "   ${MUTED}Total time: 2.34s${R}"
sleep $PAUSE

# =============================================================================
# RECIPE LIST
# =============================================================================

section "RECIPE LIST (jake -l)"

line "${MUTED}\$${R} jake -l"
sleep $MED
line "${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}98 recipes • 14 groups${R}"
line ""
line "${BOLD}build${R}"
line "  ${ROSE}build${R}           ${MUTED}Compile jake binary${R}"
line "  ${ROSE}build-release${R}   ${MUTED}Optimized release build${R}"
line "  ${ROSE}clean${R}           ${MUTED}Remove build artifacts${R}"
line ""
line "${BOLD}test${R}"
line "  ${ROSE}test${R}            ${MUTED}Run all tests${R}"
line "  ${ROSE}lint${R}            ${MUTED}Check code formatting${R}"
line "  ${ROSE}e2e${R}             ${MUTED}End-to-end tests${R}"
line ""
line "${BOLD}dev${R}"
line "  ${ROSE}dev${R}             ${MUTED}Development build${R}"
line "  ${ROSE}dev.ci${R}          ${MUTED}Run all CI checks${R}"
line ""
line "${BOLD}release${R}"
line "  ${ROSE}release.build${R}   ${MUTED}Build for current platform${R}"
line "  ${ROSE}release.all${R}     ${MUTED}Build for all platforms${R}"
line ""
line "${MUTED}... 88 more recipes (jake -la for all)${R}"
sleep $PAUSE

# =============================================================================
# WATCH MODE
# =============================================================================

section "WATCH MODE"

line "${MUTED}\$${R} jake -w dev"
sleep $MED
line ""
line "   ${BLUE}◉${R} ${BOLD}watching${R} ${MUTED}src/**/*.zig${R}"
line ""
spinner "dev" 1
printf "\r\x1b[K"
line ""
line "   ${GREEN}✓${R} dev       ${MUTED}1.82s${R}"
line ""
line "   ${GREEN}Successfully ran 1 task${R}"
line "   ${MUTED}Total time: 1.82s${R}"
sleep 0.8
line ""
line "   ${YELLOW}⟳${R} ${MUTED}changed${R} src/parser.zig"
spinner "dev" 1
printf "\r\x1b[K"
line ""
line "   ${GREEN}✓${R} dev       ${MUTED}0.34s${R}"
line ""
line "   ${GREEN}Successfully ran 1 task${R}"
line "   ${MUTED}Total time: 0.34s${R}"
sleep 0.5
line ""
line "   ${MUTED}watching for changes (ctrl+c to stop)${R}"
sleep $PAUSE

# =============================================================================
# DRY RUN
# =============================================================================

section "DRY RUN (-n)"

line "${MUTED}\$${R} jake -n release.all"
sleep $MED
line ""
line "   ${BLUE}▷${R} ${BOLD}dry-run${R} ${MUTED}(no commands executed)${R}"
line ""
line "   ${MUTED}○${R} ${ROSE}release.linux${R}"
line "     ${DIM}zig build -Dtarget=x86_64-linux${R}"
line "   ${MUTED}○${R} ${ROSE}release.macos${R}"
line "     ${DIM}zig build -Dtarget=aarch64-macos${R}"
line "   ${MUTED}○${R} ${ROSE}release.windows${R}"
line "     ${DIM}zig build -Dtarget=x86_64-windows${R}"
line "   ${MUTED}○${R} ${ROSE}release.checksums${R}"
line "     ${DIM}sha256sum zig-out/bin/*${R}"
line ""
line "   ${MUTED}4 tasks would run${R}"
sleep $PAUSE

# =============================================================================
# FILE TARGET (up to date)
# =============================================================================

section "FILE TARGET (up to date)"

line "${MUTED}\$${R} jake zig-out/bin/jake"
sleep $MED
line ""
line "   ${MUTED}—${R} zig-out/bin/jake ${MUTED}(up to date)${R}"
sleep $PAUSE

# =============================================================================
# FILE TARGET (outdated)
# =============================================================================

section "FILE TARGET (outdated)"

line "${MUTED}\$${R} jake zig-out/bin/jake"
sleep $MED
line ""
line "   ${MUTED}sources changed: src/parser.zig (2m ago)${R}"
spinner "zig-out/bin/jake" 1
printf "\r\x1b[K"
line ""
line "   ${GREEN}✓${R} zig-out/bin/jake ${MUTED}1.82s${R}"
sleep $PAUSE

# =============================================================================
# ERROR: RECIPE NOT FOUND
# =============================================================================

section "ERROR: RECIPE NOT FOUND"

line "${MUTED}\$${R} jake biuld"
sleep $MED
line ""
line "${RED}error:${R} recipe 'biuld' not found"
line ""
line "   ${MUTED}did you mean:${R} ${ROSE}build${R}"
sleep $PAUSE

# =============================================================================
# ERROR: MISSING DEPENDENCY
# =============================================================================

section "ERROR: MISSING DEPENDENCY"

line "${MUTED}\$${R} jake perf.tracy"
sleep $MED
line ""
line "${RED}error:${R} required command not found: ${BOLD}tracy${R}"
line ""
line "   ${BLUE}hint:${R} brew install tracy"
sleep $PAUSE

# =============================================================================
# ERROR: PARSE ERROR
# =============================================================================

section "ERROR: PARSE ERROR"

line "${MUTED}\$${R} jake build"
sleep $MED
line ""
line "${RED}error:${R} parse error in Jakefile"
line ""
line "   ${MUTED}┌──${R} Jakefile:24"
line "   ${MUTED}│${R}"
line "23 ${MUTED}│${R} task build"
line "24 ${MUTED}│${R}     zig build"
line "   ${MUTED}│${R}     ${RED}^${R} expected ':' after task name"
line "   ${MUTED}│${R}"
sleep $PAUSE

# =============================================================================
# CONFIRMATION PROMPT
# =============================================================================

section "CONFIRMATION PROMPT"

line "${MUTED}\$${R} jake editors.vscode-publish"
sleep $MED
line ""
spinner "editors.vscode-package" 1
printf "\r\x1b[K"
line "   ${GREEN}✓${R} editors.vscode-package ${MUTED}1.2s${R}"
sleep 0.2
line ""
printf "   ${YELLOW}?${R} Publish jake-lang 0.3.0 to marketplace? ${MUTED}[y/N]${R} "
sleep $PAUSE
echo ""
sleep $PAUSE

# =============================================================================
# RECIPE INSPECTION
# =============================================================================

section "RECIPE INSPECTION (jake -s)"

line "${MUTED}\$${R} jake -s release.build"
sleep $MED
line ""
line "${ROSE}release.build${R}"
line "${MUTED}Build optimized release for current platform${R}"
line ""
line "  group     ${MUTED}release${R}"
line "  params    ${MUTED}platform=\"native\"${R}"
line "  depends   ${MUTED}—${R}"
line ""
line "  ${MUTED}commands${R}"
line "    zig build -Doptimize=ReleaseFast -Dstrip=true"
sleep $PAUSE

# =============================================================================
# CACHE HIT
# =============================================================================

section "CACHE HIT"

line "${MUTED}\$${R} jake build"
sleep $MED
line ""
line "   ${GREEN}✓${R} build ${MUTED}[cached]${R}     ${MUTED}0.02s${R}"
line ""
line "   ${GREEN}Successfully ran 1 task${R} ${MUTED}[1 cached]${R}"
line "   ${MUTED}Total time: 0.02s${R}"
sleep $PAUSE

# =============================================================================
# END
# =============================================================================

section "END"

line "${ROSE}{j}${R} ${MUTED}v5 Demo Complete${R}"
line ""
line "${BOLD}This demo shows Jake's actual current output:${R}"
line "  • Animated braille spinners (80ms per frame)"
line "  • Blank line before completion status"
line "  • 3-space indent for status lines"
line "  • 5 spaces between name and duration"
line "  • Nx-style summary after all tasks"
line "  • Brand colors throughout"
line "  • Symbols: ✓ ✗ ◉ ⟳ ○ — ▷ ?"
line ""
