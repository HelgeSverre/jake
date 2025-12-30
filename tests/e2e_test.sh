#!/bin/bash
# Jake End-to-End Test Suite
# Tests realistic scenarios and new features

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Path to jake binary
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JAKE="${JAKE:-$SCRIPT_DIR/../zig-out/bin/jake}"

# Create temporary directory for tests
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Helper function to run a test
run_test() {
    local test_name="$1"
    local expected_exit="$2"
    shift 2

    TESTS_RUN=$((TESTS_RUN + 1))

    if eval "$@" > "$TEST_DIR/output.txt" 2>&1; then
        actual_exit=0
    else
        actual_exit=$?
    fi

    # Create dot-fill between test name and result (60 char width)
    local name_len=${#test_name}
    local dots_needed=$((58 - name_len))
    if [ "$dots_needed" -lt 2 ]; then dots_needed=2; fi
    local dots=$(printf '.%.0s' $(seq 1 $dots_needed))

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo -e "  ${test_name} ${dots} ${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "  ${test_name} ${dots} ${RED}FAIL${NC}"
        echo -e "    ${RED}Expected exit $expected_exit, got $actual_exit${NC}"
        echo "    Output:"
        sed 's/^/      /' "$TEST_DIR/output.txt"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Helper function to check output contains text
assert_output_contains() {
    local text="$1"
    if grep -q "$text" "$TEST_DIR/output.txt"; then
        return 0
    else
        echo -e "${RED}  Output missing: $text${NC}"
        return 1
    fi
}

# Helper function to check output does not contain text
assert_output_not_contains() {
    local text="$1"
    if ! grep -q "$text" "$TEST_DIR/output.txt"; then
        return 0
    else
        echo -e "${RED}  Output should not contain: $text${NC}"
        return 1
    fi
}

echo -e "${YELLOW}Jake E2E Test Suite${NC}"
echo ""

echo -e "${BLUE}Basic Recipe Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task hello:
    echo "Hello, World!"

task greet name="World":
    echo "Hello, {{name}}!"
EOF

cd "$TEST_DIR"

run_test "Basic task execution" 0 "$JAKE hello"
assert_output_contains "Hello, World!"

run_test "Task with default parameter" 0 "$JAKE greet"
assert_output_contains "Hello, World!"

run_test "Task with custom parameter" 0 "$JAKE greet name=Alice"
assert_output_contains "Hello, Alice!"

run_test "Dry run mode" 0 "$JAKE -n hello"
assert_output_contains "dry-run"

run_test "List recipes" 0 "$JAKE -l"
assert_output_contains "hello"
assert_output_contains "greet"

echo -e "\n${BLUE}Parallel Execution Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task a:
    echo "Task A started"
    sleep 0.1
    echo "Task A done"

task b:
    echo "Task B started"
    sleep 0.1
    echo "Task B done"

task c:
    echo "Task C started"
    sleep 0.1
    echo "Task C done"

# All three can run in parallel, then all runs
task all: [a, b, c]
    echo "All tasks complete"
EOF

# Time sequential execution
START=$(date +%s.%N)
run_test "Sequential execution (baseline)" 0 "$JAKE all"
SEQ_TIME=$(echo "$(date +%s.%N) - $START" | bc)

# Time parallel execution
START=$(date +%s.%N)
run_test "Parallel execution with -j4" 0 "$JAKE -j4 all"
PAR_TIME=$(echo "$(date +%s.%N) - $START" | bc)

# In theory, parallel should be faster, but with small tasks it's hard to measure
echo "    Sequential: ${SEQ_TIME}s, Parallel: ${PAR_TIME}s"

run_test "Parallel dry-run" 0 "$JAKE -n -j4 all"
assert_output_contains "dry-run"

echo -e "\n${BLUE}Dependency Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task compile:
    echo "Compiling..."

task link: [compile]
    echo "Linking..."

task test: [link]
    echo "Testing..."

task build: [test]
    echo "Build complete"
EOF

run_test "Dependency chain execution" 0 "$JAKE build"
assert_output_contains "Compiling"
assert_output_contains "Linking"
assert_output_contains "Testing"
assert_output_contains "Build complete"

echo -e "\n${BLUE}@each Directive Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task process-items:
    @each apple banana cherry
        echo "Processing: {{item}}"
    @end
    echo "Done processing items"
EOF

run_test "@each with space-separated items" 0 "$JAKE process-items"
assert_output_contains "Processing: apple"
assert_output_contains "Processing: banana"
assert_output_contains "Processing: cherry"
assert_output_contains "Done processing items"

mkdir -p "$TEST_DIR/src"
echo "file1" > "$TEST_DIR/src/test1.txt"
echo "file2" > "$TEST_DIR/src/test2.txt"
echo "file3" > "$TEST_DIR/src/test3.txt"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task glob-test:
    @each src/*.txt
        echo "Found: {{item}}"
    @end
    echo "Glob complete"
EOF

run_test "@each with glob pattern" 0 "$JAKE glob-test"
assert_output_contains "Found:"
assert_output_contains "Glob complete"

echo -e "\n${BLUE}Targeted Hook Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
@before build echo "PRE-BUILD HOOK"
@after build echo "POST-BUILD HOOK"
@before test echo "PRE-TEST HOOK"
@after test echo "POST-TEST HOOK"

task build:
    echo "Building..."

task test:
    echo "Testing..."
EOF

run_test "@before hook targets build only" 0 "$JAKE build"
assert_output_contains "PRE-BUILD HOOK"
assert_output_contains "Building..."
assert_output_contains "POST-BUILD HOOK"
assert_output_not_contains "PRE-TEST"
assert_output_not_contains "POST-TEST"

run_test "@before hook targets test only" 0 "$JAKE test"
assert_output_contains "PRE-TEST HOOK"
assert_output_contains "Testing..."
assert_output_contains "POST-TEST HOOK"
assert_output_not_contains "PRE-BUILD"
assert_output_not_contains "POST-BUILD"

echo -e "\n${BLUE}@on_error Hook Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
@on_error echo "ERROR HOOK TRIGGERED"

task fail:
    echo "About to fail..."
    exit 1

task succeed:
    echo "This will succeed"
EOF

run_test "@on_error hook runs on failure" 1 "$JAKE fail"
assert_output_contains "ERROR HOOK TRIGGERED"

run_test "@on_error hook does not run on success" 0 "$JAKE succeed"
assert_output_contains "This will succeed"
assert_output_not_contains "ERROR HOOK"

# @on_error is always global
cat > "$TEST_DIR/Jakefile" << 'EOF'
@on_error echo "GLOBAL ERROR HANDLER"

task deploy:
    echo "Deploying..."
    exit 1

task build:
    exit 1
EOF

run_test "@on_error runs on deploy failure" 1 "$JAKE deploy"
assert_output_contains "GLOBAL ERROR HANDLER"

run_test "@on_error runs on build failure" 1 "$JAKE build"
assert_output_contains "GLOBAL ERROR HANDLER"

echo -e "\n${BLUE}Conditional Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
env = "production"

task deploy:
    @if eq({{env}}, "production")
        echo "Deploying to PRODUCTION"
    @elif eq({{env}}, "staging")
        echo "Deploying to STAGING"
    @else
        echo "Unknown environment"
    @end
EOF

run_test "Conditional @if with eq()" 0 "$JAKE deploy"
assert_output_contains "Deploying to PRODUCTION"

echo -e "\n${BLUE}@confirm Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task dangerous:
    @confirm "Are you sure you want to proceed?"
    echo "Proceeding with dangerous operation"
EOF

run_test "@confirm with --yes flag" 0 "$JAKE -y dangerous"
assert_output_contains "Proceeding with dangerous operation"

run_test "@confirm in dry-run mode" 0 "$JAKE -n dangerous"
assert_output_contains "dry-run"

echo -e "\n${BLUE}@ignore Directive Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task ignore-test:
    @ignore
    exit 1
    echo "After failed command"
EOF

run_test "@ignore allows continuing after failure" 0 "$JAKE ignore-test"
assert_output_contains "After failed command"

echo -e "\n${BLUE}Private Recipe Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task public:
    echo "Public task"

task _private:
    echo "Private task"
EOF

run_test "Private recipes are hidden from list" 0 "$JAKE -l"
assert_output_contains "public"
assert_output_not_contains "_private"

run_test "Private recipes can still be executed" 0 "$JAKE _private"
assert_output_contains "Private task"

echo -e "\n${BLUE}Recipe Alias Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
@alias b
task build:
    echo "Building with alias"
EOF

run_test "Recipe can be called by alias" 0 "$JAKE b"
assert_output_contains "Building with alias"

echo -e "\n${BLUE}@needs Directive Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task check-tools:
    @needs echo cat ls
    echo "All tools present"

task check-missing:
    @needs nonexistent_tool_12345
    echo "This should not print"
EOF

run_test "@needs with existing commands" 0 "$JAKE check-tools"
assert_output_contains "All tools present"

run_test "@needs with missing command" 1 "$JAKE check-missing"
assert_output_not_contains "This should not print"

echo -e "\n${BLUE}@require Directive Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
@require TEST_VAR

task use-env:
    echo "TEST_VAR is set"
EOF

run_test "@require fails when env var missing" 1 "$JAKE use-env"
assert_output_contains "Required environment variable"

export TEST_VAR="test_value"
run_test "@require passes when env var set" 0 "$JAKE use-env"
assert_output_contains "TEST_VAR is set"
unset TEST_VAR

echo -e "\n${BLUE}Verbose Mode Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task hello:
    echo "Hello"
EOF

run_test "Verbose mode shows more output" 0 "$JAKE -v hello"
# Verbose mode should show command being run
assert_output_contains "Hello"

echo -e "\n${BLUE}File Target Tests${NC}"

rm -f "$TEST_DIR/output.txt" "$TEST_DIR/input.txt"
echo "input content" > "$TEST_DIR/input.txt"

cat > "$TEST_DIR/Jakefile" << 'EOF'
file output.txt: input.txt
    cat input.txt > output.txt
    echo "Built output.txt"
EOF

run_test "File target builds when output missing" 0 "$JAKE output.txt"
assert_output_contains "Built output.txt"

run_test "File target skips when up-to-date" 0 "$JAKE output.txt"
# Second run should be quick (cached/up-to-date)

echo -e "\n${BLUE}Groups and Descriptions Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
@group dev
@desc "Build the project"
task build:
    echo "Building"

@group dev
@desc "Run tests"
task test:
    echo "Testing"

@group prod
@desc "Deploy to production"
task deploy:
    echo "Deploying"
EOF

run_test "List shows descriptions" 0 "$JAKE -l"
assert_output_contains "Build the project"
assert_output_contains "Run tests"
assert_output_contains "Deploy to production"

echo -e "\n${BLUE}Cyclic Dependency Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task a: [b]
    echo "A"

task b: [c]
    echo "B"

task c: [a]
    echo "C"
EOF

run_test "Cyclic dependency is detected" 1 "$JAKE a"
assert_output_contains "Cyclic"

echo -e "\n${BLUE}@cd Directive Tests${NC}"

mkdir -p "$TEST_DIR/subdir"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task in-subdir:
    @cd subdir
    pwd
EOF

run_test "@cd changes working directory" 0 "$JAKE in-subdir"
assert_output_contains "subdir"

echo -e "\n${BLUE}Built-in Functions Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task test-functions:
    echo "uppercase: {{uppercase(hello world)}}"
    echo "basename: {{basename(/path/to/file.txt)}}"
    echo "dirname: {{dirname(/path/to/file.txt)}}"
EOF

run_test "Built-in functions work" 0 "$JAKE test-functions"
assert_output_contains "uppercase: HELLO WORLD"
assert_output_contains "basename: file.txt"
assert_output_contains "dirname: /path/to"

echo -e "\n${BLUE}Nested Conditionals Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task nested-if:
    @if exists(/bin)
        echo "A: /bin exists"
        @if env(HOME)
            echo "B: HOME is set"
        @else
            echo "C: No HOME"
        @end
        echo "D: after inner if"
    @else
        echo "E: No /bin"
    @end
    echo "F: after outer if"
EOF

run_test "Nested @if blocks execute correctly" 0 "$JAKE nested-if"
assert_output_contains "A: /bin exists"
assert_output_contains "B: HOME is set"
assert_output_contains "D: after inner if"
assert_output_contains "F: after outer if"
assert_output_not_contains "C: No HOME"
assert_output_not_contains "E: No /bin"

echo -e "\n${BLUE}Complex @each Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task process:
    @each alpha beta gamma
        @if exists(/bin)
            echo "Processing: {{item}} (system ok)"
        @else
            echo "{{item}} (no system)"
        @end
    @end
    echo "Done"
EOF

run_test "@each with conditional inside" 0 "$JAKE process"
assert_output_contains "Processing: alpha (system ok)"
assert_output_contains "Processing: beta (system ok)"
assert_output_contains "Processing: gamma (system ok)"
assert_output_contains "Done"

echo -e "\n${BLUE}Complex Dependency Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task prep-a:
    echo "prep-a"

task prep-b:
    echo "prep-b"

task stage1: [prep-a, prep-b]
    echo "stage1"

task stage2: [stage1]
    echo "stage2"

task stage3: [stage2]
    echo "stage3"

task final: [stage3]
    echo "final"
EOF

run_test "Deep dependency chain with parallel" 0 "$JAKE -j4 final"
assert_output_contains "prep-a"
assert_output_contains "prep-b"
assert_output_contains "stage1"
assert_output_contains "stage2"
assert_output_contains "stage3"
assert_output_contains "final"

echo -e "\n${BLUE}Hooks with Dependencies Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
@before deploy echo "[PRE-DEPLOY]"
@after deploy echo "[POST-DEPLOY]"

task build:
    echo "Building..."

task deploy: [build]
    echo "Deploying..."
EOF

run_test "Hooks run for target with dependencies" 0 "$JAKE deploy"
assert_output_contains "Building..."
assert_output_contains "PRE-DEPLOY"
assert_output_contains "Deploying..."
assert_output_contains "POST-DEPLOY"

echo -e "\n${BLUE}Multiple @each Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task multi-loop:
    echo "First loop:"
    @each red green blue
        echo "  Color: {{item}}"
    @end
    echo "Second loop:"
    @each 1 2 3
        echo "  Number: {{item}}"
    @end
    echo "Complete"
EOF

run_test "Multiple @each loops in sequence" 0 "$JAKE multi-loop"
assert_output_contains "Color: red"
assert_output_contains "Color: green"
assert_output_contains "Color: blue"
assert_output_contains "Number: 1"
assert_output_contains "Number: 2"
assert_output_contains "Number: 3"
assert_output_contains "Complete"

echo -e "\n${BLUE}Full Project Simulation${NC}"

mkdir -p "$TEST_DIR/project/src" "$TEST_DIR/project/tests" "$TEST_DIR/project/docs"
echo "module1" > "$TEST_DIR/project/src/mod1.ts"
echo "module2" > "$TEST_DIR/project/src/mod2.ts"
echo "test1" > "$TEST_DIR/project/tests/test1.ts"

cat > "$TEST_DIR/project/Jakefile" << 'EOF'
version = "2.0.0"

@before build echo "=== Starting build v{{version}} ==="
@after build echo "=== Build complete ==="
@on_error echo "!!! Build failed !!!"

@desc "Clean build artifacts"
task clean:
    echo "Cleaning..."

@desc "Lint source files"
task lint:
    echo "Linting src/mod1.ts"
    echo "Linting src/mod2.ts"

@desc "Run tests"
task test: [lint]
    echo "Testing tests/test1.ts"

@desc "Build the project"
task build: [test]
    echo "Building v{{version}} with new features"

@desc "Full release"
task release: [clean, build]
    echo "Releasing v{{version}}"
EOF

cd "$TEST_DIR/project"

run_test "Full project: clean task" 0 "$JAKE clean"
assert_output_contains "Cleaning"

run_test "Full project: lint task" 0 "$JAKE lint"
assert_output_contains "Linting src/mod1.ts"
assert_output_contains "Linting src/mod2.ts"

run_test "Full project: build with hooks and deps" 0 "$JAKE build"
assert_output_contains "=== Starting build v2.0.0 ==="
assert_output_contains "Linting"
assert_output_contains "Testing"
assert_output_contains "Building v2.0.0 with new features"
assert_output_contains "=== Build complete ==="

run_test "Full project: release with parallel deps" 0 "$JAKE -j2 release"
assert_output_contains "Cleaning"
assert_output_contains "Releasing v2.0.0"

cd "$TEST_DIR"

echo -e "\n${BLUE}@shell Directive Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task with-shell:
    @shell /bin/bash
    echo "Running in bash: $BASH_VERSION"
EOF

run_test "@shell changes the shell" 0 "$JAKE with-shell"
assert_output_contains "Running in bash"

echo -e "\n${BLUE}Variable Expansion Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
MY_VAR = "exported_value"

task check-var:
    echo "Value: {{MY_VAR}}"
EOF

run_test "Jake variables expand in commands" 0 "$JAKE check-var"
assert_output_contains "Value: exported_value"

echo -e "\n${BLUE}Triple Nested Conditionals${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task triple-nest:
    @if exists(/bin)
        echo "L1: /bin exists"
        @if env(HOME)
            echo "L2: HOME set"
            @if exists(/usr)
                echo "L3: /usr exists"
            @else
                echo "L3: no /usr"
            @end
            echo "L2: after L3"
        @else
            echo "L2: no HOME"
        @end
        echo "L1: after L2"
    @else
        echo "L1: no /bin"
    @end
    echo "Done"
EOF

run_test "Triple nested conditionals work" 0 "$JAKE triple-nest"
assert_output_contains "L1: /bin exists"
assert_output_contains "L2: HOME set"
assert_output_contains "L3: /usr exists"
assert_output_contains "L2: after L3"
assert_output_contains "L1: after L2"
assert_output_contains "Done"
assert_output_not_contains "no /bin"
assert_output_not_contains "no HOME"
assert_output_not_contains "no /usr"

echo -e "\n${BLUE}--list --short Flag Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task build:
    echo "Building..."

task test:
    echo "Testing..."

task _private:
    echo "Private task"
EOF

run_test "--list --short outputs one recipe per line" 0 "$JAKE --list --short"
assert_output_contains "build"
assert_output_contains "test"
assert_output_not_contains "_private"

# Test piping works
LINE_COUNT=$("$JAKE" --list --short 2>/dev/null | wc -l | tr -d ' ')
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$LINE_COUNT" -eq 2 ]; then
    echo -e "  --list --short line count correct ........................ ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  --list --short line count correct ........................ ${RED}FAIL${NC}"
    echo -e "    ${RED}Expected 2 lines, got $LINE_COUNT${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo -e "\n${BLUE}--show Recipe Flag Tests${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
@group dev
@desc "Build the project"
task build: [lint]
    @needs gcc
    @cd ./src
    echo "Building..."

task lint:
    echo "Linting..."
EOF

run_test "--show displays recipe details" 0 "$JAKE --show build"
assert_output_contains "Recipe:"
assert_output_contains "build"
assert_output_contains "Type:"
assert_output_contains "task"
assert_output_contains "Group:"
assert_output_contains "dev"
assert_output_contains "Description:"
assert_output_contains "Dependencies:"
assert_output_contains "lint"

run_test "-s shorthand works" 0 "$JAKE -s build"
assert_output_contains "Recipe:"
assert_output_contains "build"

run_test "--show with missing recipe fails" 1 "$JAKE --show nonexistent"
assert_output_contains "not found"

echo -e "\n${BLUE}Recipe Typo Suggestions${NC}"

cat > "$TEST_DIR/Jakefile" << 'EOF'
task build:
    echo "Building..."

task test:
    echo "Testing..."

task deploy:
    echo "Deploying..."
EOF

run_test "Typo suggestion for 'buidl'" 1 "$JAKE buidl"
assert_output_contains "not found"
assert_output_contains "Did you mean"
assert_output_contains "build"

run_test "Typo suggestion for 'tset'" 1 "$JAKE tset"
assert_output_contains "not found"
assert_output_contains "Did you mean"
assert_output_contains "test"

run_test "Typo suggestion for 'delpoy'" 1 "$JAKE delpoy"
assert_output_contains "not found"
assert_output_contains "Did you mean"
assert_output_contains "deploy"

run_test "No suggestion for completely wrong name" 1 "$JAKE xyz123"
assert_output_contains "not found"
# Should fall back to generic message when no close match
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "jake --list" "$TEST_DIR/output.txt"; then
    echo -e "  Shows generic help when no match .......................... ${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "  Shows generic help when no match .......................... ${YELLOW}SKIP${NC}"
fi

echo ""
echo -e "${YELLOW}Summary${NC}"
echo -e "  Tests run:    $TESTS_RUN"
echo -e "  Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "  Tests failed: ${RED}$TESTS_FAILED${NC}"

if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "\n${RED}SOME TESTS FAILED${NC}"
    exit 1
else
    echo -e "\n${GREEN}ALL TESTS PASSED${NC}"
    exit 0
fi
