#!/bin/bash
# completions_test.sh - Test shell completions for jake
# This script tests that completion scripts are generated correctly
# and can be sourced without errors in each shell.

set -e

JAKE_BIN="${JAKE_BIN:-./zig-out/bin/jake}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() {
	echo -e "${RED}FAIL${NC}: $1"
	exit 1
}
skip() { echo -e "${YELLOW}SKIP${NC}: $1"; }

# Change to project directory
cd "$PROJECT_DIR"

echo "=== Jake Shell Completions Test Suite ==="
echo "Using jake: $JAKE_BIN"
echo ""

# Ensure jake is built
if [ ! -f "$JAKE_BIN" ]; then
	echo "Building jake..."
	zig build -Doptimize=ReleaseFast
fi

# Test --summary flag
echo "--- Testing --summary flag ---"
SUMMARY=$("$JAKE_BIN" --summary 2>/dev/null)
if [ -n "$SUMMARY" ]; then
	RECIPE_COUNT=$(echo "$SUMMARY" | wc -w | tr -d ' ')
	pass "--summary returns $RECIPE_COUNT recipes"
else
	fail "--summary returned empty output"
fi

# Test --completions generates output for each shell
echo ""
echo "--- Testing --completions generation ---"

for SHELL_NAME in bash zsh fish; do
	OUTPUT=$("$JAKE_BIN" --completions "$SHELL_NAME" 2>/dev/null)
	if [ -n "$OUTPUT" ]; then
		LINE_COUNT=$(echo "$OUTPUT" | wc -l | tr -d ' ')
		pass "--completions $SHELL_NAME generates $LINE_COUNT lines"
	else
		fail "--completions $SHELL_NAME returned empty output"
	fi
done

# Test that completion scripts contain expected content
echo ""
echo "--- Testing completion script content ---"

# Bash: should have _jake function and complete command
BASH_COMP=$("$JAKE_BIN" --completions bash 2>/dev/null)
echo "$BASH_COMP" | grep -q "_jake()" && pass "bash: has _jake() function" || fail "bash: missing _jake() function"
echo "$BASH_COMP" | grep -q "complete -F _jake jake" && pass "bash: has complete command" || fail "bash: missing complete command"
echo "$BASH_COMP" | grep -q "jake --summary" && pass "bash: calls jake --summary" || fail "bash: missing jake --summary call"

# Zsh: should have #compdef and _arguments
ZSH_COMP=$("$JAKE_BIN" --completions zsh 2>/dev/null)
echo "$ZSH_COMP" | grep -q "#compdef jake" && pass "zsh: has #compdef jake" || fail "zsh: missing #compdef jake"
echo "$ZSH_COMP" | grep -q "_arguments" && pass "zsh: has _arguments" || fail "zsh: missing _arguments"
echo "$ZSH_COMP" | grep -q "\-\-summary" && pass "zsh: calls --summary" || fail "zsh: missing --summary call"

# Fish: should have complete -c jake and __jake_recipes function
FISH_COMP=$("$JAKE_BIN" --completions fish 2>/dev/null)
echo "$FISH_COMP" | grep -q "function __jake_recipes" && pass "fish: has __jake_recipes function" || fail "fish: missing __jake_recipes function"
echo "$FISH_COMP" | grep -q "complete -c jake" && pass "fish: has complete -c jake" || fail "fish: missing complete -c jake"
echo "$FISH_COMP" | grep -q "\-\-summary" && pass "fish: calls --summary" || fail "fish: missing --summary call"

# Test that all flags are included in completions
echo ""
echo "--- Testing flag completions ---"

for FLAG in help version list dry-run verbose yes jakefile watch jobs short show summary completions install uninstall; do
	echo "$BASH_COMP" | grep -q "\-\-$FLAG" && pass "bash: includes --$FLAG" || fail "bash: missing --$FLAG"
done

# Test completion scripts can be sourced without syntax errors
echo ""
echo "--- Testing completion script syntax ---"

# Test bash syntax
if command -v bash &>/dev/null; then
	BASH_SYNTAX=$(bash -n <(echo "$BASH_COMP") 2>&1) && pass "bash: syntax OK" || fail "bash: syntax error: $BASH_SYNTAX"
else
	skip "bash not available"
fi

# Test zsh syntax (using zsh -n for syntax check)
if command -v zsh &>/dev/null; then
	ZSH_SYNTAX=$(zsh -c "autoload -Uz compinit; source <(echo '$ZSH_COMP') 2>&1" 2>&1)
	if [ $? -eq 0 ] || echo "$ZSH_SYNTAX" | grep -q "command not found: _arguments"; then
		pass "zsh: syntax OK (or expected completion context error)"
	else
		fail "zsh: syntax error: $ZSH_SYNTAX"
	fi
else
	skip "zsh not available"
fi

# Test fish syntax
if command -v fish &>/dev/null; then
	FISH_SYNTAX=$(fish -n <(echo "$FISH_COMP") 2>&1) && pass "fish: syntax OK" || fail "fish: syntax error: $FISH_SYNTAX"
else
	skip "fish not available"
fi

# Test --completions with custom jakefile
echo ""
echo "--- Testing completions with -f flag ---"

# Create a temp jakefile
TEMP_JAKEFILE=$(mktemp)
cat >"$TEMP_JAKEFILE" <<'EOF'
task custom-recipe-one:
    echo "one"

task custom-recipe-two:
    echo "two"
EOF

CUSTOM_SUMMARY=$("$JAKE_BIN" -f "$TEMP_JAKEFILE" --summary 2>/dev/null)
if echo "$CUSTOM_SUMMARY" | grep -q "custom-recipe-one"; then
	pass "-f flag works with --summary (found custom-recipe-one)"
else
	fail "-f flag not working: expected custom-recipe-one, got: $CUSTOM_SUMMARY"
fi

rm -f "$TEMP_JAKEFILE"

# Test install paths (dry run - just verify path generation)
echo ""
echo "--- Testing install path generation ---"

# We test actual installation in a temp HOME directory
for SHELL_NAME in bash zsh fish; do
	TEMP_DIR=$(mktemp -d)
	HOME_BACKUP="$HOME"
	export HOME="$TEMP_DIR"

	# Unset ZSH to test vanilla zsh path
	ZSH_BACKUP="${ZSH:-}"
	unset ZSH

	OUTPUT=$("$JAKE_BIN" --completions "$SHELL_NAME" --install 2>&1)
	if [ $? -eq 0 ]; then
		case "$SHELL_NAME" in
		bash)
			[ -f "$TEMP_DIR/.local/share/bash-completion/completions/jake" ] && pass "bash: install creates file" || fail "bash: install did not create file"
			;;
		zsh)
			# Zsh install can go to multiple places depending on detection:
			# - ~/.zsh/completions/ (vanilla)
			# - /opt/homebrew/share/zsh/site-functions/ (homebrew, if writable)
			# - ~/.oh-my-zsh/custom/completions/ (oh-my-zsh)
			if [ -f "$TEMP_DIR/.zsh/completions/_jake" ]; then
				pass "zsh: install creates file (vanilla path)"
				if [ -f "$TEMP_DIR/.zshrc" ]; then
					grep -q "jake completion" "$TEMP_DIR/.zshrc" && pass "zsh: patches .zshrc" || skip "zsh: .zshrc not patched (may be homebrew fallback)"
				fi
			elif echo "$OUTPUT" | grep -q "homebrew\|Homebrew"; then
				pass "zsh: install to homebrew path (system-wide)"
			elif echo "$OUTPUT" | grep -q "oh-my-zsh\|Oh-My-Zsh"; then
				pass "zsh: install to oh-my-zsh path"
			else
				# Check if any path was mentioned in output
				if echo "$OUTPUT" | grep -q "Installed"; then
					pass "zsh: install succeeded"
				else
					fail "zsh: install did not create file"
				fi
			fi
			;;
		fish)
			[ -f "$TEMP_DIR/.config/fish/completions/jake.fish" ] && pass "fish: install creates file" || fail "fish: install did not create file"
			;;
		esac
	else
		fail "install command failed for $SHELL_NAME"
	fi

	export HOME="$HOME_BACKUP"
	[ -n "$ZSH_BACKUP" ] && export ZSH="$ZSH_BACKUP"
	rm -rf "$TEMP_DIR"
done

# Test uninstall (use bash since it has predictable path)
echo ""
echo "--- Testing uninstall ---"

TEMP_DIR=$(mktemp -d)
HOME_BACKUP="$HOME"
export HOME="$TEMP_DIR"

# Install bash completion first (predictable path)
"$JAKE_BIN" --completions bash --install >/dev/null 2>&1

# Verify file exists
[ -f "$TEMP_DIR/.local/share/bash-completion/completions/jake" ] && pass "uninstall test: file created" || fail "uninstall test: file not created"

# Uninstall
"$JAKE_BIN" --completions bash --uninstall >/dev/null 2>&1

# Verify file removed
[ ! -f "$TEMP_DIR/.local/share/bash-completion/completions/jake" ] && pass "uninstall test: file removed" || fail "uninstall test: file not removed"

export HOME="$HOME_BACKUP"
rm -rf "$TEMP_DIR"

echo ""
echo "=== All completion tests passed! ==="
