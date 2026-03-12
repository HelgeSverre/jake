@group dev
@desc "Build the project"
task build:
    echo "Building"

@group dev
@desc "Run tests"
task test:
    echo "Testing"

@group prod
@desc "Deploy release"
deploy:
    echo "Deploying"

@group assets
@desc "Bundle frontend"
file dist/app.js: src/app.js
    echo "Bundling"

@group dev
@desc "Internal helper"
task _helper:
    echo "Helping"
