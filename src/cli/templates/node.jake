# Jakefile - Node.js/TypeScript Template
# For JavaScript and TypeScript projects using npm/pnpm/yarn

# Load environment variables from .env file
@dotenv

# -----------------------------------------------------------------------------
# Default
# -----------------------------------------------------------------------------

# Default task - runs when you type just `jake`
task default: build

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

@group setup
@desc "Install project dependencies"
task setup:
    npm install

@group setup
@desc "Clean install (removes node_modules first)"
task clean-install:
    rm -rf node_modules
    npm ci

# -----------------------------------------------------------------------------
# Build
# -----------------------------------------------------------------------------

@group build
@desc "Build the project"
task build:
    npm run build

@group build
@desc "Build in watch mode"
task build-watch:
    npm run build -- --watch

# -----------------------------------------------------------------------------
# Development
# -----------------------------------------------------------------------------

@group dev
@desc "Start development server"
task dev:
    npm run dev

@group dev
@desc "Start development server with debugging"
task debug:
    NODE_OPTIONS='--inspect' npm run dev

# -----------------------------------------------------------------------------
# Test
# -----------------------------------------------------------------------------

@group test
@desc "Run all tests"
task test:
    npm test

@group test
@desc "Run tests in watch mode"
task test-watch:
    npm test -- --watch

@group test
@desc "Run tests with coverage"
task coverage:
    npm test -- --coverage

# -----------------------------------------------------------------------------
# Code Quality
# -----------------------------------------------------------------------------

@group lint
@desc "Run linter"
task lint:
    npm run lint

@group lint
@desc "Run linter and fix issues"
task lint-fix:
    npm run lint -- --fix

@group lint
@desc "Format code with Prettier"
task fmt:
    npx prettier --write .

@group lint
@desc "Check code formatting"
task fmt-check:
    npx prettier --check .

# -----------------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------------

@group clean
@desc "Clean build artifacts"
task clean:
    rm -rf dist/
    rm -rf build/
    rm -rf .next/
    rm -rf .nuxt/
