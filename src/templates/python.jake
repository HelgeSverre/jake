# Jakefile - Python Template
# For Python projects using venv and pip
#
# NOTE: Activate your virtual environment before running most tasks:
#   source .venv/bin/activate  (Linux/macOS)
#   .venv\Scripts\activate     (Windows)

# -----------------------------------------------------------------------------
# Default
# -----------------------------------------------------------------------------

# Default task - runs when you type just `jake`
task default: test

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

@group setup
@desc "Create virtual environment and install dependencies"
task setup:
    python -m venv .venv
    .venv/bin/pip install --upgrade pip
    .venv/bin/pip install -r requirements.txt

@group setup
@desc "Install development dependencies"
task setup-dev: setup
    .venv/bin/pip install -r requirements-dev.txt

@group setup
@desc "Install package in editable mode"
task install:
    .venv/bin/pip install -e .

@group setup
@desc "Install with all extras"
task install-all:
    .venv/bin/pip install -e ".[dev,test]"

# -----------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------

@group dev
@desc "Run the main module"
task run:
    python -m myapp

@group dev
@desc "Run with arguments"
task run-args *args:
    python -m myapp {{args}}

# -----------------------------------------------------------------------------
# Test
# -----------------------------------------------------------------------------

@group test
@desc "Run tests with pytest"
task test:
    pytest

@group test
@desc "Run tests with verbose output"
task test-v:
    pytest -v

@group test
@desc "Run tests with coverage"
task coverage:
    pytest --cov=. --cov-report=html

@group test
@desc "Run specific test file"
task test-file file:
    pytest {{file}} -v

# -----------------------------------------------------------------------------
# Code Quality
# -----------------------------------------------------------------------------

@group lint
@desc "Format code with ruff"
task fmt:
    ruff format .

@group lint
@desc "Check formatting"
task fmt-check:
    ruff format --check .

@group lint
@desc "Run ruff linter"
task lint:
    ruff check .

@group lint
@desc "Run ruff linter and fix issues"
task lint-fix:
    ruff check --fix .

@group lint
@desc "Run type checker (mypy)"
task typecheck:
    mypy .

@group lint
@desc "Run all quality checks"
task check-all: fmt-check lint typecheck

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

@group deps
@desc "Freeze current dependencies"
task freeze:
    pip freeze > requirements.txt

@group deps
@desc "Upgrade all packages"
task upgrade:
    pip list --outdated --format=json | python -c "import sys, json; print('\n'.join([x['name'] for x in json.load(sys.stdin)]))" | xargs -n1 pip install -U

@group deps
@desc "Show outdated packages"
task outdated:
    pip list --outdated

# -----------------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------------

@group clean
@desc "Clean Python artifacts"
task clean:
    find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name .mypy_cache -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name .ruff_cache -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
    find . -type f -name "*.pyc" -delete 2>/dev/null || true
    rm -rf dist/ build/ htmlcov/ .coverage

@group clean
@desc "Remove virtual environment"
task clean-venv:
    rm -rf .venv/
