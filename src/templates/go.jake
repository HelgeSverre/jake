# Jakefile - Go Template
# For Go projects using Go modules

# -----------------------------------------------------------------------------
# Default
# -----------------------------------------------------------------------------

# Default task - runs when you type just `jake`
task default: build

# -----------------------------------------------------------------------------
# Build
# -----------------------------------------------------------------------------

@group build
@desc "Build all packages"
task build:
    go build ./...

@group build
@desc "Build with optimizations"
task build-release:
    go build -ldflags="-s -w" ./...

@group build
@desc "Build for current platform"
task build-local:
    go build -o bin/ .

# -----------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------

@group dev
@desc "Run the main package"
task run:
    go run .

@group dev
@desc "Run with arguments"
task run-args *args:
    go run . {{args}}

# -----------------------------------------------------------------------------
# Test
# -----------------------------------------------------------------------------

@group test
@desc "Run all tests"
task test:
    go test ./...

@group test
@desc "Run tests with verbose output"
task test-v:
    go test -v ./...

@group test
@desc "Run tests with coverage"
task coverage:
    go test -cover ./...

@group test
@desc "Generate coverage report"
task coverage-html:
    go test -coverprofile=coverage.out ./...
    go tool cover -html=coverage.out -o coverage.html

@group test
@desc "Run benchmarks"
task bench:
    go test -bench=. ./...

# -----------------------------------------------------------------------------
# Code Quality
# -----------------------------------------------------------------------------

@group lint
@desc "Format all Go files"
task fmt:
    go fmt ./...

@group lint
@desc "Run go vet"
task vet:
    go vet ./...

@group lint
@desc "Run staticcheck (install: go install honnef.co/go/tools/cmd/staticcheck@latest)"
task lint:
    staticcheck ./...

@group lint
@desc "Run golangci-lint (install: https://golangci-lint.run/usage/install/)"
task lint-all:
    golangci-lint run

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

@group deps
@desc "Download dependencies"
task deps:
    go mod download

@group deps
@desc "Tidy go.mod and go.sum"
task tidy:
    go mod tidy

@group deps
@desc "Verify dependencies"
task verify:
    go mod verify

@group deps
@desc "Update all dependencies"
task update:
    go get -u ./...
    go mod tidy

# -----------------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------------

@group clean
@desc "Clean build artifacts"
task clean:
    go clean
    rm -rf bin/
    rm -f coverage.out coverage.html
