#!/bin/bash
# docs_contract_test.sh - Verify active CLI docs match the current binary.

set -euo pipefail

JAKE_BIN="${JAKE_BIN:-./zig-out/bin/jake}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TESTS_PASSED=0
TESTS_FAILED=0
TEMP_DIRS=()

cleanup() {
	for dir in "${TEMP_DIRS[@]}"; do
		rm -rf "$dir" 2>/dev/null || true
	done
}
trap cleanup EXIT

pass() {
	echo "PASS: $1" >&2
	((TESTS_PASSED++)) || true
}

fail() {
	echo "FAIL: $1" >&2
	((TESTS_FAILED++)) || true
}

strip_ansi() {
	perl -pe 's/\e\[[0-9;]*m//g'
}

require_contains() {
	local label="$1"
	local haystack="$2"
	local needle="$3"
	if [[ "$haystack" == *"$needle"* ]]; then
		pass "$label"
	else
		fail "$label (missing '$needle')"
	fi
}

require_matches() {
	local label="$1"
	local haystack="$2"
	local pattern="$3"
	if [[ "$haystack" =~ $pattern ]]; then
		pass "$label"
	else
		fail "$label (missing pattern '$pattern')"
	fi
}

require_no_match() {
	local label="$1"
	local pattern="$2"
	shift 2
	if rg -n -- "$pattern" "$@" >/tmp/jake-docs-contract-rg.out 2>&1; then
		echo "Unexpected matches for $label:" >&2
		cat /tmp/jake-docs-contract-rg.out >&2
		fail "$label"
	else
		pass "$label"
	fi
}

run_capture() {
	local label="$1"
	shift
	local output
	if ! output="$("$@" 2>&1)"; then
		echo "$output" >&2
		fail "$label"
		return 1
	fi
	printf '%s' "$output"
	pass "$label"
}

cd "$PROJECT_DIR"

if [[ ! -f "$JAKE_BIN" ]]; then
	echo "Building release binary for docs contract checks..."
	zig build -Doptimize=ReleaseFast
fi

ACTIVE_DOCS=(
	README.md
	GUIDE.md
	CHANGELOG.md
	site/src/content/docs/reference/cli.md
	site/src/content/docs/reference/shell-completions.md
	site/src/content/docs/docs/installation.md
	site/src/content/docs/docs/web-ui.md
	site/src/content/docs/docs/external-build-systems.md
)

echo "=== Jake Docs Contract Test Suite ===" >&2
echo "Using jake: $JAKE_BIN" >&2
echo "" >&2

HELP_OUTPUT="$(NO_COLOR=1 "$JAKE_BIN" --help | strip_ansi)"
VERSION_OUTPUT="$(NO_COLOR=1 "$JAKE_BIN" --version | strip_ansi)"

require_contains "help shows optional completions shell" "$HELP_OUTPUT" "--completions [SHELL]"
require_contains "help shows external listing flag" "$HELP_OUTPUT" "--[no-]external [TYPE]"
require_contains "help shows summary flag" "$HELP_OUTPUT" "--summary"
require_contains "help shows web flag" "$HELP_OUTPUT" "--web"
require_contains "help shows port flag" "$HELP_OUTPUT" "--port PORT"
require_contains "help shows formatter check flag" "$HELP_OUTPUT" "--check"
require_contains "help shows formatter dump flag" "$HELP_OUTPUT" "--dump"
require_matches "version command returns semver-like output" "$VERSION_OUTPUT" '[0-9]+\.[0-9]+\.[0-9]+'

require_no_match "active docs do not mention removed --webui flag" "--webui" "${ACTIVE_DOCS[@]}"
require_no_match "active docs do not use stale JAKE_FILE env name" "JAKE_FILE" "${ACTIVE_DOCS[@]}"
require_no_match "active docs do not present completions shell as required" "--completions SHELL" "${ACTIVE_DOCS[@]}"
require_no_match "active docs do not show standalone jake --check" "jake --check" "${ACTIVE_DOCS[@]}"
require_no_match "active docs do not show standalone jake --dump" "jake --dump" "${ACTIVE_DOCS[@]}"

LIST_FIXTURE="$PROJECT_DIR/tests/e2e/fixtures/cli/list.jake"
SHOW_FIXTURE="$PROJECT_DIR/tests/e2e/fixtures/cli/show.jake"
FORMAT_FIXTURE="$PROJECT_DIR/tests/e2e/fixtures/basic/hello.jake"
EXTERNAL_FIXTURE="$PROJECT_DIR/tests/e2e/fixtures/external/nested/Jakefile"

LIST_OUTPUT="$(run_capture "documented --list example succeeds" "$JAKE_BIN" -f "$LIST_FIXTURE" --list)"
require_contains "--list output contains build recipe" "$LIST_OUTPUT" "build"

ALL_OUTPUT="$(run_capture "documented --all example succeeds" "$JAKE_BIN" -f "$LIST_FIXTURE" --list --all)"
require_contains "--all output includes hidden recipe" "$ALL_OUTPUT" "_private"

SHORT_OUTPUT="$(run_capture "documented --list --short example succeeds" "$JAKE_BIN" -f "$LIST_FIXTURE" --list --short)"
require_contains "--list --short output includes build" "$SHORT_OUTPUT" "build"

SUMMARY_OUTPUT="$(run_capture "documented --summary example succeeds" "$JAKE_BIN" -f "$LIST_FIXTURE" --summary)"
require_contains "--summary output includes test" "$SUMMARY_OUTPUT" "test"

SHOW_OUTPUT="$(run_capture "documented --show example succeeds" env NO_COLOR=1 "$JAKE_BIN" -f "$SHOW_FIXTURE" --show build)"
require_contains "--show output includes recipe header" "$SHOW_OUTPUT" "Recipe:"
require_contains "--show output includes recipe name" "$SHOW_OUTPUT" "build"

FMT_OUTPUT="$(run_capture "documented --fmt --check example succeeds" env NO_COLOR=1 "$JAKE_BIN" --fmt --check -f "$FORMAT_FIXTURE")"
require_contains "--fmt --check reports formatted file" "$FMT_OUTPUT" "correctly formatted"

BASH_COMPLETIONS="$(run_capture "documented bash completions example succeeds" "$JAKE_BIN" --completions bash)"
require_contains "bash completions include complete hook" "$BASH_COMPLETIONS" "complete -F _jake jake"

ZSH_COMPLETIONS="$(run_capture "documented zsh completions example succeeds" "$JAKE_BIN" --completions zsh)"
require_contains "zsh completions include compdef" "$ZSH_COMPLETIONS" "#compdef jake"
require_contains "zsh completions invoke jake completer" "$ZSH_COMPLETIONS" "_jake \"\$@\""

FISH_COMPLETIONS="$(run_capture "documented fish completions example succeeds" "$JAKE_BIN" --completions fish)"
require_contains "fish completions include complete command" "$FISH_COMPLETIONS" "complete -c jake"

temp_home="$(mktemp -d)"
TEMP_DIRS+=("$temp_home")

INSTALL_OUTPUT="$(run_capture "documented completion install example succeeds" env HOME="$temp_home" SHELL=/bin/bash NO_COLOR=1 "$JAKE_BIN" --completions --install)"
require_contains "completion install reports destination" "$INSTALL_OUTPUT" "Installed bash completion"
if [[ -f "$temp_home/.local/share/bash-completion/completions/jake" ]]; then
	pass "completion install created bash completion file"
else
	fail "completion install created bash completion file"
fi

UNINSTALL_OUTPUT="$(run_capture "documented completion uninstall example succeeds" env HOME="$temp_home" SHELL=/bin/bash NO_COLOR=1 "$JAKE_BIN" --completions --uninstall)"
require_contains "completion uninstall reports removal" "$UNINSTALL_OUTPUT" "Removed bash completions"
if [[ ! -f "$temp_home/.local/share/bash-completion/completions/jake" ]]; then
	pass "completion uninstall removed bash completion file"
else
	fail "completion uninstall removed bash completion file"
fi

EXTERNAL_LIST_OUTPUT="$(run_capture "documented external listing example succeeds" env NO_COLOR=1 "$JAKE_BIN" -f "$EXTERNAL_FIXTURE" --external make)"
require_contains "--external make output includes nested target" "$EXTERNAL_LIST_OUTPUT" "make.nested-list"

EXTERNAL_RUN_OUTPUT="$(run_capture "documented external execution example succeeds" env NO_COLOR=1 "$JAKE_BIN" -f "$EXTERNAL_FIXTURE" make.nested-list)"
require_contains "external execution runs nested make target" "$EXTERNAL_RUN_OUTPUT" "NESTED_EXTERNAL_OK"

echo "" >&2
echo "Docs contract summary: $TESTS_PASSED passed, $TESTS_FAILED failed" >&2

if [[ "$TESTS_FAILED" -ne 0 ]]; then
	exit 1
fi
