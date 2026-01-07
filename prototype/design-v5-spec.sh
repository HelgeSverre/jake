#!/bin/bash
# =============================================================================
# Jake CLI Design v5 - Current Implementation Specification
# =============================================================================
# This is the CANONICAL documentation of Jake's actual CLI output as implemented.
# Based on analysis of: color.zig, progress.zig, executor.zig, args.zig, main.zig
# Run: bash prototype/design-v5-spec.sh
# =============================================================================

R="\x1b[0m"
BOLD="\x1b[1m"
DIM="\x1b[2m"

# Brand colors (24-bit true color) - from src/color.zig
ROSE="\x1b[38;2;244;63;94m"      # #f43f5e - Jake Rose (brand, recipe names, logo)
GREEN="\x1b[38;2;34;197;94m"     # #22c55e - Success Green (checkmarks, success)
RED="\x1b[38;2;239;68;68m"       # #ef4444 - Error Red (failures, errors)
YELLOW="\x1b[38;2;234;179;8m"    # #eab308 - Warning Yellow (warnings, prompts, directives)
BLUE="\x1b[38;2;96;165;250m"     # #60a5fa - Info Blue (arrows, watch, mode indicators)
MUTED="\x1b[38;2;113;113;122m"   # #71717a - Muted Gray (descriptions, durations, secondary)

# Animation speeds (for section transitions only)
SLOW=0.4
PAUSE=1.2

clear

line() { echo -e "$1"; }

section() {
    echo ""
    echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${R} ${BLUE}$1${R}"
    echo ""
    sleep $SLOW
}

# Fake spinner for demo (shows final frame)
spinner_demo() {
    local text="$1"
    printf "   ${ROSE}⠋${R} %s" "$text"
    sleep 0.5
    printf "\r\x1b[K"
}

# =============================================================================
line "${ROSE}{j}${R} ${BOLD}JAKE CLI DESIGN v5 - CURRENT IMPLEMENTATION${R}"
line "${MUTED}Canonical documentation of actual CLI output${R}"
sleep $PAUSE

# =============================================================================
# SYMBOL VOCABULARY
# =============================================================================

section "SYMBOL VOCABULARY (from src/color.zig)"

line "${BOLD}Status symbols:${R}"
line "   ${GREEN}✓${R}  Success (task completed successfully)"
line "   ${RED}✗${R}  Failure (task failed)"
line "   ${MUTED}—${R}  Skipped (up to date / not applicable)"
line ""
line "${BOLD}Activity symbols:${R}"
line "   ${ROSE}⠋${R}  Spinner (task running) - 10-frame braille animation"
line "   ${BLUE}◉${R}  Watching (watch mode active)"
line "   ${YELLOW}⟳${R}  Changed (file modified in watch mode)"
line "   ${MUTED}○${R}  Pending (dry-run, task would run)"
line ""
line "${BOLD}UI symbols:${R}"
line "   ${YELLOW}?${R}  Prompt (confirmation required)"
line "   ${BLUE}▷${R}  Mode indicator (dry-run header)"
line "   ${BLUE}→${R}  Arrow (recipe execution header, non-TTY)"
line "   ${ROSE}{j}${R}  Logo (version, help, errors)"
line ""
line "${BOLD}Box-drawing (parallel execution):${R}"
line "   ${MUTED}┌ ┐ └ ┘ │ ─${R}  Box characters for grouping"
line ""
line "${BOLD}Spinner frames:${R}"
line "   ${ROSE}⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏${R}  (80ms per frame)"
sleep $PAUSE

# =============================================================================
# BRAND COLORS
# =============================================================================

section "BRAND COLORS (from src/color.zig)"

line "${ROSE}████${R} Jake Rose     #f43f5e  rgb(244, 63, 94)   - Logo, recipe names"
line "${GREEN}████${R} Success Green #22c55e  rgb(34, 197, 94)   - Success, checkmarks"
line "${RED}████${R} Error Red     #ef4444  rgb(239, 68, 68)   - Errors, failures"
line "${YELLOW}████${R} Warning Yellow #eab308  rgb(234, 179, 8)   - Warnings, prompts"
line "${BLUE}████${R} Info Blue     #60a5fa  rgb(96, 165, 250)  - Arrows, watch, info"
line "${MUTED}████${R} Muted Gray    #71717a  rgb(113, 113, 122) - Descriptions, timing"
sleep $PAUSE

# =============================================================================
# VERSION OUTPUT
# =============================================================================

section "VERSION OUTPUT (jake --version)"

line "${MUTED}\$${R} jake --version"
line "${ROSE}{j}${R} jake ${MUTED}0.5.0${R}"
sleep $PAUSE

# =============================================================================
# HELP OUTPUT
# =============================================================================

section "HELP OUTPUT (jake --help)"

line "${MUTED}\$${R} jake --help"
line ""
line "${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
line ""
line "${BOLD}Usage:${R} jake [options] [recipe] [args...]"
line ""
line "${BOLD}General:${R}"
line "  ${ROSE}-h${R}, ${ROSE}--help${R}              Show this help message"
line "  ${ROSE}-V${R}, ${ROSE}--version${R}           Show version"
line ""
line "${BOLD}Output:${R}"
line "  ${ROSE}-l${R}, ${ROSE}--list${R}              List available recipes"
line "  ${ROSE}-a${R}, ${ROSE}--all${R}               Show all recipes including hidden (use with -l)"
line "      ${ROSE}--short${R}             Output one recipe name per line (for scripting)"
line "  ${ROSE}-s${R}, ${ROSE}--show${R} ${MUTED}RECIPE${R}     Show detailed recipe information"
line "      ${ROSE}--summary${R}           Print recipe names (space-separated, for scripts)"
line ""
line "${BOLD}Execution:${R}"
line "  ${ROSE}-n${R}, ${ROSE}--dry-run${R}           Print commands without executing${MUTED} [env: JAKE_DRY_RUN]${R}"
line "  ${ROSE}-v${R}, ${ROSE}--verbose${R}           Show verbose output (use -vv or -vvv for more)${MUTED} [env: JAKE_VERBOSE]${R}"
line "  ${ROSE}-y${R}, ${ROSE}--yes${R}               Auto-confirm all @confirm prompts${MUTED} [env: JAKE_YES]${R}"
line "  ${ROSE}-w${R}, ${ROSE}--watch${R} ${MUTED}[PATTERN]${R}   Watch files and re-run on changes"
line "  ${ROSE}-j${R}, ${ROSE}--jobs${R} ${MUTED}[N]${R}          Run N recipes in parallel${MUTED} (default: CPU count)${R}${MUTED} [env: JAKE_JOBS]${R}"
line ""
line "${BOLD}File:${R}"
line "  ${ROSE}-f${R}, ${ROSE}--jakefile${R} ${MUTED}FILE${R}   Use specified Jakefile${MUTED} (default: Jakefile)${R}${MUTED} [env: JAKEFILE]${R}"
line "      ${ROSE}--fmt${R}               Format Jakefile"
line "      ${ROSE}--check${R}             Check formatting (exit 1 if changes needed)"
line "      ${ROSE}--dump${R}              Output formatted Jakefile to stdout"
line ""
line "${BOLD}Shell:${R}"
line "      ${ROSE}--completions${R} ${MUTED}[SHELL]${R}  Print shell completion script"
line "      ${ROSE}--install${R}           Install completions to user directory"
line "      ${ROSE}--uninstall${R}         Remove completions and config"
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

section "SINGLE TASK EXECUTION"

line "${MUTED}\$${R} jake lint"
line "${BLUE}→${R} lint"
line ""
line "   ${GREEN}✓${R} lint     ${MUTED}0.21s${R}"
line ""
line "   ${GREEN}Successfully ran 1 task${R}"
line "   ${MUTED}Total time: 0.21s${R}"
line ""
line "${MUTED}Format notes:${R}"
line "  • Arrow header: ${BLUE}→${R} recipe_name"
line "  • TTY mode: animated spinner replaces arrow during execution"
line "  • Blank line between header and completion"
line "  • Completion: 3-space indent + symbol + name + 5 spaces + duration"
sleep $PAUSE

# =============================================================================
# SEQUENTIAL TASKS WITH DEPENDENCIES
# =============================================================================

section "SEQUENTIAL TASKS (with dependencies)"

line "${MUTED}\$${R} jake dev.ci"
line ""

line "   ${GREEN}✓${R} lint      ${MUTED}0.12s${R}"
line ""
line "   ${GREEN}✓${R} test      ${MUTED}3.40s${R}"
line ""
line "   ${GREEN}✓${R} build     ${MUTED}2.10s${R}"
line ""
line "   ${GREEN}✓${R} e2e       ${MUTED}4.70s${R}"
line ""
line "   ${GREEN}Successfully ran 4 tasks${R}"
line "   ${MUTED}Total time: 10.32s${R}"
sleep $PAUSE

# =============================================================================
# PARALLEL EXECUTION
# =============================================================================

section "PARALLEL EXECUTION (-j4)"

line "${MUTED}\$${R} jake -j4 release.all"
line ""
line "${MUTED}Note: Parallel uses same completion format, but tasks run concurrently.${R}"
line "${MUTED}Box-drawing for visual grouping (when multiple tasks run simultaneously):${R}"
line ""
line "   ${MUTED}┌─────────────────────────────────────────────────────┐${R}"
line "   ${MUTED}│${R} ${ROSE}⠋${R} release.linux ${MUTED}│${R} ${ROSE}⠋${R} release.macos ${MUTED}│${R} ${ROSE}⠋${R} release.windows ${MUTED}│${R}"
line "   ${MUTED}└─────────────────────────────────────────────────────┘${R}"
line ""
line "${MUTED}As each completes:${R}"
line ""
line "   ${GREEN}✓${R} release.linux     ${MUTED}3.8s${R}"
line "   ${GREEN}✓${R} release.macos     ${MUTED}3.2s${R}"
line "   ${GREEN}✓${R} release.windows   ${MUTED}4.1s${R}"
line ""
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
# HIDDEN RECIPES (--all)
# =============================================================================

section "HIDDEN RECIPES (jake -la)"

line "${MUTED}\$${R} jake -la"
line "${MUTED}Shows all recipes including hidden ones:${R}"
line ""
line "${MUTED}(hidden):${R}"
line "  ${ROSE}_internal${R}      ${MUTED}Internal helper task${R}"
line "  ${ROSE}_setup${R}         ${MUTED}Setup dependencies${R}"
sleep $PAUSE

# =============================================================================
# WATCH MODE
# =============================================================================

section "WATCH MODE (jake -w dev)"

line "${MUTED}\$${R} jake -w dev"
line ""
line "   ${BLUE}◉${R} ${BOLD}watching${R} ${MUTED}src/**/*.zig${R}"
line ""
line "   ${GREEN}✓${R} dev       ${MUTED}1.82s${R}"
line ""
line "   ${GREEN}Successfully ran 1 task${R}"
line "   ${MUTED}Total time: 1.82s${R}"
line ""
line "   ${YELLOW}⟳${R} ${MUTED}changed${R} src/parser.zig"
line ""
line "   ${GREEN}✓${R} dev       ${MUTED}0.34s${R}"
line ""
line "   ${GREEN}Successfully ran 1 task${R}"
line "   ${MUTED}Total time: 0.34s${R}"
line ""
line "   ${MUTED}watching for changes (ctrl+c to stop)${R}"
sleep $PAUSE

# =============================================================================
# DRY RUN
# =============================================================================

section "DRY RUN (jake -n build)"

line "${MUTED}\$${R} jake -n build"
line "○ build"
line "[dry-run @pre] echo \"Starting build process...\""
line "[dry-run @pre] echo \"Building jake...\""
line "     zig build"
line "[dry-run @post] echo \"Build successful: zig-out/bin/jake\""
line "[dry-run @post] echo \"Build process finished.\""
line ""
line "   1 task would run"
line ""
line "${MUTED}Note: Dry-run format:${R}"
line "  • ${MUTED}○${R} recipe_name (pending symbol, no color on name)"
line "  • [dry-run @pre/post] for hooks"
line "  • Commands indented with 5 spaces"
line "  • Summary: \"N task would run\" (singular/plural)"
sleep $PAUSE

# =============================================================================
# CACHE HIT
# =============================================================================

section "CACHE HIT"

line "${MUTED}\$${R} jake build"
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

line "${BOLD}Up to date:${R}"
line ""
line "${MUTED}\$${R} jake zig-out/bin/jake"
line ""
line "   ${MUTED}—${R} zig-out/bin/jake ${MUTED}(up to date)${R}"
line ""
line "${BOLD}Outdated (verbose mode shows reason):${R}"
line ""
line "${MUTED}\$${R} jake -v zig-out/bin/jake"
line "   ${MUTED}jake: 'zig-out/bin/jake' is up to date${R}"
line ""
line "${MUTED}Or when rebuild needed:${R}"
line "   ${MUTED}sources changed: src/parser.zig (2m ago)${R}"
line ""
line "   ${GREEN}✓${R} zig-out/bin/jake ${MUTED}1.82s${R}"
sleep $PAUSE

# =============================================================================
# CONFIRMATION PROMPT
# =============================================================================

section "CONFIRMATION PROMPT (@confirm)"

line "${MUTED}\$${R} jake editors.vscode-publish"
line ""
line "   ${GREEN}✓${R} editors.vscode-package ${MUTED}1.2s${R}"
line ""
printf "   ${YELLOW}?${R} Publish jake-lang 0.3.0 to marketplace? ${MUTED}[y/N]${R} "
sleep $PAUSE
echo ""
line ""
line "${BOLD}With --yes flag:${R}"
line ""
line "${MUTED}\$${R} jake -y editors.vscode-publish"
line ""
line "   ${GREEN}✓${R} editors.vscode-package ${MUTED}1.2s${R}"
line "   ${MUTED}auto-confirmed: Publish jake-lang 0.3.0 to marketplace?${R}"
line "   ${GREEN}✓${R} editors.vscode-publish ${MUTED}3.4s${R}"
sleep $PAUSE

# =============================================================================
# RECIPE INSPECTION
# =============================================================================

section "RECIPE INSPECTION (jake -s build)"

line "${MUTED}\$${R} jake -s build"
line ""
line "Recipe: build"
line "Type: task"
line "Group: build"
line "Description: Compile jake binary"
line ""
line "Commands:"
line "  @needs needs zig"
line "  @cache cache src/*.zig build.zig build.zig.zon"
line "  zig build"
line ""
line "Hooks:"
line "  @pre: echo \"Building jake...\""
line "  @post: echo \"Build successful: zig-out/bin/jake\""
line ""
line "${MUTED}Note: -s output format:${R}"
line "  • Labels: Recipe, Type, Group, Description, Commands, Hooks"
line "  • Directives shown with @ prefix"
line "  • No coloring in current implementation"
sleep $PAUSE

# =============================================================================
# ERROR: RECIPE NOT FOUND
# =============================================================================

section "ERROR: RECIPE NOT FOUND"

line "${MUTED}\$${R} jake biuld"
line ""
line "${RED}error:${R} recipe 'biuld' not found"
line ""
line "   did you mean: build"
sleep $PAUSE

# =============================================================================
# ERROR: MISSING DEPENDENCY
# =============================================================================

section "ERROR: MISSING DEPENDENCY (@needs)"

line "${MUTED}\$${R} jake perf.tracy"
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
# ERROR: NO JAKEFILE
# =============================================================================

section "ERROR: NO JAKEFILE"

line "${MUTED}\$${R} jake build"
line ""
line "${ROSE}{j}${R} ${RED}error:${R} no Jakefile found"
line ""
line "   ${MUTED}Searched: Jakefile, jakefile, Jakefile.jake${R}"
line "   ${BLUE}hint:${R} run ${ROSE}jake init${R} to create one"
sleep $PAUSE

# =============================================================================
# VERBOSE OUTPUT
# =============================================================================

section "VERBOSE OUTPUT (-v)"

line "${MUTED}Verbose messages use 'jake:' prefix in muted color:${R}"
line ""
line "${MUTED}\$${R} jake -v dev.ci"
line ""
line "   ${MUTED}jake: loading .env from /project/.env${R}"
line "   ${MUTED}jake: loaded 3 variables from .env${R}"
line "   ${MUTED}jake: importing 'jake/build.jake'${R}"
line "   ${MUTED}jake: imported 12 recipes from 'jake/build.jake'${R}"
line "   ${MUTED}jake: resolving dependencies for 'dev.ci'${R}"
line "   ${MUTED}jake: dependency order: lint → test → build → e2e${R}"
line ""
line "   ${GREEN}✓${R} lint      ${MUTED}0.12s${R}"
line "   ${MUTED}jake: executing 'zig fmt --check src/'${R}"
line ""
line "   ${GREEN}✓${R} test      ${MUTED}3.40s${R}"
line "   ${MUTED}jake: executing 'zig build test'${R}"
line ""
line "   ${GREEN}✓${R} build     ${MUTED}2.10s${R}"
line "   ${MUTED}jake: executing 'zig build -Doptimize=ReleaseFast'${R}"
line "   ${MUTED}jake: cache updated for 'build'${R}"
line ""
line "   ${GREEN}✓${R} e2e       ${MUTED}4.70s${R}"
line "   ${MUTED}jake: executing './zig-out/bin/jake -f tests/e2e/Jakefile'${R}"
line ""
line "   ${GREEN}Successfully ran 4 tasks${R}"
line "   ${MUTED}Total time: 10.32s${R}"
sleep $PAUSE

# =============================================================================
# VERBOSE OUTPUT CATEGORIES
# =============================================================================

section "VERBOSE OUTPUT CATEGORIES"

line "${MUTED}All verbose messages use 'jake:' prefix in muted color (#71717a):${R}"
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
line "   ${MUTED}jake: parallel execution with 4 threads${R}"
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
# IGNORED COMMAND (@ignore)
# =============================================================================

section "IGNORED COMMAND (@ignore)"

line "${MUTED}When a command fails but has @ignore:${R}"
line ""
line "   ${YELLOW}[ignored]${R} ${YELLOW}continuing despite command failure${R}"
line "   ${YELLOW}[ignored]${R} ${YELLOW}command failed with error: ExitCodeFailure${R}"
sleep $PAUSE

# =============================================================================
# IMPLEMENTATION MAP
# =============================================================================

section "IMPLEMENTATION MAP"

line "${BOLD}Source files for each output type:${R}"
line ""
line "${ROSE}src/color.zig${R}"
line "  • Brand colors (jake_rose, success_green, etc.)"
line "  • Unicode symbols (✓, ✗, ◉, ⟳, ○, —, ▷, {j})"
line "  • Spinner frames (braille animation)"
line "  • Theme semantic helpers (successSymbol, failureSymbol, etc.)"
line ""
line "${ROSE}src/progress.zig${R}"
line "  • Spinner struct (start, stop, pause, unpause)"
line "  • printCompletionLine() - \"   ✓ name     1.82s\""
line "  • TTY vs non-TTY detection"
line ""
line "${ROSE}src/executor.zig${R}"
line "  • Recipe execution flow"
line "  • printExecutionSummary() - \"Successfully ran N tasks\""
line "  • listRecipes() - \"jake -l\" output"
line "  • showRecipe() - \"jake -s\" output"
line "  • Dry-run output formatting"
line "  • Verbose message output"
line ""
line "${ROSE}src/parallel.zig${R}"
line "  • Parallel execution with thread pool"
line "  • Same completion/summary format as sequential"
line "  • Output synchronization with mutexes"
line ""
line "${ROSE}src/args.zig${R}"
line "  • printHelp() - Help text with categories"
line "  • Error messages for unknown flags"
line "  • Flag suggestions (\"Did you mean...\")"
line ""
line "${ROSE}src/main.zig${R}"
line "  • Version output (\"{j} jake 0.x.x\")"
line "  • No-Jakefile error (with {j} logo)"
line "  • Recipe not found error"
line ""
line "${ROSE}src/watch.zig${R}"
line "  • \"◉ watching\" header"
line "  • \"⟳ changed\" notifications"
line "  • \"watching for changes\" footer"
line ""
line "${ROSE}src/prompt.zig${R}"
line "  • \"? Publish...\" confirmation prompts"
line "  • Auto-confirm messages"
sleep $PAUSE

# =============================================================================
# END
# =============================================================================

section "END"

line "${ROSE}{j}${R} ${MUTED}v5 Specification Complete${R}"
line ""
line "${BOLD}Key implementation details:${R}"
line "  • 3-space indent for status lines"
line "  • 5 spaces between name and duration"
line "  • Blank line before each completion status"
line "  • Spinner pauses during command output (TTY)"
line "  • 80ms animation frame rate"
line "  • Brand colors use 24-bit true color"
line "  • Muted gray (#71717a) for all secondary text"
line "  • Bold group headers in list (not Rose)"
line "  • jake: prefix for all verbose messages"
line ""
