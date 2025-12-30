@group dev
@desc "Build the project"
task build: [lint]
    @needs gcc
    @cd ./src
    echo "Building..."

task lint:
    echo "Linting..."
