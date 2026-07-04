@require TEST_VAR

task use-env:
    echo "TEST_VAR is set"

# No @require — must run even when TEST_VAR is unset (recipe-scoping).
task no-env:
    echo "no env needed"
