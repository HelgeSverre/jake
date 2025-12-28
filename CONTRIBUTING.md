# Contributing to Jake

Thank you for your interest in contributing to Jake!

## Development Setup

1. Install [Zig](https://ziglang.org/) 0.14 or later
2. Clone the repository:
   ```bash
   git clone https://github.com/HelgeSverre/jake.git
   cd jake
   ```
3. Build and test:
   ```bash
   zig build
   zig build test
   ```

## Project Structure

```
jake/
├── src/
│   ├── main.zig          # CLI entry point
│   ├── root.zig          # Library exports
│   ├── lexer.zig         # Tokenizer
│   ├── parser.zig        # AST builder
│   ├── executor.zig      # Recipe execution
│   ├── parallel.zig      # Parallel execution
│   ├── cache.zig         # File change detection
│   ├── glob.zig          # Glob pattern matching
│   ├── import.zig        # Import resolution
│   ├── watch.zig         # File watcher
│   ├── env.zig           # Environment handling
│   ├── conditions.zig    # Conditional logic
│   └── hooks.zig         # Pre/post hooks
├── samples/              # E2E test samples
├── GUIDE.md             # User documentation
└── README.md            # Project overview
```

## Running Tests

```bash
# Unit tests
zig build test

# E2E tests
cd samples && ../zig-out/bin/jake test-all
```

## Code Style

- Follow Zig's standard style
- Run `zig fmt src/` before committing
- Keep functions focused and well-documented
- Add tests for new features

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run tests: `zig build test`
5. Format code: `zig fmt src/`
6. Commit with a clear message
7. Push and create a Pull Request

## Commit Messages

Use clear, descriptive commit messages:

```
feat: add watch mode for automatic rebuilds
fix: handle glob patterns with special characters
docs: update user guide with new examples
test: add E2E tests for import system
```

## Reporting Issues

When reporting bugs, please include:
- Jake version (`jake --version`)
- Operating system
- Minimal Jakefile to reproduce
- Expected vs actual behavior
- Full error message

## Feature Requests

We welcome feature ideas! Please:
- Check existing issues first
- Describe the use case
- Provide example syntax if applicable

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
