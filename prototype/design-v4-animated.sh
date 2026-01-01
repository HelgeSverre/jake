#!/bin/bash
# =============================================================================
# Jake CLI Design v4 - Animated Demo
# =============================================================================
# Inspired by: Nx, Turborepo, Cargo, Deno
# Run: bash prototype/design-v4-animated.sh
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

# Animation speeds
FAST=0.03
MED=0.08
SLOW=0.4
PAUSE=1.5

clear

# Typing effect
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

# Section with cyan explanation
section() {
    echo ""
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R} ${CYAN}$1${R}"
    echo ""
    sleep $SLOW
}

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

line "${ROSE}{j}${R} ${BOLD}JAKE CLI DESIGN v4${R}"
line "${MUTED}Animated demo • Inspired by Nx, Turborepo, Cargo${R}"
sleep $PAUSE

section "VERSION OUTPUT"

line "${MUTED}\$${R} jake --version"
sleep $MED
line "${ROSE}{j}${R} jake 0.3.0"
sleep $PAUSE

section "HELP OUTPUT"

line "${MUTED}\$${R} jake --help"
sleep $MED
line ""
line "${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
line ""
line "${BOLD}Usage:${R} jake [options] [recipe] [args...]"
line ""
line "${BOLD}Options:${R}"
line "  -l, --list        List recipes"
line "  -n, --dry-run     Preview execution"
line "  -w, --watch       Watch and re-run"
line "  -j, --jobs N      Parallel tasks"
line ""
line "${BOLD}Examples:${R}"
line "  jake build"
line "  jake test -j4"
line "  jake -w dev"
sleep $PAUSE

section "SINGLE TASK EXECUTION"

line "${MUTED}\$${R} jake build"
sleep $MED
spinner "build" 2
printf "\r   ${GREEN}✓${R} ${BOLD}build${R}                              \n"
line "     ${MUTED}zig build${R}"
line "     ${GREEN}completed in 1.82s${R}"
sleep $PAUSE

section "TASK WITH DEPENDENCIES (dev.ci)"

line "${MUTED}\$${R} jake dev.ci"
sleep $MED
line ""

# lint
spinner "lint" 1
printf "\r   ${GREEN}✓${R} lint      ${MUTED}0.12s${R}                      \n"
sleep 0.1

# test  
spinner "test" 2
printf "\r   ${GREEN}✓${R} test      ${MUTED}3.40s${R}                      \n"
sleep 0.1

# build
spinner "build" 1
printf "\r   ${GREEN}✓${R} build     ${MUTED}2.10s${R}                      \n"
sleep 0.1

# e2e
spinner "e2e" 2
printf "\r   ${GREEN}✓${R} e2e       ${MUTED}4.70s${R}                      \n"
sleep 0.2

line ""
line "   ${GREEN}Successfully ran 4 tasks${R}"
line "   ${MUTED}Total time: 10.3s${R}"
sleep $PAUSE

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
printf "\r   ${GREEN}✓${R} release.checksums ${MUTED}0.02s${R}                \n"

line ""
line "   ${GREEN}Successfully ran 4 tasks${R}"
line "   ${MUTED}Total time: 4.2s${R}"
sleep $PAUSE

section "TASK FAILURE"

line "${MUTED}\$${R} jake test"
sleep $MED
line ""
spinner "test" 2
printf "\r   ${RED}✗${R} ${BOLD}test${R}                                \n"
line ""
line "   ${MUTED}src/parser.zig:142:25${R}"
line "   ${RED}error:${R} expected ')' after argument"
line ""
line "   ${RED}✗${R} ${BOLD}test${R} ${MUTED}failed with exit code 1${R}"
sleep $PAUSE

section "RECIPE LIST (jake -l)"

line "${MUTED}\$${R} jake -l"
sleep $MED
line ""
line "${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}98 recipes • 14 groups${R}"
line ""
line "${BOLD}build${R}"
line "  build           ${MUTED}Compile jake binary${R}"
line "  build-release   ${MUTED}Optimized release build${R}"
line "  clean           ${MUTED}Remove build artifacts${R}"
line ""
line "${BOLD}test${R}"
line "  test            ${MUTED}Run all tests${R}"
line "  lint            ${MUTED}Check formatting${R}"
line "  e2e             ${MUTED}End-to-end tests${R}"
line ""
line "${BOLD}dev${R}"
line "  dev             ${MUTED}Development build${R}"
line "  dev.ci          ${MUTED}Run CI checks${R}"
line ""
line "${BOLD}release${R}"
line "  release.build   ${MUTED}Current platform${R}"
line "  release.all     ${MUTED}All platforms${R}"
line ""
line "${MUTED}... 88 more recipes (jake -la for all)${R}"
sleep $PAUSE

section "WATCH MODE"

line "${MUTED}\$${R} jake -w dev"
sleep $MED
line ""
line "   ${BLUE}◉${R} ${BOLD}watching${R} ${MUTED}src/**/*.zig${R}"
line ""
spinner "dev" 1
printf "\r   ${GREEN}✓${R} dev ${MUTED}1.82s${R}                          \n"
sleep 0.8
line ""
line "   ${YELLOW}⟳${R} ${MUTED}changed${R} src/parser.zig"
spinner "dev" 1
printf "\r   ${GREEN}✓${R} dev ${MUTED}0.34s${R}                          \n"
sleep 0.5
line ""
line "   ${MUTED}watching for changes (ctrl+c to stop)${R}"
sleep $PAUSE

section "DRY RUN (-n)"

line "${MUTED}\$${R} jake -n release.all"
sleep $MED
line ""
line "   ${BLUE}▷${R} ${BOLD}dry-run${R} ${MUTED}(no commands executed)${R}"
line ""
line "   ${MUTED}○${R} release.linux"
line "     ${DIM}zig build -Dtarget=x86_64-linux${R}"
line "   ${MUTED}○${R} release.macos"
line "     ${DIM}zig build -Dtarget=aarch64-macos${R}"
line "   ${MUTED}○${R} release.windows"
line "     ${DIM}zig build -Dtarget=x86_64-windows${R}"
line "   ${MUTED}○${R} release.checksums"
line "     ${DIM}sha256sum zig-out/bin/*${R}"
line ""
line "   ${MUTED}4 tasks would run${R}"
sleep $PAUSE

section "FILE TARGET (up to date)"

line "${MUTED}\$${R} jake zig-out/bin/jake"
sleep $MED
line ""
line "   ${MUTED}—${R} zig-out/bin/jake ${MUTED}(up to date)${R}"
sleep $PAUSE

section "FILE TARGET (outdated)"

line "${MUTED}\$${R} jake zig-out/bin/jake"
sleep $MED
line ""
line "   ${MUTED}sources changed: src/parser.zig (2m ago)${R}"
spinner "zig-out/bin/jake" 1
printf "\r   ${GREEN}✓${R} zig-out/bin/jake ${MUTED}1.8s${R}              \n"
sleep $PAUSE

section "ERROR: RECIPE NOT FOUND"

line "${MUTED}\$${R} jake biuld"
sleep $MED
line ""
line "${RED}error:${R} recipe 'biuld' not found"
line ""
line "   ${MUTED}did you mean:${R} ${ROSE}build${R}"
sleep $PAUSE

section "ERROR: MISSING DEPENDENCY"

line "${MUTED}\$${R} jake perf.tracy"
sleep $MED
line ""
line "${RED}error:${R} required command not found: ${BOLD}tracy${R}"
line ""
line "   ${BLUE}hint:${R} brew install tracy"
sleep $PAUSE

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

section "CONFIRMATION PROMPT"

line "${MUTED}\$${R} jake editors.vscode-publish"
sleep $MED
line ""
spinner "editors.vscode-package" 1
printf "\r   ${GREEN}✓${R} editors.vscode-package               \n"
sleep 0.2
line ""
printf "   ${YELLOW}?${R} Publish jake-lang 0.3.0 to marketplace? ${MUTED}[y/N]${R} "
sleep $PAUSE
echo ""
sleep $PAUSE

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

section "CACHE HIT (Nx/Turborepo style)"

line "${MUTED}\$${R} jake build"
sleep $MED
line ""
line "   ${GREEN}✓${R} ${BOLD}build${R} ${MUTED}[cached]${R}"
line "     ${MUTED}replayed output from cache${R}"
line "     ${GREEN}completed in 0.02s${R}"
sleep $PAUSE

section "END"

line "${ROSE}{j}${R} ${MUTED}Design v4 complete${R}"
line ""
line "${CYAN}Design decisions:${R}"
line "  • Animated spinners during execution"
line "  • Box drawing for parallel tasks (visual grouping)"
line "  • Individual task timings + summary (Nx-style)"
line "  • Symbols: ✓ ✗ ◉ ○ — ⟳"
line "  • [cached] indicator for cache hits"
line ""
