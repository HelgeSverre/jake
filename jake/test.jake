# Test tasks

JAKE_FUZZ_PORT = "4455"

@group test
@desc "Run coverage-guided fuzz testing"
task fuzz:
    @needs zig
    @pre echo "Running fuzz tests with coverage guidance..."
    @pre echo "Web UI: http://127.0.0.1:{{JAKE_FUZZ_PORT}}"
    zig build fuzz --fuzz --webui=127.0.0.1:{{JAKE_FUZZ_PORT}} -Doptimize=ReleaseSafe -j4

@group test
@desc "Test shell completions (bash, zsh, fish)"
task test-completions: [build]
    ./tests/completions_test.sh

@group test
@desc "Test completions in Docker (isolated environment)"
task test-completions-docker:
    @needs docker
    docker build -t jake-completions-test -f tests/Dockerfile.completions .
    docker run --rm jake-completions-test
