#!/bin/bash
# =============================================================================
# Jake CLI Design v4 - Complete Specification
# =============================================================================
# This is the FINAL design spec for jake CLI output
# Run: bash prototype/design-v4-spec.sh
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
PAUSE=1.2

clear

line() { echo -e "$1"; }

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
line "${ROSE}{j}${R} ${BOLD}JAKE CLI DESIGN v4 - COMPLETE SPECIFICATION${R}"
line "${MUTED}Final design for implementation${R}"
sleep $PAUSE

# =============================================================================
# SYMBOL VOCABULARY
# =============================================================================

section "SYMBOL VOCABULARY"

line "${CYAN}Status symbols:${R}"
line "   ${GREEN}✓${R}  Success (task completed)"
line "   ${RED}✗${R}  Failure (task failed)"
line "   ${MUTED}—${R}  Skipped (up to date / not applicable)"
line ""
line "${CYAN}Activity symbols:${R}"
line "   ${ROSE}⠋${R}  Spinner (task running) - animated"
line "   ${BLUE}◉${R}  Watching (watch mode active)"
line "   ${YELLOW}⟳${R}  Changed (file modified)"
line "   ${MUTED}○${R}  Pending (dry-run, would run)"
line ""
line "${CYAN}UI symbols:${R}"
line "   ${YELLOW}?${R}  Prompt (confirmation required)"
line "   ${BLUE}▷${R}  Mode indicator (dry-run, etc)"
line "   ${MUTED}│${R}  Box drawing (parallel grouping)"
sleep $PAUSE

# =============================================================================
# VERSION OUTPUT
# =============================================================================

section "VERSION OUTPUT"

line "${MUTED}\$${R} jake --version"
sleep $MED
line "${ROSE}{j}${R} jake ${MUTED}0.3.0${R}"
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
line "${BOLD}Options:${R}"
line "  -l, --list        List available recipes"
line "  -s, --show NAME   Show recipe details"
line "  -n, --dry-run     Preview without executing"
line "  -w, --watch       Watch files and re-run"
line "  -j, --jobs N      Run N tasks in parallel"
line "  -q, --quiet       Suppress command echo"
line "  -v, --verbose     Show debug information"
line "  -y, --yes         Auto-confirm prompts"
line ""
line "${BOLD}Examples:${R}"
line "  jake build            ${MUTED}Run the build recipe${R}"
line "  jake test -v          ${MUTED}Run tests with verbose output${R}"
line "  jake -w dev           ${MUTED}Watch and rebuild on changes${R}"
line "  jake release.all -j4  ${MUTED}Parallel release builds${R}"
sleep $PAUSE

# =============================================================================
# SINGLE TASK EXECUTION
# =============================================================================

section "SINGLE TASK"

line "${MUTED}\$${R} jake build"
sleep $MED
spinner "build" 2
printf "\r   ${GREEN}✓${R} build     ${MUTED}1.82s${R}                      \n"
line ""
line "   ${GREEN}Successfully ran 1 task${R}"
line "   ${MUTED}Total time: 1.82s${R}"
sleep $PAUSE

# =============================================================================
# SEQUENTIAL TASKS WITH DEPENDENCIES
# =============================================================================

section "SEQUENTIAL TASKS (with deps)"

line "${MUTED}\$${R} jake dev.ci"
sleep $MED
line ""

spinner "lint" 1
printf "\r   ${GREEN}✓${R} lint      ${MUTED}0.12s${R}                      \n"
sleep 0.1

spinner "test" 2
printf "\r   ${GREEN}✓${R} test      ${MUTED}3.40s${R}                      \n"
sleep 0.1

spinner "build" 1
printf "\r   ${GREEN}✓${R} build     ${MUTED}2.10s${R}                      \n"
sleep 0.1

spinner "e2e" 2
printf "\r   ${GREEN}✓${R} e2e       ${MUTED}4.70s${R}                      \n"
sleep 0.2

line ""
line "   ${GREEN}Successfully ran 4 tasks${R}"
line "   ${MUTED}Total time: 10.3s${R}"
sleep $PAUSE

# =============================================================================
# PARALLEL EXECUTION
# =============================================================================

section "PARALLEL EXECUTION (-j4)"

line "${MUTED}\$${R} jake -j4 release.all"
sleep $MED
line ""

line "   ${MUTED}┌─────────────────────────────────────────────────────┐${R}"

frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
for i in {1..15}; do
    f="${frames[$((i % 10))]}"
    printf "\r   ${MUTED}│${R} ${ROSE}%s${R} release.linux ${MUTED}│${R} ${ROSE}%s${R} release.macos ${MUTED}│${R} ${ROSE}%s${R} release.windows ${MUTED}│${R}" "$f" "$f" "$f"
    sleep 0.08
done

for i in {1..6}; do
    f="${frames[$((i % 10))]}"
    printf "\r   ${MUTED}│${R} ${ROSE}%s${R} release.linux ${MUTED}│${R} ${GREEN}✓${R} release.macos ${MUTED}│${R} ${ROSE}%s${R} release.windows ${MUTED}│${R}" "$f" "$f"
    sleep 0.08
done

for i in {1..4}; do
    f="${frames[$((i % 10))]}"
    printf "\r   ${MUTED}│${R} ${GREEN}✓${R} release.linux ${MUTED}│${R} ${GREEN}✓${R} release.macos ${MUTED}│${R} ${ROSE}%s${R} release.windows ${MUTED}│${R}" "$f"
    sleep 0.08
done

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

# =============================================================================
# TASK FAILURE
# =============================================================================

section "TASK FAILURE"

line "${MUTED}\$${R} jake test"
sleep $MED
line ""
spinner "test" 2
printf "\r   ${RED}✗${R} test                                   \n"
line ""
line "   ${MUTED}src/parser.zig:142:25${R}"
line "   ${RED}error:${R} expected ')' after argument"
line ""
line "   ${RED}Failed to run 1 task${R}"
line "   ${MUTED}Total time: 2.3s${R}"
sleep $PAUSE

# =============================================================================
# RECIPE LIST
# =============================================================================

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
line "  lint            ${MUTED}Check code formatting${R}"
line "  e2e             ${MUTED}End-to-end tests${R}"
line ""
line "${BOLD}dev${R}"
line "  dev             ${MUTED}Development build${R}"
line "  dev.ci          ${MUTED}Run all CI checks${R}"
line ""
line "${BOLD}release${R}"
line "  release.build   ${MUTED}Build for current platform${R}"
line "  release.all     ${MUTED}Build for all platforms${R}"
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
printf "\r   ${GREEN}✓${R} dev       ${MUTED}1.82s${R}                      \n"
sleep 0.5
line ""
line "   ${YELLOW}⟳${R} ${MUTED}changed${R} src/parser.zig"
spinner "dev" 1
printf "\r   ${GREEN}✓${R} dev       ${MUTED}0.34s${R}                      \n"
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
# FILE TARGET
# =============================================================================

section "FILE TARGET"

line "${CYAN}Up to date:${R}"
line ""
line "${MUTED}\$${R} jake zig-out/bin/jake"
sleep $MED
line ""
line "   ${MUTED}—${R} zig-out/bin/jake ${MUTED}(up to date)${R}"

line ""
line "${CYAN}Outdated:${R}"
line ""
line "${MUTED}\$${R} jake zig-out/bin/jake"
sleep $MED
line ""
line "   ${MUTED}sources changed: src/parser.zig (2m ago)${R}"
spinner "zig-out/bin/jake" 1
printf "\r   ${GREEN}✓${R} zig-out/bin/jake ${MUTED}1.82s${R}              \n"
sleep $PAUSE

# =============================================================================
# CONFIRMATION
# =============================================================================

section "CONFIRMATION PROMPT"

line "${MUTED}\$${R} jake editors.vscode-publish"
sleep $MED
line ""
spinner "editors.vscode-package" 1
printf "\r   ${GREEN}✓${R} editors.vscode-package ${MUTED}1.2s${R}         \n"
line ""
printf "   ${YELLOW}?${R} Publish jake-lang 0.3.0 to marketplace? ${MUTED}[y/N]${R} "
sleep $PAUSE
echo ""
sleep $MED

line ""
line "${CYAN}With --yes:${R}"
line ""
line "${MUTED}\$${R} jake -y editors.vscode-publish"
sleep $MED
line ""
line "   ${GREEN}✓${R} editors.vscode-package ${MUTED}1.2s${R}"
line "   ${MUTED}auto-confirmed: Publish jake-lang 0.3.0 to marketplace?${R}"
line "   ${GREEN}✓${R} editors.vscode-publish ${MUTED}3.4s${R}"
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
# ERRORS
# =============================================================================

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

section "ERROR: NO JAKEFILE"

line "${MUTED}\$${R} jake build"
sleep $MED
line ""
line "${ROSE}{j}${R} ${RED}error:${R} no Jakefile found"
line ""
line "   ${MUTED}Searched: Jakefile, jakefile, Jakefile.jake${R}"
line "   ${BLUE}hint:${R} run ${ROSE}jake init${R} to create one"
sleep $PAUSE

# =============================================================================
# VERBOSE OUTPUT (-v)
# =============================================================================

section "VERBOSE OUTPUT (-v)"

line "${CYAN}Verbose mode adds debug info with 'jake:' prefix:${R}"
line ""
line "${MUTED}\$${R} jake -v dev.ci"
sleep $MED
line ""
line "   ${MUTED}jake: loading .env from /project/.env${R}"
line "   ${MUTED}jake: loaded 3 variables from .env${R}"
line "   ${MUTED}jake: importing 'jake/build.jake'${R}"
line "   ${MUTED}jake: imported 12 recipes from 'jake/build.jake'${R}"
line "   ${MUTED}jake: resolving dependencies for 'dev.ci'${R}"
line "   ${MUTED}jake: dependency order: lint → test → build → e2e${R}"
line ""
spinner "lint" 1
printf "\r   ${GREEN}✓${R} lint      ${MUTED}0.12s${R}                      \n"
line "   ${MUTED}jake: executing 'zig fmt --check src/'${R}"
sleep 0.1

spinner "test" 1
printf "\r   ${GREEN}✓${R} test      ${MUTED}3.40s${R}                      \n"
line "   ${MUTED}jake: executing 'zig build test'${R}"
sleep 0.1

spinner "build" 1
printf "\r   ${GREEN}✓${R} build     ${MUTED}2.10s${R}                      \n"
line "   ${MUTED}jake: executing 'zig build -Doptimize=ReleaseFast'${R}"
line "   ${MUTED}jake: cache updated for 'build'${R}"
sleep 0.1

spinner "e2e" 1
printf "\r   ${GREEN}✓${R} e2e       ${MUTED}4.70s${R}                      \n"
line "   ${MUTED}jake: executing './zig-out/bin/jake -f tests/e2e/Jakefile'${R}"
sleep 0.2

line ""
line "   ${GREEN}Successfully ran 4 tasks${R}"
line "   ${MUTED}Total time: 10.3s${R}"
sleep $PAUSE

# =============================================================================
# VERBOSE CATEGORIES
# =============================================================================

section "VERBOSE OUTPUT CATEGORIES"

line "${CYAN}All verbose messages use 'jake:' prefix in muted color:${R}"
line ""
line "${BOLD}Import resolution:${R}"
line "   ${MUTED}jake: importing 'path/to/file.jake'${R}"
line "   ${MUTED}jake: importing 'file.jake' as 'namespace'${R}"
line "   ${MUTED}jake: imported 12 recipes, 3 variables from 'file.jake'${R}"
line ""
line "${BOLD}Environment:${R}"
line "   ${MUTED}jake: loading .env from '/project/.env'${R}"
line "   ${MUTED}jake: loaded 5 variables from .env${R}"
line "   ${MUTED}jake: .env not found (skipping)${R}"
line ""
line "${BOLD}Directory changes:${R}"
line "   ${MUTED}jake: changing directory to '/project/src'${R}"
line "   ${MUTED}jake: recipe 'build' running in '/project/src'${R}"
line ""
line "${BOLD}Variable expansion:${R}"
line "   ${MUTED}jake: expanding {{name}} → 'value'${R}"
line "   ${MUTED}jake: calling {{env(HOME)}} → '/Users/dev'${R}"
line ""
line "${BOLD}Glob patterns:${R}"
line "   ${MUTED}jake: expanding 'src/*.zig' → 12 files${R}"
line ""
line "${BOLD}Cache operations:${R}"
line "   ${MUTED}jake: cache hit for 'build' (up to date)${R}"
line "   ${MUTED}jake: cache miss for 'build' (needs rebuild)${R}"
line "   ${MUTED}jake: dependency 'lib.zig' changed, rebuilding 'build'${R}"
line "   ${MUTED}jake: cache updated for 'build'${R}"
line ""
line "${BOLD}Dependencies:${R}"
line "   ${MUTED}jake: resolving dependencies for 'deploy'${R}"
line "   ${MUTED}jake: dependency order: build → test → deploy${R}"
line "   ${MUTED}jake: parallel execution: 4 threads, 3 parallel max${R}"
line ""
line "${BOLD}Watch mode:${R}"
line "   ${MUTED}jake: watching 24 files for changes${R}"
line "   ${MUTED}jake: detected change in 'src/parser.zig'${R}"
line ""
line "${BOLD}Hooks:${R}"
line "   ${MUTED}jake: running @pre hook for 'deploy'${R}"
line "   ${MUTED}jake: hook exited with code 0${R}"
line ""
line "${BOLD}Validation:${R}"
line "   ${MUTED}jake: checking @require 'docker'${R}"
line "   ${MUTED}jake: @require 'docker' satisfied${R}"
line "   ${MUTED}jake: detected platform 'macos-aarch64'${R}"
line ""
line "${BOLD}Conditions:${R}"
line "   ${MUTED}jake: evaluating condition 'env_exists(CI)' → true${R}"
line "   ${MUTED}jake: @if block taken${R}"
sleep $PAUSE

# =============================================================================
# IMPLEMENTATION LOCATIONS
# =============================================================================

section "IMPLEMENTATION MAP"

line "${CYAN}Files to modify for v4 design:${R}"
line ""
line "${BOLD}src/executor.zig${R}"
line "  • Recipe headers (→ animated spinner)"
line "  • Completion status (✓/✗ with timing)"
line "  • Nx-style summary at end"
line "  • Dry-run formatting"
line "  • Verbose 'jake:' prefix messages"
line ""
line "${BOLD}src/parallel.zig${R}"
line "  • Box-drawing for parallel tasks"
line "  • Synchronized spinner animation"
line "  • Per-thread completion updates"
line ""
line "${BOLD}src/main.zig${R}"
line "  • Version output ({j} logo)"
line "  • Error formatting (recipe not found, etc)"
line "  • No-Jakefile error with {j} logo"
line ""
line "${BOLD}src/watch.zig${R}"
line "  • ◉ watching indicator"
line "  • ⟳ changed indicator"
line ""
line "${BOLD}src/color.zig${R}"
line "  • Add new symbols (◉, ⟳, ○, —, ▷)"
line "  • Spinner frames constant"
line ""
line "${BOLD}src/args.zig${R}"
line "  • Help text with {j} logo"
line ""
line "${BOLD}src/prompt.zig${R}"
line "  • ? symbol for confirmation"
line "  • Auto-confirm message format"
sleep $PAUSE

# =============================================================================
# END
# =============================================================================

section "END"

line "${ROSE}{j}${R} ${MUTED}v4 Specification Complete${R}"
line ""
line "${CYAN}Key decisions:${R}"
line "  • Animated spinners during task execution"
line "  • Box drawing (│) for parallel task grouping"
line "  • Nx-style summary: individual timings + total"
line "  • Verbose uses 'jake:' prefix in muted color"
line "  • {j} logo in version, help, and no-Jakefile error"
line "  • Symbols: ✓ ✗ ◉ ⟳ ○ — ▷ ?"
line ""
