#!/bin/bash
# Jake CLI Design v2 - Minimal & Consistent
# Run: bash prototype/design-v2.sh

# ============================================================================
# COLORS
# ============================================================================

R="\x1b[0m"
BOLD="\x1b[1m"
DIM="\x1b[2m"

# Brand colors (24-bit)
ROSE="\x1b[38;2;244;63;94m"
GREEN="\x1b[38;2;34;197;94m"
RED="\x1b[38;2;239;68;68m"
YELLOW="\x1b[38;2;234;179;8m"
BLUE="\x1b[38;2;96;165;250m"
MUTED="\x1b[38;2;113;113;122m"

# ============================================================================
# DESIGN PRINCIPLES
# ============================================================================
#
# 1. MINIMAL OUTPUT - Only show what's needed
# 2. CONSISTENT SYMBOLS:
#    →  starting a task
#    ✓  success
#    ✗  failure
#    ~  warning/skipped
# 3. COLOR HIERARCHY:
#    ROSE   = task/recipe names (the focus)
#    GREEN  = success states
#    RED    = errors
#    YELLOW = warnings, prompts
#    BLUE   = info, hints
#    MUTED  = secondary info, descriptions, metadata
# 4. NO BRACKETS - cleaner without [task], [file], etc.
# 5. TIMING - always right-aligned or inline, muted
#
# ============================================================================

divider() {
    echo ""
    echo ""
    echo -e "${DIM}$(printf '%90s' | tr ' ' '-')${R}"
    echo ""
    echo ""
}

section() {
    echo -e "${BOLD}$1${R}"
    echo ""
}

prompt() {
    echo -e "${MUTED}\$${R} $1"
}

# ============================================================================
# START
# ============================================================================

echo ""
section "JAKE CLI DESIGN v2 - Minimal & Consistent"

divider

# ============================================================================
# TASK EXECUTION
# ============================================================================

section "TASK EXECUTION"

echo -e "${MUTED}Single task${R}"
echo ""
prompt "jake build"
echo -e "${ROSE}→ build${R}"
echo -e "  cargo build --release"
echo -e "${GREEN}✓ build${R} ${MUTED}2.4s${R}"

echo ""
echo -e "${MUTED}With dependencies${R}"
echo ""
prompt "jake deploy"
echo -e "${ROSE}→ build${R}"
echo -e "  cargo build --release"
echo -e "${GREEN}✓ build${R} ${MUTED}2.4s${R}"
echo -e "${ROSE}→ test${R}"
echo -e "  cargo test"
echo -e "${GREEN}✓ test${R} ${MUTED}1.2s${R}"
echo -e "${ROSE}→ deploy${R}"
echo -e "  ./deploy.sh"
echo -e "${GREEN}✓ deploy${R} ${MUTED}0.8s${R}"

echo ""
echo -e "${MUTED}Quiet mode (no command echo)${R}"
echo ""
prompt "jake build"
echo -e "${ROSE}→ build${R}"
echo -e "${GREEN}✓ build${R} ${MUTED}2.4s${R}"

echo ""
echo -e "${MUTED}Failure${R}"
echo ""
prompt "jake test"
echo -e "${ROSE}→ test${R}"
echo -e "  cargo test"
echo -e "${RED}✗ test${R} ${MUTED}failed${R}"
echo ""
echo -e "${RED}error:${R} command exited with code 1"
echo -e "${MUTED}  Jakefile:12 in task test${R}"

divider

# ============================================================================
# PARALLEL EXECUTION
# ============================================================================

section "PARALLEL EXECUTION"

prompt "jake -j4 all"
echo -e "${ROSE}→ frontend${R}  ${ROSE}→ backend${R}  ${ROSE}→ docs${R}"
echo -e "${GREEN}✓ docs${R} ${MUTED}1.2s${R}"
echo -e "${GREEN}✓ frontend${R} ${MUTED}2.8s${R}"
echo -e "${GREEN}✓ backend${R} ${MUTED}3.1s${R}"
echo ""
echo -e "${GREEN}✓ done${R} ${MUTED}3.1s${R}"

divider

# ============================================================================
# LIST OUTPUT
# ============================================================================

section "LIST OUTPUT (jake -l)"

prompt "jake -l"
echo ""
echo -e "${BOLD}Available recipes:${R}"
echo ""
echo -e "${BOLD}${ROSE}build${R}"
echo -e "  ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "  ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo -e "  ${ROSE}dist/app.js${R}  ${MUTED}Bundle JavaScript (file)${R}"
echo ""
echo -e "${BOLD}${ROSE}test${R}"
echo -e "  ${ROSE}test${R}         ${MUTED}Run all tests${R}"
echo -e "  ${ROSE}test-unit${R}    ${MUTED}Run unit tests only${R}"
echo ""
echo -e "${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo -e "${ROSE}ci${R}             ${MUTED}Run CI pipeline${R}"

echo ""
echo -e "${MUTED}With --all flag (shows hidden)${R}"
echo ""
prompt "jake -l --all"
echo ""
echo -e "${BOLD}Available recipes:${R}"
echo ""
echo -e "${BOLD}${ROSE}build${R}"
echo -e "  ${ROSE}build${R}        ${MUTED}Build the application${R}"
echo -e "  ${ROSE}clean${R}        ${MUTED}Remove build artifacts${R}"
echo ""
echo -e "${ROSE}deploy${R}         ${MUTED}Deploy to production${R}"
echo ""
echo -e "${MUTED}_internal${R}      ${MUTED}Private helper task${R}"
echo -e "${MUTED}_setup${R}         ${MUTED}Setup development environment${R}"

divider

# ============================================================================
# ERRORS
# ============================================================================

section "ERRORS"

echo -e "${MUTED}Recipe not found${R}"
echo ""
prompt "jake buidl"
echo -e "${RED}error:${R} recipe 'buidl' not found"
echo -e "${MUTED}  did you mean: ${R}${ROSE}build${R}${MUTED}?${R}"

echo ""
echo -e "${MUTED}Missing dependency${R}"
echo ""
prompt "jake deploy"
echo -e "${RED}error:${R} required command not found: ${ROSE}helm${R}"
echo -e "${BLUE}hint:${R} brew install helm"

echo ""
echo -e "${MUTED}Missing env var${R}"
echo ""
prompt "jake deploy"
echo -e "${RED}error:${R} missing required environment variables"
echo -e "  ${RED}✗${R} AWS_ACCESS_KEY_ID"
echo -e "  ${RED}✗${R} AWS_SECRET_ACCESS_KEY"

echo ""
echo -e "${MUTED}Syntax error${R}"
echo ""
prompt "jake build"
echo -e "${RED}error:${R} parse error in Jakefile:9"
echo -e "${MUTED}  │${R}"
echo -e "${MUTED}8 │${R} task build"
echo -e "${MUTED}9 │${R}     echo \"missing colon\""
echo -e "${MUTED}  │${R}     ${RED}^${R} expected ':' after task name"

echo ""
echo -e "${MUTED}Cyclic dependency${R}"
echo ""
prompt "jake build"
echo -e "${RED}error:${R} cyclic dependency detected"
echo -e "${MUTED}  ${R}${ROSE}build${R} ${MUTED}→${R} ${ROSE}test${R} ${MUTED}→${R} ${ROSE}build${R}"

divider

# ============================================================================
# WATCH MODE
# ============================================================================

section "WATCH MODE"

prompt "jake -w build"
echo -e "${BLUE}watching${R} ${MUTED}src/**/*.ts${R}"
echo ""
echo -e "${ROSE}→ build${R}"
echo -e "  npm run build"
echo -e "${GREEN}✓ build${R} ${MUTED}0.82s${R}"
echo ""
echo -e "${YELLOW}changed${R} ${MUTED}src/index.ts${R}"
echo -e "${ROSE}→ build${R}"
echo -e "  npm run build"
echo -e "${GREEN}✓ build${R} ${MUTED}0.34s${R}"
echo ""
echo -e "${MUTED}watching for changes... (ctrl+c to stop)${R}"

divider

# ============================================================================
# DRY RUN
# ============================================================================

section "DRY RUN"

prompt "jake -n deploy"
echo -e "${BLUE}dry-run${R}"
echo ""
echo -e "${MUTED}→${R} ${ROSE}build${R}"
echo -e "${MUTED}  cargo build --release${R}"
echo ""
echo -e "${MUTED}→${R} ${ROSE}test${R}"
echo -e "${MUTED}  cargo test${R}"
echo ""
echo -e "${MUTED}→${R} ${ROSE}deploy${R}"
echo -e "${MUTED}  ./deploy.sh production${R}"
echo ""
echo -e "${MUTED}3 tasks would run${R}"

divider

# ============================================================================
# RECIPE INFO
# ============================================================================

section "RECIPE INFO (jake -s)"

prompt "jake -s deploy"
echo ""
echo -e "${ROSE}deploy${R} ${MUTED}— Deploy to production servers${R}"
echo ""
echo -e "${MUTED}group${R}       production"
echo -e "${MUTED}depends${R}     build, test"
echo -e "${MUTED}params${R}      env=${MUTED}\"staging\"${R}  force"
echo -e "${MUTED}needs${R}       kubectl, docker, helm"
echo -e "${MUTED}requires${R}    AWS_ACCESS_KEY_ID"
echo ""
echo -e "${MUTED}commands${R}"
echo "  @confirm \"Deploy to production?\""
echo "  ./scripts/deploy.sh \$env"

divider

# ============================================================================
# FILE TARGETS
# ============================================================================

section "FILE TARGETS"

echo -e "${MUTED}Out of date${R}"
echo ""
prompt "jake dist/bundle.js"
echo -e "${ROSE}→ dist/bundle.js${R} ${MUTED}outdated${R}"
echo -e "  esbuild src/index.ts --bundle"
echo -e "${GREEN}✓ dist/bundle.js${R} ${MUTED}0.42s${R}"

echo ""
echo -e "${MUTED}Up to date${R}"
echo ""
prompt "jake dist/bundle.js"
echo -e "${MUTED}~ dist/bundle.js${R} ${MUTED}up to date${R}"

divider

# ============================================================================
# CONFIRMATION
# ============================================================================

section "CONFIRMATION PROMPTS"

prompt "jake deploy"
echo -e "${ROSE}→ deploy${R}"
echo ""
echo -e "${YELLOW}?${R} Deploy to production? ${MUTED}[y/N]${R} "

divider

# ============================================================================
# VERSION & HELP
# ============================================================================

section "VERSION & HELP"

prompt "jake --version"
echo -e "jake ${MUTED}0.2.0${R}"

echo ""
prompt "jake --help"
echo ""
echo -e "${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e "${MUTED}usage${R}  jake [options] [recipe] [args...]"
echo ""
echo -e "${MUTED}options${R}"
echo -e "  -l, --list       list recipes"
echo -e "  -s, --show       show recipe details"
echo -e "  -n, --dry-run    show what would run"
echo -e "  -w, --watch      watch and re-run"
echo -e "  -j, --jobs N     parallel execution"
echo -e "  -v, --verbose    verbose output"
echo -e "  -y, --yes        skip confirmations"
echo ""
echo -e "${MUTED}examples${R}"
echo -e "  jake build"
echo -e "  jake test --verbose"
echo -e "  jake deploy env=prod"

divider

# ============================================================================
# COMPLETIONS INSTALL
# ============================================================================

section "SHELL COMPLETIONS"

prompt "jake --completions --install"
echo -e "${GREEN}✓${R} installed completions for ${ROSE}zsh${R}"
echo -e "${MUTED}  ~/.zshrc updated${R}"
echo -e "${MUTED}  restart your shell or run: source ~/.zshrc${R}"

divider

# ============================================================================
# VERBOSE MODE
# ============================================================================

section "VERBOSE MODE"

prompt "jake -v build"
echo -e "${ROSE}→ build${R}"
echo -e "${MUTED}  deps: none${R}"
echo -e "${MUTED}  cwd: /Users/dev/project${R}"
echo -e "  cargo build --release"
echo -e "${MUTED}     Compiling myapp v0.1.0${R}"
echo -e "${MUTED}     Finished release [optimized] target(s) in 2.34s${R}"
echo -e "${GREEN}✓ build${R} ${MUTED}2.4s${R}"

echo ""
