# Jakefile - Rust Template
# For Rust projects using Cargo

# -----------------------------------------------------------------------------
# Default
# -----------------------------------------------------------------------------

# Default task - runs when you type just `jake`
task default: build

# -----------------------------------------------------------------------------
# Build
# -----------------------------------------------------------------------------

@group build
@desc "Build in debug mode"
task build:
    cargo build

@group build
@desc "Build in release mode"
task release:
    cargo build --release

@group build
@desc "Build all targets"
task build-all:
    cargo build --all-targets

@group build
@desc "Check if project compiles (faster than build)"
task check:
    cargo check

# -----------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------

@group dev
@desc "Run the project"
task run:
    cargo run

@group dev
@desc "Run in release mode"
task run-release:
    cargo run --release

@group dev
@desc "Run with arguments"
task run-args *args:
    cargo run -- {{args}}

# -----------------------------------------------------------------------------
# Test
# -----------------------------------------------------------------------------

@group test
@desc "Run all tests"
task test:
    cargo test

@group test
@desc "Run tests with output"
task test-v:
    cargo test -- --nocapture

@group test
@desc "Run specific test"
task test-one name:
    cargo test {{name}}

@group test
@desc "Run doc tests"
task test-doc:
    cargo test --doc

# -----------------------------------------------------------------------------
# Code Quality
# -----------------------------------------------------------------------------

@group lint
@desc "Format code"
task fmt:
    cargo fmt

@group lint
@desc "Check formatting"
task fmt-check:
    cargo fmt -- --check

@group lint
@desc "Run Clippy linter"
task clippy:
    cargo clippy

@group lint
@desc "Run Clippy with strict warnings"
task clippy-strict:
    cargo clippy -- -D warnings

@group lint
@desc "Run all quality checks"
task lint-all: fmt-check clippy

# -----------------------------------------------------------------------------
# Documentation
# -----------------------------------------------------------------------------

@group docs
@desc "Build documentation"
task doc:
    cargo doc

@group docs
@desc "Build and open documentation"
task doc-open:
    cargo doc --open

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

@group deps
@desc "Update dependencies"
task update:
    cargo update

@group deps
@desc "Fetch dependencies"
task fetch:
    cargo fetch

@group deps
@desc "Show dependency tree"
task tree:
    cargo tree

@group deps
@desc "Audit dependencies for vulnerabilities"
task audit:
    cargo audit

# -----------------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------------

@group clean
@desc "Clean build artifacts"
task clean:
    cargo clean
