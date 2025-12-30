@before build echo "PRE-BUILD HOOK"
@after build echo "POST-BUILD HOOK"
@before test echo "PRE-TEST HOOK"
@after test echo "POST-TEST HOOK"

task build:
    echo "Building..."

task test:
    echo "Testing..."
