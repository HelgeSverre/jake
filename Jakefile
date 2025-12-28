# Example Jakefile for testing jake

greeting = "Hello from Jake!"

@default
task hello:
    echo "{{greeting}}"

task build:
    echo "Building..."
    echo "Done!"

task test: [build]
    echo "Running tests..."

task all: [build, test]
    echo "All done!"

task greet name="World":
    echo "Hello, {{name}}!"
