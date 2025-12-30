@on_error echo "ERROR HOOK TRIGGERED"

task fail:
    echo "About to fail..."
    exit 1

task succeed:
    echo "This will succeed"
