---
title: CLI Options
description: Jake command line reference.
---

## Usage

```
jake [OPTIONS] [RECIPE] [ARGS...]
```

## Arguments

| Argument | Description                                         |
| -------- | --------------------------------------------------- |
| `RECIPE` | Recipe to run (default: first recipe or `@default`) |
| `ARGS`   | Recipe parameters (`name=value`) and positional args |

## Options

| Option              | Short | Description                         |
| ------------------- | ----- | ----------------------------------- |
| `--help`            | `-h`  | Show help message                   |
| `--version`         | `-V`  | Show version                        |
| `--list`            | `-l`  | List available recipes              |
| `--all`             | `-a`  | Show all recipes including hidden   |
| `--dry-run`         | `-n`  | Print commands without executing    |
| `--verbose`         | `-v`  | Show verbose output                 |
| `--yes`             | `-y`  | Auto-confirm all `@confirm` prompts |
| `--jakefile PATH`   | `-f`  | Use specified Jakefile              |
| `--watch [PATTERN]` | `-w`  | Watch and re-run on changes         |
| `--jobs [N]`        | `-j`  | Parallel jobs (default: CPU count)  |
| `--show RECIPE`     | `-s`  | Show recipe details                 |
| `--summary`         |       | Print recipe names for scripts      |
| `--short`           |       | Output one recipe name per line     |
| `--json`            |       | Emit JSON for listing-style output  |
| `--group GROUP`     |       | Filter recipes to a specific group  |
| `--filter PATTERN`  |       | Filter recipe names by glob pattern |
| `--type TYPE`       |       | Filter recipes by type (`task`, `file`, `simple`, `external`) |
| `--groups`          |       | List available group names          |
| `--web`             |       | Start web UI server                 |
| `--port PORT`       |       | Web UI port (default: 8420)         |
| `--external [TYPE]` |       | Show external recipes (make/just)   |
| `--no-external`     |       | Hide external recipes from listing  |
| `--completions [SHELL]` |   | Print shell completion script       |
| `--install`         |       | Install shell completions           |
| `--uninstall`       |       | Remove shell completions            |
| `--fmt`             |       | Format Jakefile                     |
| `--check`           |       | Validate formatting (requires `--fmt`) |
| `--dump`            |       | Print formatted Jakefile (requires `--fmt`) |

## Examples

```bash
# Run default recipe
jake

# Run specific recipe
jake build

# List all recipes including hidden
jake --list --all

# Run with verbose output
jake test --verbose

# Pass parameters
jake deploy env=production

# Run with 4 parallel jobs
jake -j4 all

# Watch and rebuild
jake -w build

# Dry-run (show what would execute)
jake -n deploy

# Use different Jakefile
jake -f build.jake test

# Auto-confirm prompts
jake -y deploy

# Machine-readable output
jake --summary
jake --list --short
jake --json
jake --summary --json
jake --groups --json

# Filter listings
jake --group dev --list --short
jake --filter "build*" --summary
jake --type file --summary
jake --groups

# Validate formatting
jake --fmt --check -f build.jake

# Start web UI
jake --web
jake --web --port 9000
jake --web --verbose
jake --web -j4

# List external build system recipes
jake --external
jake --external make
jake --external just

# Run external recipes
jake make.build
jake just.test

# External discovery follows the selected Jakefile
jake -f tools/Jakefile make.build
```

When `-f` points at a Jakefile in another directory, external Makefile/Justfile discovery and delegated execution use that Jakefile's directory as the base path.

Web UI runs inherit the CLI process' `--verbose` and `--jobs` settings, forward browser-entered recipe params as `name=value`, validate `@require` before execution, and surface `@confirm` prompts back to the browser for interactive approval.

## Exit Codes

| Code | Meaning            |
| ---- | ------------------ |
| 0    | Success            |
| 1    | Recipe failed      |
| 2    | Recipe not found   |
| 3    | Jakefile not found |
| 4    | Parse error        |

## Environment Variables

| Variable    | Description            |
| ----------- | ---------------------- |
| `JAKEFILE`  | Default Jakefile path  |
| `JAKE_DRY_RUN` | Enable dry-run mode |
| `JAKE_VERBOSE` | Enable verbose output |
| `JAKE_YES` | Auto-confirm prompts |
| `JAKE_JOBS` | Default parallel job count |
| `NO_COLOR` | Disable colored output |
