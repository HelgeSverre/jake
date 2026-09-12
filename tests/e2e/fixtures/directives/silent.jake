# @silent suppresses jake's own status chrome for a recipe while keeping the
# recipe's output, errors, and exit code.

@silent
task help:
    echo "HELP BODY"

task normal:
    echo "NORMAL BODY"

@silent
task failing:
    echo "FAIL BODY"
    exit 1
