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
