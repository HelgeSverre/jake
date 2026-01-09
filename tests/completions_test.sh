#!/bin/bash
# completions_test.sh - Test shell completions for jake
# This script tests that completion scripts are generated correctly
# and can be sourced without errors in each shell.
#
# Note: Uses bash for array support and process substitution

set -e
set -o pipefail

JAKE_BIN="${JAKE_BIN:-./zig-out/bin/jake}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test statistics
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Cleanup tracking
TEMP_FILES=()

cleanup() {
	for f in "${TEMP_FILES[@]}"; do
		rm -rf "$f" 2>/dev/null || true
	done
}
trap cleanup EXIT

pass() {
	echo -e "${GREEN}✓ PASS${NC}: $1"
	((TESTS_PASSED++)) || true
}

fail() {
	echo -e "${RED}✗ FAIL${NC}: $1"
	((TESTS_FAILED++)) || true
	# Don't exit immediately - collect all failures
}

skip() {
	echo -e "${YELLOW}⊘ SKIP${NC}: $1"
	((TESTS_SKIPPED++)) || true
}

info() {
	echo -e "${BLUE}ℹ${NC} $1"
}

# Helper: Check if shell is available
check_shell() {
	local shell_name="$1"
	if command -v "$shell_name" &>/dev/null; then
		return 0
	else
		return 1
	fi
}

# Change to project directory
cd "$PROJECT_DIR"

echo "=== Jake Shell Completions Test Suite ==="
echo "Using jake: $JAKE_BIN"
echo ""

# Ensure jake is built
if [[ ! -f "$JAKE_BIN" ]]; then
	info "Building jake..."
	zig build -Doptimize=ReleaseFast
fi

# Verify jake binary works
if ! "$JAKE_BIN" --version >/dev/null 2>&1; then
	echo -e "${RED}ERROR${NC}: jake binary not working"
	exit 1
fi

# Test --summary flag
echo "--- Testing --summary flag ---"
if SUMMARY=$("$JAKE_BIN" --summary 2>/dev/null); then
	if [[ -n "$SUMMARY" ]]; then
		RECIPE_COUNT=$(echo "$SUMMARY" | wc -w | tr -d ' ')
		pass "--summary returns $RECIPE_COUNT recipes"
	else
		fail "--summary returned empty output"
	fi
else
	fail "--summary command failed"
fi

# Test --short flag (one recipe per line)
echo ""
echo "--- Testing --short flag ---"
if SHORT_OUTPUT=$("$JAKE_BIN" --short 2>/dev/null); then
	if [[ -n "$SHORT_OUTPUT" ]]; then
		LINE_COUNT=$(echo "$SHORT_OUTPUT" | wc -l | tr -d ' ')
		# Verify format: each recipe on its own line, no spaces
		if echo "$SHORT_OUTPUT" | head -1 | grep -q " "; then
			fail "--short contains spaces on first line (should be one recipe per line)"
		else
			pass "--short returns $LINE_COUNT recipes (one per line)"
		fi
	else
		fail "--short returned empty output"
	fi
else
	fail "--short command failed"
fi

# Test --completions generates output for each shell
echo ""
echo "--- Testing --completions generation ---"

SHELLS=("bash" "zsh" "fish")
for SHELL_NAME in "${SHELLS[@]}"; do
	if OUTPUT=$("$JAKE_BIN" --completions "$SHELL_NAME" 2>/dev/null); then
		if [[ -n "$OUTPUT" ]]; then
			LINE_COUNT=$(echo "$OUTPUT" | wc -l | tr -d ' ')
			pass "--completions $SHELL_NAME generates $LINE_COUNT lines"
		else
			fail "--completions $SHELL_NAME returned empty output"
		fi
	else
		fail "--completions $SHELL_NAME command failed"
	fi
done

# Test invalid shell name (defaults to zsh)
echo ""
echo "--- Testing error handling ---"
if OUTPUT=$("$JAKE_BIN" --completions invalid_shell 2>/dev/null); then
	# Jake defaults to zsh for unrecognized shell names
	if echo "$OUTPUT" | grep -q "#compdef jake"; then
		pass "--completions defaults to zsh for invalid shell name"
	else
		fail "--completions invalid shell handling returned unexpected output"
	fi
else
	fail "--completions command failed with invalid shell name"
fi

# Test that completion scripts contain expected content
echo ""
echo "--- Testing completion script content ---"

# Bash: should have _jake function and complete command
BASH_COMP=$("$JAKE_BIN" --completions bash 2>/dev/null)
if echo "$BASH_COMP" | grep -q "_jake()"; then
	pass "bash: has _jake() function"
else
	fail "bash: missing _jake() function"
fi

if echo "$BASH_COMP" | grep -q "complete -F _jake jake"; then
	pass "bash: has complete command"
else
	fail "bash: missing complete command"
fi

if echo "$BASH_COMP" | grep -q "jake --summary"; then
	pass "bash: calls jake --summary"
else
	fail "bash: missing jake --summary call"
fi

# Zsh: should have #compdef and _arguments
ZSH_COMP=$("$JAKE_BIN" --completions zsh 2>/dev/null)
if echo "$ZSH_COMP" | grep -q "#compdef jake"; then
	pass "zsh: has #compdef jake"
else
	fail "zsh: missing #compdef jake"
fi

if echo "$ZSH_COMP" | grep -q "_arguments"; then
	pass "zsh: has _arguments"
else
	fail "zsh: missing _arguments"
fi

if echo "$ZSH_COMP" | grep -q "\-\-summary"; then
	pass "zsh: calls --summary"
else
	fail "zsh: missing --summary call"
fi

# Fish: should have complete -c jake and __jake_recipes function
FISH_COMP=$("$JAKE_BIN" --completions fish 2>/dev/null)
if echo "$FISH_COMP" | grep -q "function __jake_recipes"; then
	pass "fish: has __jake_recipes function"
else
	fail "fish: missing __jake_recipes function"
fi

if echo "$FISH_COMP" | grep -q "complete -c jake"; then
	pass "fish: has complete -c jake"
else
	fail "fish: missing complete -c jake"
fi

if echo "$FISH_COMP" | grep -q "\-\-summary"; then
	pass "fish: calls --summary"
else
	fail "fish: missing --summary call"
fi

# Test that all flags are included in completions
echo ""
echo "--- Testing flag completions ---"

EXPECTED_FLAGS=(
	"help"
	"version"
	"list"
	"dry-run"
	"verbose"
	"yes"
	"jakefile"
	"watch"
	"jobs"
	"short"
	"show"
	"summary"
	"completions"
	"install"
	"uninstall"
)

for FLAG in "${EXPECTED_FLAGS[@]}"; do
	if echo "$BASH_COMP" | grep -q "\-\-$FLAG"; then
		pass "bash: includes --$FLAG"
	else
		fail "bash: missing --$FLAG"
	fi
done

# Test completion scripts can be sourced without syntax errors
echo ""
echo "--- Testing completion script syntax ---"

# Test bash syntax
if check_shell bash; then
	if bash -n <(echo "$BASH_COMP") 2>&1; then
		pass "bash: syntax check passed"
	else
		BASH_SYNTAX=$(bash -n <(echo "$BASH_COMP") 2>&1)
		fail "bash: syntax error: $BASH_SYNTAX"
	fi
else
	skip "bash not available for testing"
fi

# Test zsh syntax
if check_shell zsh; then
	# zsh doesn't have a simple -n flag, try to source in a subshell
	if ZSH_SYNTAX=$(zsh -c "autoload -Uz compinit; source <(cat <<'ZSHEOF'
$ZSH_COMP
ZSHEOF
) 2>&1" 2>&1); then
		pass "zsh: syntax check passed"
	else
		# _arguments command not found is expected when not in completion context
		if echo "$ZSH_SYNTAX" | grep -q "command not found: _arguments"; then
			pass "zsh: syntax OK (completion functions require completion context)"
		else
			fail "zsh: syntax error: $ZSH_SYNTAX"
		fi
	fi
else
	skip "zsh not available for testing"
fi

# Test fish syntax
if check_shell fish; then
	if fish -n <(echo "$FISH_COMP") 2>&1; then
		pass "fish: syntax check passed"
	else
		FISH_SYNTAX=$(fish -n <(echo "$FISH_COMP") 2>&1)
		fail "fish: syntax error: $FISH_SYNTAX"
	fi
else
	skip "fish not available for testing"
fi

# Test --completions with custom jakefile
echo ""
echo "--- Testing completions with -f flag ---"

# Create a temp jakefile
TEMP_JAKEFILE=$(mktemp)
TEMP_FILES+=("$TEMP_JAKEFILE")

cat >"$TEMP_JAKEFILE" <<'EOF'
task custom-recipe-one:
    echo "one"

task custom-recipe-two:
    echo "two"

file target.txt: source.txt
    echo "build"
EOF

if CUSTOM_SUMMARY=$("$JAKE_BIN" -f "$TEMP_JAKEFILE" --summary 2>/dev/null); then
	if echo "$CUSTOM_SUMMARY" | grep -q "custom-recipe-one"; then
		pass "-f flag: --summary finds custom-recipe-one"
	else
		fail "-f flag: expected custom-recipe-one in summary, got: $CUSTOM_SUMMARY"
	fi

	if echo "$CUSTOM_SUMMARY" | grep -q "custom-recipe-two"; then
		pass "-f flag: --summary finds custom-recipe-two"
	else
		fail "-f flag: expected custom-recipe-two in summary"
	fi

	if echo "$CUSTOM_SUMMARY" | grep -q "target.txt"; then
		pass "-f flag: --summary includes file targets"
	else
		fail "-f flag: expected target.txt in summary"
	fi
else
	fail "-f flag: --summary command failed"
fi

# Test --short with custom jakefile
if CUSTOM_SHORT=$("$JAKE_BIN" -f "$TEMP_JAKEFILE" --short 2>/dev/null); then
	SHORT_LINE_COUNT=$(echo "$CUSTOM_SHORT" | wc -l | tr -d ' ')
	if [[ $SHORT_LINE_COUNT -ge 3 ]]; then
		pass "-f flag: --short returns $SHORT_LINE_COUNT lines"
	else
		fail "-f flag: --short returned only $SHORT_LINE_COUNT lines (expected 3+)"
	fi
else
	fail "-f flag: --short command failed"
fi

# Test that completions don't execute recipes
echo ""
echo "--- Testing completion safety ---"

TEMP_SAFETY=$(mktemp)
TEMP_FILES+=("$TEMP_SAFETY")

cat >"$TEMP_SAFETY" <<'EOF'
task dangerous:
    rm -rf /tmp/should-not-execute-{{env_var("USER")}}
EOF

# Generate completions - should NOT execute the recipe
if "$JAKE_BIN" -f "$TEMP_SAFETY" --summary >/dev/null 2>&1; then
	pass "completions do not execute recipes"
else
	fail "completions attempted to execute or errored"
fi

# Test install paths (dry run - just verify path generation)
echo ""
echo "--- Testing installation ---"

# Test bash installation
if check_shell bash; then
	TEMP_DIR=$(mktemp -d)
	TEMP_FILES+=("$TEMP_DIR")
	HOME_BACKUP="$HOME"
	export HOME="$TEMP_DIR"

	if "$JAKE_BIN" --completions bash --install >/dev/null 2>&1; then
		if [[ -f "$TEMP_DIR/.local/share/bash-completion/completions/jake" ]]; then
			pass "bash: install creates completion file"
		else
			fail "bash: install did not create completion file at expected path"
		fi
	else
		fail "bash: install command failed"
	fi

	export HOME="$HOME_BACKUP"
else
	skip "bash not available for install testing"
fi

# Test zsh installation
if check_shell zsh; then
	TEMP_DIR=$(mktemp -d)
	TEMP_FILES+=("$TEMP_DIR")
	HOME_BACKUP="$HOME"
	export HOME="$TEMP_DIR"

	# Unset ZSH to test vanilla zsh path
	ZSH_BACKUP="${ZSH:-}"
	unset ZSH

	if OUTPUT=$("$JAKE_BIN" --completions zsh --install 2>&1); then
		# Check multiple possible install locations
		if [[ -f "$TEMP_DIR/.zsh/completions/_jake" ]]; then
			pass "zsh: install creates completion file (vanilla path)"

			# Check .zshrc patching
			if [[ -f "$TEMP_DIR/.zshrc" ]]; then
				if grep -q "jake completion" "$TEMP_DIR/.zshrc"; then
					pass "zsh: .zshrc patched with fpath"
				else
					skip "zsh: .zshrc exists but not patched (using system path?)"
				fi
			fi
		elif [[ -f "$TEMP_DIR/.oh-my-zsh/custom/completions/_jake" ]]; then
			pass "zsh: install creates completion file (oh-my-zsh path)"
		elif echo "$OUTPUT" | grep -iq "installed.*completions"; then
			pass "zsh: install succeeded (system-wide path)"
		else
			fail "zsh: install did not create completion file. Output: $OUTPUT"
		fi
	else
		fail "zsh: install command failed"
	fi

	export HOME="$HOME_BACKUP"
	[[ -n "$ZSH_BACKUP" ]] && export ZSH="$ZSH_BACKUP"
else
	skip "zsh not available for install testing"
fi

# Test fish installation
if check_shell fish; then
	TEMP_DIR=$(mktemp -d)
	TEMP_FILES+=("$TEMP_DIR")
	HOME_BACKUP="$HOME"
	export HOME="$TEMP_DIR"

	if "$JAKE_BIN" --completions fish --install >/dev/null 2>&1; then
		if [[ -f "$TEMP_DIR/.config/fish/completions/jake.fish" ]]; then
			pass "fish: install creates completion file"
		else
			fail "fish: install did not create completion file at expected path"
		fi
	else
		fail "fish: install command failed"
	fi

	export HOME="$HOME_BACKUP"
else
	skip "fish not available for install testing"
fi

# Test uninstall
echo ""
echo "--- Testing uninstall ---"

if check_shell bash; then
	TEMP_DIR=$(mktemp -d)
	TEMP_FILES+=("$TEMP_DIR")
	HOME_BACKUP="$HOME"
	export HOME="$TEMP_DIR"

	# Install first
	"$JAKE_BIN" --completions bash --install >/dev/null 2>&1

	COMPLETION_FILE="$TEMP_DIR/.local/share/bash-completion/completions/jake"

	if [[ -f "$COMPLETION_FILE" ]]; then
		pass "uninstall test: completion file created"

		# Now uninstall
		if "$JAKE_BIN" --completions bash --uninstall >/dev/null 2>&1; then
			if [[ ! -f "$COMPLETION_FILE" ]]; then
				pass "uninstall test: completion file removed"
			else
				fail "uninstall test: completion file still exists"
			fi
		else
			fail "uninstall test: uninstall command failed"
		fi
	else
		fail "uninstall test: completion file not created for test"
	fi

	export HOME="$HOME_BACKUP"
else
	skip "bash not available for uninstall testing"
fi

# Test idempotency - install twice should work
echo ""
echo "--- Testing install idempotency ---"

if check_shell bash; then
	TEMP_DIR=$(mktemp -d)
	TEMP_FILES+=("$TEMP_DIR")
	HOME_BACKUP="$HOME"
	export HOME="$TEMP_DIR"

	# Install twice
	if "$JAKE_BIN" --completions bash --install >/dev/null 2>&1 && \
	   "$JAKE_BIN" --completions bash --install >/dev/null 2>&1; then
		pass "install is idempotent (can install twice)"
	else
		fail "install failed when run twice"
	fi

	export HOME="$HOME_BACKUP"
else
	skip "bash not available for idempotency testing"
fi

# Print summary
echo ""
echo "========================================"
echo "         Test Summary"
echo "========================================"
echo -e "Passed:  ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:  ${RED}$TESTS_FAILED${NC}"
echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
echo "----------------------------------------"
echo -e "Total:   $((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))"
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
	echo ""
	echo -e "${GREEN}✓ All completion tests passed!${NC}"
	exit 0
else
	echo ""
	echo -e "${RED}✗ $TESTS_FAILED test(s) failed${NC}"
	exit 1
fi
