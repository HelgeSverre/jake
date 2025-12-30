# Docker build tasks - imported with "docker" prefix

registry = "ghcr.io/example"

task build:
    echo "Building Docker image..."
    echo "Registry: {{registry}}"

task push:
    echo "Pushing to {{registry}}..."

task pull:
    echo "Pulling from {{registry}}..."
