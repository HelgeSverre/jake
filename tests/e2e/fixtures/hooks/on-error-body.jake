task fail:
    echo "About to fail..."
    @on_error echo "BODY ERROR HOOK"
    exit 1

task succeed:
    echo "Success path"
    @on_error echo "BODY ERROR HOOK"

task other-fails:
    echo "Other failing recipe..."
    exit 1
