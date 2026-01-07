#!/bin/bash
# Jake CLI Design Showcase
# Run: bash prototype/design.sh

# ============================================================================
# COLORS
# ============================================================================

R="\x1b[0m"
BOLD="\x1b[1m"
DIM="\x1b[2m"

# Brand colors (24-bit)
JAKE_ROSE="\x1b[38;2;244;63;94m"
SUCCESS="\x1b[38;2;34;197;94m"
ERROR="\x1b[38;2;239;68;68m"
WARNING="\x1b[38;2;234;179;8m"
INFO="\x1b[38;2;96;165;250m"
MUTED="\x1b[38;2;113;113;122m"

# Potential new colors
ORANGE="\x1b[38;2;249;115;22m"

# Standard ANSI fallback
GRAY="\x1b[90m"

# ============================================================================
# HELPERS
# ============================================================================

divider() {
    echo ""
    echo ""
    echo -e "${DIM}$(printf '%90s' | tr ' ' '-')${R}"
    echo ""
    echo ""
}

section() {
    echo -e "${BOLD}=== $1 ===${R}"
    echo ""
}

prompt() {
    echo -e "${MUTED}\$${R} $1"
}

# ============================================================================
# START
# ============================================================================

echo ""
section "JAKE CLI DESIGN SHOWCASE"
echo -e "${MUTED}All CLI output examples for review${R}"

divider

# ============================================================================
# GROUP COLOR OPTIONS (the original request)
# ============================================================================

section "GROUP/RECIPE COLOR OPTIONS"

echo -e "${MUTED}Option A: Orange for groups${R}"
echo ""
prompt "jake -l"
echo ""
echo -e "${BOLD}Available recipes:${R}"
echo ""
echo -e "${ORANGE}ai:${R}"
echo -e "  ${JAKE_ROSE}ai.validate-docs${R} [task]  ${MUTED}# AI validates README, CHANGELOG, TODO against codebase${R}"
echo -e "  ${JAKE_ROSE}ai.suggest-doc-updates${R} [task]  ${MUTED}# AI suggests documentation updates${R}"
echo ""
echo -e "${ORANGE}dev:${R}"
echo -e "  ${JAKE_ROSE}build${R} [task]  ${MUTED}# Build the project${R}"
echo -e "  ${JAKE_ROSE}test${R} [task]  ${MUTED}# Run all tests${R}"
echo -e "  ${JAKE_ROSE}lint${R} [task]  ${MUTED}# Check code formatting${R}"

echo ""
echo -e "${MUTED}Option B: Dim recipes (muted gray)${R}"
echo ""
prompt "jake -l"
echo ""
echo -e "${BOLD}Available recipes:${R}"
echo ""
echo -e "${JAKE_ROSE}ai:${R}"
echo -e "  ${MUTED}ai.validate-docs${R} [task]  ${MUTED}# AI validates README, CHANGELOG, TODO against codebase${R}"
echo -e "  ${MUTED}ai.suggest-doc-updates${R} [task]  ${MUTED}# AI suggests documentation updates${R}"
echo ""
echo -e "${JAKE_ROSE}dev:${R}"
echo -e "  ${MUTED}build${R} [task]  ${MUTED}# Build the project${R}"
echo -e "  ${MUTED}test${R} [task]  ${MUTED}# Run all tests${R}"
echo -e "  ${MUTED}lint${R} [task]  ${MUTED}# Check code formatting${R}"

echo ""
echo -e "${MUTED}Option C: Bold groups only${R}"
echo ""
prompt "jake -l"
echo ""
echo -e "${BOLD}Available recipes:${R}"
echo ""
echo -e "${BOLD}${JAKE_ROSE}ai:${R}"
echo -e "  ${JAKE_ROSE}ai.validate-docs${R} [task]  ${MUTED}# AI validates README, CHANGELOG, TODO against codebase${R}"
echo -e "  ${JAKE_ROSE}ai.suggest-doc-updates${R} [task]  ${MUTED}# AI suggests documentation updates${R}"
echo ""
echo -e "${BOLD}${JAKE_ROSE}dev:${R}"
echo -e "  ${JAKE_ROSE}build${R} [task]  ${MUTED}# Build the project${R}"
echo -e "  ${JAKE_ROSE}test${R} [task]  ${MUTED}# Run all tests${R}"
echo -e "  ${JAKE_ROSE}lint${R} [task]  ${MUTED}# Check code formatting${R}"

divider

# ============================================================================
# TASK EXECUTION OUTPUT
# ============================================================================

section "TASK EXECUTION OUTPUT"

echo -e "${MUTED}Style A: Arrow prefix${R}"
echo ""
prompt "jake build"
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}build${R}"
echo "  cargo build --release"
echo -e "${SUCCESS}✓${R} ${SUCCESS}build${R} ${MUTED}(2.4s)${R}"

echo ""
echo -e "${MUTED}Style B: Bracket prefix${R}"
echo ""
prompt "jake build"
echo -e "${MUTED}[${R}${JAKE_ROSE}build${R}${MUTED}]${R} cargo build --release"
echo -e "${MUTED}[${R}${SUCCESS}done${R}${MUTED}]${R} build ${MUTED}(2.4s)${R}"

echo ""
echo -e "${MUTED}Style C: Double arrow${R}"
echo ""
prompt "jake build"
echo -e "${JAKE_ROSE}»${R} ${JAKE_ROSE}build${R}"
echo "  cargo build --release"
echo -e "${SUCCESS}✓${R} build ${MUTED}2.4s${R}"

echo ""
echo -e "${MUTED}Style D: Minimal${R}"
echo ""
prompt "jake build"
echo -e "${JAKE_ROSE}build:${R}"
echo "  cargo build --release"
echo -e "  ${SUCCESS}done${R} ${MUTED}(2.4s)${R}"

divider

# ============================================================================
# PARALLEL EXECUTION OUTPUT
# ============================================================================

section "PARALLEL EXECUTION OUTPUT"

echo -e "${MUTED}Style A: Parallel indicators${R}"
echo ""
prompt "jake -j4 all"
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}frontend${R} ${MUTED}│${R} ${JAKE_ROSE}→${R} ${JAKE_ROSE}backend${R} ${MUTED}│${R} ${JAKE_ROSE}→${R} ${JAKE_ROSE}docs${R}"
echo -e "${SUCCESS}✓${R} docs ${MUTED}(1.2s)${R}"
echo -e "${SUCCESS}✓${R} frontend ${MUTED}(2.8s)${R}"
echo -e "${SUCCESS}✓${R} backend ${MUTED}(3.1s)${R}"
echo -e "${SUCCESS}✓${R} all ${MUTED}(3.1s total)${R}"

echo ""
echo -e "${MUTED}Style B: With progress${R}"
echo ""
prompt "jake -j4 all"
echo -e "${JAKE_ROSE}⠋${R} frontend  ${JAKE_ROSE}⠋${R} backend  ${JAKE_ROSE}⠋${R} docs"
echo -e "${SUCCESS}✓${R} docs      ${JAKE_ROSE}⠙${R} frontend ${JAKE_ROSE}⠙${R} backend"
echo -e "${SUCCESS}✓${R} docs      ${SUCCESS}✓${R} frontend ${JAKE_ROSE}⠹${R} backend"
echo -e "${SUCCESS}✓${R} docs      ${SUCCESS}✓${R} frontend ${SUCCESS}✓${R} backend"
echo -e "${SUCCESS}✓${R} ${SUCCESS}all${R} ${MUTED}(3.1s)${R}"

divider

# ============================================================================
# LIST OUTPUT (jake -l)
# ============================================================================

section "LIST OUTPUT (jake -l)"

echo -e "${MUTED}Style A: Grouped with type badges${R}"
echo ""
prompt "jake -l"
echo ""
echo -e "${JAKE_ROSE}build${R}"
echo -e "  ${JAKE_ROSE}build${R}       ${MUTED}[task]${R}  Build the application"
echo -e "  ${JAKE_ROSE}dist/app.js${R} ${MUTED}[file]${R}  Bundle JavaScript"
echo -e "  ${JAKE_ROSE}clean${R}       ${MUTED}[task]${R}  Remove build artifacts"
echo ""
echo -e "${JAKE_ROSE}test${R}"
echo -e "  ${JAKE_ROSE}test${R}        ${MUTED}[task]${R}  Run all tests"
echo -e "  ${JAKE_ROSE}test-unit${R}   ${MUTED}[task]${R}  Run unit tests only"
echo ""
echo -e "${MUTED}5 recipes available${R}"

echo ""
echo -e "${MUTED}Style B: Compact table${R}"
echo ""
prompt "jake -l"
echo ""
echo -e "${MUTED}RECIPE        TYPE  DESCRIPTION${R}"
echo -e "${JAKE_ROSE}build${R}         task  Build the application"
echo -e "${JAKE_ROSE}dist/app.js${R}   file  Bundle JavaScript"
echo -e "${JAKE_ROSE}clean${R}         task  Remove build artifacts"
echo -e "${JAKE_ROSE}test${R}          task  Run all tests"
echo -e "${JAKE_ROSE}deploy${R}        task  Deploy to production"

echo ""
echo -e "${MUTED}Style C: Tree with deps${R}"
echo ""
prompt "jake -l"
echo ""
echo -e "${JAKE_ROSE}build${R} ${MUTED}- Build the application${R}"
echo -e "${JAKE_ROSE}test${R} ${MUTED}- Run all tests${R}"
echo -e "  ${MUTED}└─ depends on:${R} ${INFO}build${R}"
echo -e "${JAKE_ROSE}deploy${R} ${MUTED}- Deploy to production${R}"
echo -e "  ${MUTED}└─ depends on:${R} ${INFO}build${R}, ${INFO}test${R}"
echo -e "${JAKE_ROSE}clean${R} ${MUTED}- Remove build artifacts${R}"

echo ""
echo -e "${MUTED}Style D: Minimal list${R}"
echo ""
prompt "jake -l"
echo ""
echo -e "${JAKE_ROSE}build${R}        Build the application"
echo -e "${JAKE_ROSE}test${R}         Run all tests"
echo -e "${JAKE_ROSE}deploy${R}       Deploy to production"
echo -e "${JAKE_ROSE}clean${R}        Remove build artifacts"
echo -e "${JAKE_ROSE}dist/app.js${R}  ${MUTED}(file target)${R}"

divider

# ============================================================================
# ERROR MESSAGES
# ============================================================================

section "ERROR MESSAGES"

echo -e "${MUTED}Recipe not found (with suggestion)${R}"
echo ""
prompt "jake buidl"
echo -e "${ERROR}error:${R} Recipe '${JAKE_ROSE}buidl${R}' not found"
echo ""
echo -e "${MUTED}Did you mean:${R} ${JAKE_ROSE}build${R}?"
echo ""
echo -e "${MUTED}Run 'jake -l' to see available recipes.${R}"

echo ""
echo -e "${MUTED}Command failed${R}"
echo ""
prompt "jake test"
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}test${R}"
echo "  npm test"
echo -e "${ERROR}✗${R} ${ERROR}test${R} ${MUTED}(failed)${R}"
echo ""
echo -e "${ERROR}error:${R} Command exited with code ${JAKE_ROSE}1${R}"
echo -e "  ${MUTED}at${R} Jakefile:12"
echo -e "  ${MUTED}in${R} task ${JAKE_ROSE}test${R}"

echo ""
echo -e "${MUTED}Missing @needs dependency${R}"
echo ""
prompt "jake deploy"
echo -e "${ERROR}error:${R} Required command not found: ${JAKE_ROSE}helm${R}"
echo ""
echo -e "${INFO}hint:${R} Install with: brew install helm"
echo -e "${MUTED}      or run: jake toolchain.install${R}"

echo ""
echo -e "${MUTED}Missing @require env var${R}"
echo ""
prompt "jake deploy"
echo -e "${ERROR}error:${R} Required environment variable not set"
echo ""
echo -e "  ${JAKE_ROSE}AWS_ACCESS_KEY_ID${R}       ${ERROR}✗${R} missing"
echo -e "  ${JAKE_ROSE}AWS_SECRET_ACCESS_KEY${R}   ${ERROR}✗${R} missing"
echo ""
echo -e "${MUTED}Set these variables or add them to .env${R}"

echo ""
echo -e "${MUTED}Syntax error${R}"
echo ""
prompt "jake build"
echo -e "${ERROR}error:${R} Parse error in Jakefile"
echo ""
echo -e "  ${INFO}8${R} │ task build"
echo -e "  ${ERROR}9${R} │     echo \"missing colon\""
echo -e "    │ ${ERROR}^^^^${R} expected ':' after task name"
echo ""
echo -e "${MUTED}Fix the syntax error and try again.${R}"

echo ""
echo -e "${MUTED}Cyclic dependency${R}"
echo ""
prompt "jake build"
echo -e "${ERROR}error:${R} Cyclic dependency detected"
echo ""
echo -e "  ${JAKE_ROSE}build${R} → ${JAKE_ROSE}test${R} → ${JAKE_ROSE}build${R}"
echo -e "  ${ERROR}^^^^^^^^^^^^^^^^^^^^^^^${R}"
echo ""
echo -e "${MUTED}Remove circular dependencies.${R}"

divider

# ============================================================================
# WATCH MODE OUTPUT
# ============================================================================

section "WATCH MODE OUTPUT"

echo -e "${MUTED}Style A: Emoji indicator${R}"
echo ""
prompt "jake -w build"
echo -e "${INFO}👀${R} Watching ${MUTED}src/**/*.ts${R}"
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}build${R}"
echo "  npm run build"
echo -e "${SUCCESS}✓${R} build ${MUTED}(0.82s)${R}"
echo ""
echo -e "${WARNING}Changed:${R} src/index.ts"
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}build${R}"
echo "  npm run build"
echo -e "${SUCCESS}✓${R} build ${MUTED}(0.34s)${R}"
echo ""
echo -e "${MUTED}Press Ctrl+C to stop watching${R}"

echo ""
echo -e "${MUTED}Style B: Text indicator${R}"
echo ""
prompt "jake -w build"
echo -e "${INFO}[watch]${R} Monitoring ${MUTED}src/**/*.ts${R}"
echo -e "${JAKE_ROSE}[build]${R} npm run build"
echo -e "${SUCCESS}[done]${R}  0.82s"
echo ""
echo -e "${WARNING}[change]${R} src/index.ts"
echo -e "${JAKE_ROSE}[build]${R} npm run build"
echo -e "${SUCCESS}[done]${R}  0.34s"
echo ""
echo -e "${MUTED}[watch] Press q to quit${R}"

divider

# ============================================================================
# DRY RUN OUTPUT
# ============================================================================

section "DRY RUN OUTPUT (jake -n)"

echo -e "${MUTED}Style A: Would run prefix${R}"
echo ""
prompt "jake -n deploy"
echo -e "${INFO}[dry-run]${R} Would execute:"
echo ""
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}build${R}"
echo -e "  ${MUTED}would run:${R} cargo build --release"
echo ""
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}test${R}"
echo -e "  ${MUTED}would run:${R} cargo test"
echo ""
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}deploy${R}"
echo -e "  ${MUTED}would run:${R} ./deploy.sh production"
echo ""
echo -e "${MUTED}3 tasks would run (not executed)${R}"

echo ""
echo -e "${MUTED}Style B: Ghost commands${R}"
echo ""
prompt "jake -n deploy"
echo ""
echo -e "${JAKE_ROSE}build${R} ${MUTED}(dry-run)${R}"
echo -e "  ${MUTED}\$ cargo build --release${R}"
echo ""
echo -e "${JAKE_ROSE}test${R} ${MUTED}(dry-run)${R}"
echo -e "  ${MUTED}\$ cargo test${R}"
echo ""
echo -e "${JAKE_ROSE}deploy${R} ${MUTED}(dry-run)${R}"
echo -e "  ${MUTED}\$ ./deploy.sh production${R}"

divider

# ============================================================================
# RECIPE INSPECTION
# ============================================================================

section "RECIPE INSPECTION (jake -s)"

echo -e "${MUTED}Style A: Structured metadata${R}"
echo ""
prompt "jake -s deploy"
echo ""
echo -e "${JAKE_ROSE}Recipe:${R} deploy"
echo -e "${MUTED}Type:${R}    task"
echo -e "${MUTED}Group:${R}   production"
echo -e "${MUTED}Desc:${R}    Deploy to production servers"
echo -e "${MUTED}Default:${R} no"
echo ""
echo -e "${MUTED}Dependencies:${R}"
echo -e "  ${INFO}build${R}, ${INFO}test${R}"
echo ""
echo -e "${MUTED}Parameters:${R}"
echo -e "  ${JAKE_ROSE}env${R} ${MUTED}(default: \"staging\")${R}"
echo -e "  ${JAKE_ROSE}force${R} ${MUTED}(required)${R}"
echo ""
echo -e "${MUTED}Validation:${R}"
echo -e "  ${SUCCESS}@needs${R} kubectl, docker, helm"
echo -e "  ${SUCCESS}@require${R} AWS_ACCESS_KEY_ID"
echo ""
echo -e "${MUTED}Commands:${R}"
echo "  @confirm \"Deploy to production?\""
echo "  ./scripts/deploy.sh \$env"

echo ""
echo -e "${MUTED}Style B: Compact view${R}"
echo ""
prompt "jake -s deploy"
echo ""
echo -e "${JAKE_ROSE}deploy${R} ${MUTED}[task]${R} ${MUTED}production${R}"
echo -e "${MUTED}│${R} Deploy to production servers"
echo -e "${MUTED}│${R}"
echo -e "${MUTED}├─${R} ${MUTED}deps:${R}    build → test"
echo -e "${MUTED}├─${R} ${MUTED}params:${R}  env=${MUTED}\"staging\"${R}, force"
echo -e "${MUTED}├─${R} ${MUTED}needs:${R}   kubectl, docker, helm"
echo -e "${MUTED}└─${R} ${MUTED}require:${R} AWS_ACCESS_KEY_ID"
echo ""
echo -e "${MUTED}commands:${R}"
echo "  @confirm \"Deploy to production?\""
echo "  ./scripts/deploy.sh \$env"

divider

# ============================================================================
# FILE TARGET STATUS
# ============================================================================

section "FILE TARGET STATUS"

echo -e "${MUTED}Needs rebuild${R}"
echo ""
prompt "jake dist/bundle.js"
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}dist/bundle.js${R} ${MUTED}(out of date)${R}"
echo -e "  ${MUTED}changed:${R} src/index.ts ${MUTED}(2m ago)${R}"
echo -e "  ${MUTED}changed:${R} src/utils.ts ${MUTED}(5m ago)${R}"
echo "  esbuild src/index.ts --bundle"
echo -e "${SUCCESS}✓${R} dist/bundle.js ${MUTED}(0.42s)${R}"

echo ""
echo -e "${MUTED}Up to date${R}"
echo ""
prompt "jake dist/bundle.js"
echo -e "${MUTED}⊘${R} ${MUTED}dist/bundle.js${R} ${MUTED}(up to date)${R}"
echo -e "  ${MUTED}last built: 2m ago${R}"
echo -e "  ${MUTED}no sources changed${R}"

divider

# ============================================================================
# CONFIRMATION PROMPTS
# ============================================================================

section "CONFIRMATION PROMPTS"

echo -e "${MUTED}Style A: Y/n prompt${R}"
echo ""
prompt "jake deploy"
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}deploy${R}"
echo ""
echo -e "${WARNING}?${R} Deploy to production? ${MUTED}[Y/n]${R} █"

echo ""
echo -e "${MUTED}Style B: Arrow select${R}"
echo ""
prompt "jake deploy"
echo -e "${JAKE_ROSE}→${R} ${JAKE_ROSE}deploy${R}"
echo ""
echo -e "${WARNING}?${R} Deploy to production?"
echo -e "  ${JAKE_ROSE}❯${R} ${SUCCESS}Yes, deploy${R}"
echo -e "    ${MUTED}No, cancel${R}"

divider

# ============================================================================
# VERSION & HELP
# ============================================================================

section "VERSION & BRANDING"

echo -e "${MUTED}jake --version${R}"
echo ""
prompt "jake --version"
echo -e "${JAKE_ROSE}{j}${R} jake ${MUTED}0.2.0${R}"
echo -e "${MUTED}A modern command runner with dependency tracking${R}"

echo ""
echo -e "${MUTED}jake --help (header)${R}"
echo ""
prompt "jake --help"
echo ""
echo -e "${JAKE_ROSE}{j}${R} ${BOLD}jake${R} - Modern command running"
echo -e "${MUTED}The best of Make and Just, combined.${R}"
echo ""
echo -e "${MUTED}USAGE:${R}"
echo -e "  jake ${MUTED}[OPTIONS]${R} ${MUTED}[RECIPE]${R} ${MUTED}[ARGS...]${R}"
echo ""
echo -e "${MUTED}OPTIONS:${R}"
echo -e "  ${JAKE_ROSE}-l${R}, ${JAKE_ROSE}--list${R}      List available recipes"
echo -e "  ${JAKE_ROSE}-n${R}, ${JAKE_ROSE}--dry-run${R}   Show what would run"
echo -e "  ${JAKE_ROSE}-w${R}, ${JAKE_ROSE}--watch${R}     Watch and re-run"
echo -e "  ${JAKE_ROSE}-j${R}, ${JAKE_ROSE}--jobs${R} ${MUTED}N${R}    Parallel jobs"

divider

# ============================================================================
# CURRENT IMPLEMENTATION (for comparison)
# ============================================================================

section "CURRENT IMPLEMENTATION (for comparison)"

echo -e "${MUTED}This is approximately what jake -l looks like now:${R}"
echo ""
prompt "jake -l"
echo -e "${BOLD}Available recipes:${R}"
echo ""
echo -e "${JAKE_ROSE}ai:${R}"
echo -e "  ${JAKE_ROSE}ai.validate-docs${R} [task]  ${MUTED}# AI validates README, CHANGELOG, TODO against codebase${R}"
echo -e "  ${JAKE_ROSE}ai.suggest-doc-updates${R} [task]  ${MUTED}# AI suggests documentation updates${R}"
echo ""
echo -e "${JAKE_ROSE}dev:${R}"
echo -e "  ${JAKE_ROSE}build${R} [task]  ${MUTED}# Build the project${R}"
echo -e "  ${JAKE_ROSE}test${R} [task]  ${MUTED}# Run all tests${R}"
echo ""
echo -e "${MUTED}(hidden):${R}"
echo -e "  ${JAKE_ROSE}_internal${R} [task]  ${MUTED}# Private task${R}"

echo ""
