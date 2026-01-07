#!/bin/bash
# =============================================================================
# Jake CLI Output Design Recommendations
# =============================================================================
# Author: Amp Agent
# Based on: Brand guidelines, codebase analysis, and CLI best practices research
#
# Run: bash prototype/amp-recommendations.sh
# =============================================================================

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

divider() {
    echo ""
    echo -e "${DIM}$(printf '%90s' | tr ' ' '─')${R}"
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

note() {
    echo -e "${BLUE}ℹ${R} $1"
}

# =============================================================================
# EXECUTIVE SUMMARY
# =============================================================================

echo ""
echo -e "${ROSE}{j}${R} ${BOLD}JAKE CLI OUTPUT DESIGN RECOMMENDATIONS${R}"
echo -e "${MUTED}Based on brand guidelines, existing prototypes, and CLI best practices${R}"

divider

section "🎯 RECOMMENDATION SUMMARY"

echo -e "${BOLD}Recommended Style:${R} ${ROSE}Design v2 (Minimal & Consistent)${R} with refinements"
echo ""
echo "Key principles:"
echo -e "  ${GREEN}1.${R} Arrow prefix style (→) for task execution"
echo -e "  ${GREEN}2.${R} Minimal, no-bracket output format"
echo -e "  ${GREEN}3.${R} Consistent symbol vocabulary"
echo -e "  ${GREEN}4.${R} Rose for recipes, muted for metadata"
echo -e "  ${GREEN}5.${R} Bold for groups, regular for items"
echo -e "  ${GREEN}6.${R} ${ROSE}{j}${R} logo in version/help and header contexts"

divider

# =============================================================================
# {j} LOGO USAGE
# =============================================================================

section "${ROSE}{j}${R} LOGO PLACEMENT"

echo "The {j} mark should appear in:"
echo ""
echo -e "  ${GREEN}✓${R} ${BOLD}--version output${R} — brand identity"
echo -e "  ${GREEN}✓${R} ${BOLD}--help header${R} — tool recognition"
echo -e "  ${GREEN}✓${R} ${BOLD}First-run welcome${R} — onboarding"
echo -e "  ${GREEN}✓${R} ${BOLD}Error header (optional)${R} — when Jakefile not found"
echo ""
echo -e "  ${RED}✗${R} ${MUTED}Task execution output${R} — too noisy, distracting"
echo -e "  ${RED}✗${R} ${MUTED}Recipe list output${R} — clutters the list"
echo -e "  ${RED}✗${R} ${MUTED}Every line of output${R} — overwhelming"

divider

# =============================================================================
# DESIGN PHILOSOPHY
# =============================================================================

section "📐 DESIGN PHILOSOPHY"

echo "Based on research of cargo, just, npm, and modern CLI tools:"
echo ""
echo -e "${BOLD}1. Fail Loudly, Succeed Quietly${R}"
echo -e "   ${MUTED}Minimize output on success; be verbose on failure${R}"
echo ""
echo -e "${BOLD}2. Consistent Visual Vocabulary${R}"
echo -e "   ${MUTED}Same symbols mean the same thing everywhere${R}"
echo -e "   → = starting    ✓ = success    ✗ = failure    ~ = skipped"
echo ""
echo -e "${BOLD}3. Hierarchy Through Color, Not Decoration${R}"
echo -e "   ${MUTED}Avoid brackets [like this] - use color and indentation${R}"
echo ""
echo -e "${BOLD}4. Parseable When Piped${R}"
echo -e "   ${MUTED}Output should be machine-readable when colors disabled${R}"
echo ""
echo -e "${BOLD}5. Respect Terminal Standards${R}"
echo -e "   ${MUTED}NO_COLOR, CLICOLOR, true color detection${R}"

divider

# =============================================================================
# RECOMMENDED: VERSION & HELP (with {j} logo)
# =============================================================================

section "✅ RECOMMENDED: Version & Help ${MUTED}(with {j} logo)${R}"

echo -e "${MUTED}The {j} logo appears here for brand recognition:${R}"
echo ""

prompt "jake --version"
echo -e "${ROSE}{j}${R} jake ${MUTED}0.3.0${R}"

echo ""
prompt "jake --help"
echo ""
echo -e "${ROSE}{j}${R} ${BOLD}jake${R} ${MUTED}— modern command runner${R}"
echo ""
echo -e "${MUTED}usage${R}  jake [options] [recipe] [args...]"
echo ""
echo -e "${MUTED}options${R}"
echo -e "  ${ROSE}-l${R}, ${ROSE}--list${R}       list available recipes"
echo -e "  ${ROSE}-s${R}, ${ROSE}--show${R}       show recipe details"
echo -e "  ${ROSE}-n${R}, ${ROSE}--dry-run${R}    show what would run"
echo -e "  ${ROSE}-w${R}, ${ROSE}--watch${R}      watch files and re-run"
echo -e "  ${ROSE}-j${R}, ${ROSE}--jobs${R} N     run N tasks in parallel"
echo -e "  ${ROSE}-q${R}, ${ROSE}--quiet${R}      suppress command echo"
echo -e "  ${ROSE}-v${R}, ${ROSE}--verbose${R}    show additional details"
echo ""
echo -e "${MUTED}examples${R}"
echo -e "  jake build              ${MUTED}Run the build recipe${R}"
echo -e "  jake test -v            ${MUTED}Run tests with verbose output${R}"
echo -e "  jake release.all -j4    ${MUTED}Build all releases in parallel${R}"
echo -e "  jake deploy env=prod    ${MUTED}Deploy with parameter${R}"

echo ""
echo -e "${MUTED}No Jakefile found (with {j} logo):${R}"
echo ""

prompt "jake build"
echo -e "${ROSE}{j}${R} ${RED}error:${R} no Jakefile found in current directory"
echo -e "   ${MUTED}Create a Jakefile or run${R} ${ROSE}jake --init${R} ${MUTED}to get started${R}"

divider

# =============================================================================
# RECOMMENDED: TASK EXECUTION
# =============================================================================

section "✅ RECOMMENDED: Task Execution"

echo -e "${MUTED}Why this style:${R}"
echo -e "  - Arrow (→) is universally understood as 'starting'"
echo -e "  - Recipe name in Rose creates brand recognition"
echo -e "  - Timing is muted (secondary info)"
echo -e "  - Commands are indented 2 spaces (clear hierarchy)"
echo ""

prompt "jake build"
echo -e "${ROSE}→ build${R}"
echo -e "  zig build"
echo -e "${GREEN}✓ build${R} ${MUTED}1.8s${R}"

echo ""
echo -e "${MUTED}With dependencies (realistic):${R}"
echo ""

prompt "jake dev.ci"
echo -e "${ROSE}→ lint${R}"
echo -e "  zig fmt --check src/"
echo -e "${GREEN}✓ lint${R} ${MUTED}0.12s${R}"
echo -e "${ROSE}→ test${R}"
echo -e "  zig build test"
echo -e "${GREEN}✓ test${R} ${MUTED}3.4s${R}"
echo -e "${ROSE}→ build${R}"
echo -e "  zig build -Doptimize=ReleaseFast"
echo -e "${GREEN}✓ build${R} ${MUTED}2.1s${R}"
echo -e "${ROSE}→ e2e${R}"
echo -e "  ./zig-out/bin/jake -f tests/e2e/Jakefile test-all"
echo -e "${GREEN}✓ e2e${R} ${MUTED}4.7s${R}"
echo ""
echo -e "${GREEN}✓ dev.ci${R} ${MUTED}10.3s${R}"

echo ""
echo -e "${MUTED}Release build:${R}"
echo ""

prompt "jake release.build"
echo -e "${ROSE}→ release.build${R}"
echo -e "  zig build -Doptimize=ReleaseFast -Dstrip=true"
echo -e "${MUTED}  Binary: zig-out/bin/jake (2.1MB)${R}"
echo -e "${GREEN}✓ release.build${R} ${MUTED}4.2s${R}"

echo ""
echo -e "${MUTED}On failure:${R}"
echo ""

prompt "jake test"
echo -e "${ROSE}→ test${R}"
echo -e "  zig build test"
echo -e "${MUTED}  src/parser.zig:142:25: error: expected ')' after argument${R}"
echo -e "${RED}✗ test${R} ${MUTED}failed${R}"
echo ""
echo -e "${RED}error:${R} command exited with code 1"
echo -e "${MUTED}  Jakefile:47 in task test${R}"

divider

# =============================================================================
# RECOMMENDED: LIST OUTPUT
# =============================================================================

section "✅ RECOMMENDED: List Output (jake -l)"

echo -e "${MUTED}Why this style:${R}"
echo -e "  - Groups are bold Rose (hierarchy through weight)"
echo -e "  - Recipes in regular Rose (consistent branding)"
echo -e "  - Descriptions muted (secondary info)"
echo -e "  - NO type badges [task] - cleaner, 95% are tasks anyway"
echo -e "  - File targets noted inline where relevant"
echo ""

prompt "jake -l"
echo ""
echo -e "${BOLD}Available recipes:${R}"
echo ""
echo -e "${BOLD}${ROSE}build${R}"
echo -e "  ${ROSE}build${R}              ${MUTED}Compile jake binary${R}"
echo -e "  ${ROSE}build-release${R}      ${MUTED}Optimized release build${R}"
echo -e "  ${ROSE}clean${R}              ${MUTED}Remove build artifacts${R}"
echo -e "  ${ROSE}rebuild${R}            ${MUTED}Clean and rebuild from scratch${R}"
echo ""
echo -e "${BOLD}${ROSE}test${R}"
echo -e "  ${ROSE}test${R}               ${MUTED}Run all tests${R}"
echo -e "  ${ROSE}lint${R}               ${MUTED}Check code formatting${R}"
echo -e "  ${ROSE}format${R}             ${MUTED}Auto-format source code${R}"
echo -e "  ${ROSE}e2e${R}                ${MUTED}Run end-to-end tests${R}"
echo -e "  ${ROSE}coverage${R}           ${MUTED}Run tests with code coverage${R}"
echo ""
echo -e "${BOLD}${ROSE}dev${R}"
echo -e "  ${ROSE}dev${R}                ${MUTED}Development build with watch support${R}"
echo -e "  ${ROSE}dev.all${R}            ${MUTED}Build and test everything${R}"
echo -e "  ${ROSE}dev.ci${R}             ${MUTED}Run all CI checks${R}"
echo -e "  ${ROSE}dev.check${R}          ${MUTED}Quick pre-commit checks${R}"
echo ""
echo -e "${BOLD}${ROSE}release${R}"
echo -e "  ${ROSE}release.build${R}      ${MUTED}Build optimized release for current platform${R}"
echo -e "  ${ROSE}release.all${R}        ${MUTED}Build for all platforms${R}"
echo -e "  ${ROSE}release.checksums${R}  ${MUTED}Generate SHA256 checksums for all builds${R}"
echo ""
echo -e "${BOLD}${ROSE}editors${R}"
echo -e "  ${ROSE}editors.vscode-install${R}   ${MUTED}Install VS Code extension locally${R}"
echo -e "  ${ROSE}editors.neovim-install${R}   ${MUTED}Install Neovim syntax files${R}"
echo -e "  ${ROSE}editors.all${R}              ${MUTED}Build all editor extensions${R}"
echo ""
echo -e "${ROSE}install${R}            ${MUTED}Install jake to ~/.local/bin${R}"
echo ""
echo -e "${MUTED}98 recipes (14 groups) • run${R} ${ROSE}jake -la${R} ${MUTED}to show hidden${R}"

echo ""
echo -e "${MUTED}With search filter:${R}"
echo ""

prompt "jake -l vscode"
echo ""
echo -e "${BOLD}Matching recipes:${R}"
echo ""
echo -e "  ${ROSE}editors.vscode-package${R}   ${MUTED}Package VS Code extension as .vsix${R}"
echo -e "  ${ROSE}editors.vscode-install${R}   ${MUTED}Install VS Code extension locally${R}"
echo -e "  ${ROSE}editors.vscode-publish${R}   ${MUTED}Publish VS Code extension to marketplace${R}"
echo -e "  ${ROSE}editors.vscode-dev${R}       ${MUTED}Package, install, and validate extension${R}"
echo -e "  ${ROSE}editors.vscode-run${R}       ${MUTED}Launch VS Code with extension loaded${R}"
echo ""
echo -e "${MUTED}5 recipes matching 'vscode'${R}"

divider

# =============================================================================
# RECOMMENDED: ERROR MESSAGES
# =============================================================================

section "✅ RECOMMENDED: Error Messages"

echo -e "${MUTED}Why this style:${R}"
echo -e "  - 'error:' prefix in red (consistent with cargo, gcc)"
echo -e "  - Recipe names stay Rose even in errors"
echo -e "  - Suggestions are muted with Rose highlight"
echo -e "  - Hints use blue for actionable info"
echo ""

echo -e "${MUTED}Recipe not found (with typo suggestion):${R}"
echo ""
prompt "jake buld"
echo -e "${RED}error:${R} recipe 'buld' not found"
echo -e "${MUTED}  did you mean: ${R}${ROSE}build${R}${MUTED}?${R}"

echo ""
prompt "jake editor.vscode"
echo -e "${RED}error:${R} recipe 'editor.vscode' not found"
echo -e "${MUTED}  did you mean: ${R}${ROSE}editors.vscode-install${R}${MUTED}?${R}"

echo ""
echo -e "${MUTED}Missing dependency (@needs):${R}"
echo ""
prompt "jake perf.tracy"
echo -e "${RED}error:${R} required command not found: ${ROSE}tracy${R}"
echo -e "${BLUE}hint:${R} brew install tracy"

echo ""
echo -e "${MUTED}Missing env var (@require):${R}"
echo ""
prompt "jake editors.vscode-publish"
echo -e "${RED}error:${R} missing required environment variables"
echo -e "  ${RED}✗${R} VSCE_PAT"
echo -e "${BLUE}hint:${R} export VSCE_PAT=your-token or add to .env"

echo ""
echo -e "${MUTED}Syntax error (Rust/cargo style):${R}"
echo ""
prompt "jake build"
echo -e "${RED}error:${R} parse error in Jakefile:24"
echo -e "${MUTED}   │${R}"
echo -e "${MUTED}23 │${R} task build"
echo -e "${MUTED}24 │${R}     zig build --release"
echo -e "${MUTED}   │${R}     ${RED}^${R} expected ':' after task name"

echo ""
echo -e "${MUTED}Cyclic dependency:${R}"
echo ""
prompt "jake release.all"
echo -e "${RED}error:${R} cyclic dependency detected"
echo -e "${MUTED}  ${R}${ROSE}release.all${R} ${MUTED}→${R} ${ROSE}release.build${R} ${MUTED}→${R} ${ROSE}release.all${R}"

echo ""
echo -e "${MUTED}Parameter validation:${R}"
echo ""
prompt "jake release.build platform=windoze"
echo -e "${RED}error:${R} invalid value for parameter ${ROSE}platform${R}"
echo -e "${MUTED}  expected one of: linux, macos, windows${R}"
echo -e "${MUTED}  got: windoze${R}"

divider

# =============================================================================
# RECOMMENDED: WATCH MODE
# =============================================================================

section "✅ RECOMMENDED: Watch Mode"

echo -e "${MUTED}Why this style:${R}"
echo -e "  - 'watching' label in blue (info/state indicator)"
echo -e "  - 'changed' in yellow (attention, not error)"
echo -e "  - Pattern in muted (configuration detail)"
echo -e "  - No emoji - professional, cross-platform"
echo ""

prompt "jake -w dev"
echo -e "${BLUE}watching${R} ${MUTED}src/**/*.zig${R}"
echo ""
echo -e "${ROSE}→ dev${R}"
echo -e "  zig build"
echo -e "${GREEN}✓ dev${R} ${MUTED}1.82s${R}"
echo ""
echo -e "${YELLOW}changed${R} ${MUTED}src/parser.zig${R}"
echo -e "${ROSE}→ dev${R}"
echo -e "  zig build"
echo -e "${GREEN}✓ dev${R} ${MUTED}0.34s${R}"
echo ""
echo -e "${YELLOW}changed${R} ${MUTED}src/lexer.zig, src/executor.zig${R}"
echo -e "${ROSE}→ dev${R}"
echo -e "  zig build"
echo -e "${GREEN}✓ dev${R} ${MUTED}0.41s${R}"
echo ""
echo -e "${MUTED}watching for changes... (ctrl+c to stop)${R}"

divider

# =============================================================================
# RECOMMENDED: DRY RUN
# =============================================================================

section "✅ RECOMMENDED: Dry Run (jake -n)"

echo -e "${MUTED}Why this style:${R}"
echo -e "  - 'dry-run' label in blue (mode indicator)"
echo -e "  - Arrows muted (not actually running)"
echo -e "  - Commands muted (would run, not running)"
echo -e "  - Summary at bottom${R}"
echo ""

prompt "jake -n release.all"
echo -e "${BLUE}dry-run${R}"
echo ""
echo -e "${MUTED}→${R} ${ROSE}release.linux${R}"
echo -e "${MUTED}  zig build -Dtarget=x86_64-linux -Doptimize=ReleaseFast${R}"
echo ""
echo -e "${MUTED}→${R} ${ROSE}release.macos${R}"
echo -e "${MUTED}  zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast${R}"
echo ""
echo -e "${MUTED}→${R} ${ROSE}release.windows${R}"
echo -e "${MUTED}  zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast${R}"
echo ""
echo -e "${MUTED}→${R} ${ROSE}release.checksums${R}"
echo -e "${MUTED}  sha256sum zig-out/bin/* > checksums.txt${R}"
echo ""
echo -e "${MUTED}4 tasks would run${R}"

divider

# =============================================================================
# RECOMMENDED: PARALLEL EXECUTION
# =============================================================================

section "✅ RECOMMENDED: Parallel Execution"

echo -e "${MUTED}Why this style:${R}"
echo -e "  - Show which tasks are running in parallel"
echo -e "  - Completion order is natural (as they finish)"
echo -e "  - Total time at end"
echo ""

prompt "jake -j4 release.all"
echo -e "${ROSE}→ release.linux${R}  ${ROSE}→ release.macos${R}  ${ROSE}→ release.windows${R}"
echo -e "${GREEN}✓ release.macos${R} ${MUTED}3.2s${R}"
echo -e "${GREEN}✓ release.linux${R} ${MUTED}3.8s${R}"
echo -e "${GREEN}✓ release.windows${R} ${MUTED}4.1s${R}"
echo -e "${ROSE}→ release.checksums${R}"
echo -e "${GREEN}✓ release.checksums${R} ${MUTED}0.02s${R}"
echo ""
echo -e "${GREEN}✓ release.all${R} ${MUTED}4.2s${R}"

echo ""
echo -e "${MUTED}Editor extensions in parallel:${R}"
echo ""

prompt "jake -j8 editors.all"
echo -e "${ROSE}→ editors.vscode-package${R}  ${ROSE}→ editors.intellij-build${R}  ${ROSE}→ editors.zed-build${R}"
echo -e "${GREEN}✓ editors.vscode-package${R} ${MUTED}1.2s${R}"
echo -e "${GREEN}✓ editors.zed-build${R} ${MUTED}2.8s${R}"
echo -e "${GREEN}✓ editors.intellij-build${R} ${MUTED}8.4s${R}"
echo ""
echo -e "${GREEN}✓ editors.all${R} ${MUTED}8.4s${R}"

divider

# =============================================================================
# RECOMMENDED: RECIPE INSPECTION
# =============================================================================

section "✅ RECOMMENDED: Recipe Inspection (jake -s)"

echo -e "${MUTED}Why this style:${R}"
echo -e "  - Recipe name and description on first line (like man pages)"
echo -e "  - Key-value pairs are scannable"
echo -e "  - Commands shown verbatim at bottom"
echo ""

prompt "jake -s editors.vscode-publish"
echo ""
echo -e "${ROSE}editors.vscode-publish${R} ${MUTED}— Publish VS Code extension to marketplace${R}"
echo ""
echo -e "${MUTED}group${R}       editors"
echo -e "${MUTED}depends${R}     editors.vscode-package, editors.vscode-validate"
echo -e "${MUTED}needs${R}       vsce, node"
echo -e "${MUTED}requires${R}    VSCE_PAT"
echo ""
echo -e "${MUTED}commands${R}"
echo "  cd editors/vscode"
echo "  vsce publish --pat \$VSCE_PAT"

echo ""
prompt "jake -s release.build"
echo ""
echo -e "${ROSE}release.build${R} ${MUTED}— Build optimized release for current platform${R}"
echo ""
echo -e "${MUTED}group${R}       release"
echo -e "${MUTED}params${R}      platform=${MUTED}\"native\"${R}"
echo ""
echo -e "${MUTED}commands${R}"
echo "  zig build -Doptimize=ReleaseFast -Dstrip=true"
echo "  @echo \"Binary: zig-out/bin/jake\""

echo ""
prompt "jake -s perf.tracy-build"
echo ""
echo -e "${ROSE}perf.tracy-build${R} ${MUTED}— Build jake with Tracy instrumentation${R}"
echo ""
echo -e "${MUTED}group${R}       perf"
echo -e "${MUTED}needs${R}       tracy"
echo ""
echo -e "${MUTED}commands${R}"
echo "  zig build -Dtracy=true -Doptimize=ReleaseFast"

divider

# =============================================================================
# RECOMMENDED: FILE TARGETS
# =============================================================================

section "✅ RECOMMENDED: File Targets"

echo -e "${MUTED}Outdated (needs rebuild):${R}"
echo ""
prompt "jake zig-out/bin/jake"
echo -e "${ROSE}→ zig-out/bin/jake${R} ${MUTED}outdated${R}"
echo -e "${MUTED}  sources changed: src/parser.zig (2m ago)${R}"
echo -e "  zig build"
echo -e "${GREEN}✓ zig-out/bin/jake${R} ${MUTED}1.8s${R}"

echo ""
echo -e "${MUTED}Up to date (skip):${R}"
echo ""
prompt "jake zig-out/bin/jake"
echo -e "${MUTED}~ zig-out/bin/jake${R} ${MUTED}up to date${R}"

echo ""
echo -e "${MUTED}Multiple file targets:${R}"
echo ""
prompt "jake editors/vscode/jake.vsix"
echo -e "${ROSE}→ editors/vscode/jake.vsix${R} ${MUTED}outdated${R}"
echo -e "${MUTED}  sources changed: editors/vscode/syntaxes/jake.tmLanguage.json (5m ago)${R}"
echo -e "  cd editors/vscode && vsce package"
echo -e "${GREEN}✓ editors/vscode/jake.vsix${R} ${MUTED}2.1s${R}"

divider

# =============================================================================
# RECOMMENDED: CONFIRMATION PROMPTS
# =============================================================================

section "✅ RECOMMENDED: Confirmation Prompts"

echo -e "${MUTED}Why this style:${R}"
echo -e "  - Yellow question mark (attention required)"
echo -e "  - Default clearly indicated with capitalization"
echo -e "  - Simple y/N format (fast to type)"
echo ""

prompt "jake editors.vscode-publish"
echo -e "${ROSE}→ editors.vscode-publish${R}"
echo ""
echo -e "${YELLOW}?${R} Publish jake-lang v0.3.0 to VS Code Marketplace? ${MUTED}[y/N]${R} "

echo ""
prompt "jake maintenance.prune"
echo -e "${ROSE}→ maintenance.prune${R}"
echo ""
echo -e "${YELLOW}?${R} Delete all build artifacts and caches? ${MUTED}[y/N]${R} "

divider

# =============================================================================
# VERBOSE MODE
# =============================================================================

section "✅ RECOMMENDED: Verbose Mode (jake -v)"

echo -e "${MUTED}Shows additional context for debugging:${R}"
echo ""

prompt "jake -v build"
echo -e "${ROSE}→ build${R}"
echo -e "${MUTED}  deps: (none)${R}"
echo -e "${MUTED}  cwd: /Users/helge/code/jake${R}"
echo -e "  zig build"
echo -e "${MUTED}     info: Compilation started${R}"
echo -e "${MUTED}     info: 23/48 files cached${R}"
echo -e "${MUTED}     Compiling: src/main.zig${R}"
echo -e "${MUTED}     Compiling: src/parser.zig${R}"
echo -e "${MUTED}     Linking: zig-out/bin/jake${R}"
echo -e "${GREEN}✓ build${R} ${MUTED}1.8s${R}"

divider

# =============================================================================
# QUIET MODE
# =============================================================================

section "✅ RECOMMENDED: Quiet Mode (jake -q)"

echo -e "${MUTED}Minimal output - no command echo:${R}"
echo ""

prompt "jake -q dev.ci"
echo -e "${ROSE}→ lint${R}"
echo -e "${GREEN}✓ lint${R} ${MUTED}0.12s${R}"
echo -e "${ROSE}→ test${R}"
echo -e "${GREEN}✓ test${R} ${MUTED}3.4s${R}"
echo -e "${ROSE}→ build${R}"
echo -e "${GREEN}✓ build${R} ${MUTED}2.1s${R}"
echo -e "${ROSE}→ e2e${R}"
echo -e "${GREEN}✓ e2e${R} ${MUTED}4.7s${R}"
echo ""
echo -e "${GREEN}✓ dev.ci${R} ${MUTED}10.3s${R}"

divider

# =============================================================================
# REJECTED ALTERNATIVES
# =============================================================================

section "❌ REJECTED: Bracket Style"

echo -e "${MUTED}Why rejected:${R}"
echo -e "  - Adds visual noise"
echo -e "  - Doesn't match cargo/modern CLI conventions"
echo -e "  - Type badges add clutter (most recipes are tasks)"
echo ""

prompt "jake build"
echo -e "${MUTED}[${R}${ROSE}build${R}${MUTED}]${R} zig build"
echo -e "${MUTED}[${R}${GREEN}done${R}${MUTED}]${R} build ${MUTED}(1.8s)${R}"
echo ""
echo -e "${MUTED}^ Harder to scan, more cluttered${R}"

divider

section "❌ REJECTED: Emoji Indicators"

echo -e "${MUTED}Why rejected:${R}"
echo -e "  - Cross-platform rendering issues"
echo -e "  - Unprofessional appearance in some contexts"
echo -e "  - Unicode symbols (→✓✗) are sufficient and more consistent"
echo ""

prompt "jake -w dev"
echo -e "👀 Watching src/**/*.zig"
echo ""
echo -e "${MUTED}^ Font-dependent, may render as boxes on some terminals${R}"

divider

section "❌ REJECTED: {j} On Every Line"

echo -e "${MUTED}Why rejected:${R}"
echo -e "  - Overwhelming, distracting"
echo -e "  - Reduces scannability"
echo -e "  - Logo is for brand moments, not every output line"
echo ""

prompt "jake dev.ci"
echo -e "${ROSE}{j}${R} ${ROSE}→ lint${R}"
echo -e "${ROSE}{j}${R} ${GREEN}✓ lint${R} ${MUTED}0.12s${R}"
echo -e "${ROSE}{j}${R} ${ROSE}→ test${R}"
echo -e "${ROSE}{j}${R} ${GREEN}✓ test${R} ${MUTED}3.4s${R}"
echo ""
echo -e "${MUTED}^ Too noisy, the {j} adds no value here${R}"

divider

section "❌ REJECTED: Orange for Groups"

echo -e "${MUTED}Why rejected:${R}"
echo -e "  - Introduces 7th color to palette (complexity)"
echo -e "  - Bold + Rose provides enough differentiation"
echo -e "  - Keeps brand identity focused on Rose"
echo ""

echo -e "\x1b[38;2;249;115;22meditors:${R}"
echo -e "  ${ROSE}editors.vscode-install${R}  ${MUTED}Install VS Code extension${R}"
echo ""
echo -e "${MUTED}vs recommended (bold Rose):${R}"
echo ""
echo -e "${BOLD}${ROSE}editors${R}"
echo -e "  ${ROSE}editors.vscode-install${R}  ${MUTED}Install VS Code extension${R}"

divider

# =============================================================================
# IMPLEMENTATION SUMMARY
# =============================================================================

section "📋 IMPLEMENTATION CHECKLIST"

echo "Color palette (already in color.zig):"
echo -e "  ${GREEN}✓${R} Jake Rose (#f43f5e) - recipe names, branding, {j} logo"
echo -e "  ${GREEN}✓${R} Success Green (#22c55e) - checkmarks, done"
echo -e "  ${GREEN}✓${R} Error Red (#ef4444) - failures, errors"
echo -e "  ${GREEN}✓${R} Warning Yellow (#eab308) - warnings, prompts"
echo -e "  ${GREEN}✓${R} Info Blue (#60a5fa) - mode indicators"
echo -e "  ${GREEN}✓${R} Muted Gray (#71717a) - secondary info"
echo ""
echo "Symbols (already in color.zig):"
echo -e "  ${GREEN}✓${R} {j} (logo) - version, help, errors without Jakefile"
echo -e "  ${GREEN}✓${R} → (arrow) - starting task"
echo -e "  ${GREEN}✓${R} ✓ (check) - success"
echo -e "  ${GREEN}✓${R} ✗ (cross) - failure"
echo -e "  ${GREEN}✓${R} ~ (tilde) - skipped/up-to-date"
echo ""
echo "Output changes needed:"
echo -e "  ${YELLOW}○${R} Add {j} to --version and --help output"
echo -e "  ${YELLOW}○${R} Add {j} to 'no Jakefile found' error"
echo -e "  ${YELLOW}○${R} Remove [task]/[file] type badges from list output"
echo -e "  ${YELLOW}○${R} Use bold+Rose for group headers (not just Rose)"
echo -e "  ${YELLOW}○${R} Add 'watching' / 'changed' labels for watch mode"
echo -e "  ${YELLOW}○${R} Add 'dry-run' label and mute commands"
echo -e "  ${YELLOW}○${R} Implement 'hint:' prefix for actionable suggestions"
echo -e "  ${YELLOW}○${R} Add recipe count summary to -l output"

divider

# =============================================================================
# COMPARISON WITH OTHER TOOLS
# =============================================================================

section "📊 COMPARISON WITH OTHER TOOLS"

echo -e "${BOLD}just${R} (casey/just)"
echo -e "  ${MUTED}Output:${R} Minimal - just echoes commands"
echo -e "  ${MUTED}List:${R}   4-space indent, no colors by default"
echo -e "  ${MUTED}jake adds:${R} progress indication, timing, status, colors${R}"
echo ""
echo -e "${BOLD}cargo${R}"
echo -e "  ${MUTED}Output:${R} 'Compiling'/'Finished' labels in green"
echo -e "  ${MUTED}Errors:${R} 'error:' prefix in red with context"
echo -e "  ${MUTED}jake borrows:${R} error format, color conventions${R}"
echo ""
echo -e "${BOLD}npm${R}"
echo -e "  ${MUTED}Output:${R} Very verbose with lifecycle scripts"
echo -e "  ${MUTED}Style:${R}  Heavy use of emoji"
echo -e "  ${MUTED}jake avoids:${R} verbosity, emoji dependency${R}"
echo ""
echo -e "${BOLD}make${R}"
echo -e "  ${MUTED}Output:${R} No colors, cryptic error messages"
echo -e "  ${MUTED}List:${R}   No built-in list command"
echo -e "  ${MUTED}jake improves:${R} clarity, discoverability, visual feedback${R}"

divider

echo -e "${ROSE}{j}${R} ${MUTED}End of recommendations${R}"
echo ""
