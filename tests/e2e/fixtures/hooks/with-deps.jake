@before deploy echo "[PRE-DEPLOY]"
@after deploy echo "[POST-DEPLOY]"

task build:
    echo "Building..."

task deploy: [build]
    echo "Deploying..."
