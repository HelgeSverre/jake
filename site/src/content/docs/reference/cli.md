---
title: CLI Options
description: Jake command line reference.
---

## Usage

```
jake [OPTIONS] [RECIPE] [ARGS...]
```

## Arguments

| Argument | Description |
|----------|-------------|
| `RECIPE` | Recipe to run (default: first recipe or `@default`) |
| `ARGS` | Recipe arguments in `name=value` format |

## Options

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message |
| `--version` | `-V` | Show version |
| `--list` | `-l` | List available recipes |
| `--dry-run` | `-n` | Print commands without executing |
| `--verbose` | `-v` | Show verbose output |
| `--yes` | `-y` | Auto-confirm all `@confirm` prompts |
| `--jakefile PATH` | `-f` | Use specified Jakefile |
| `--watch [PATTERN]` | `-w` | Watch and re-run on changes |
| `--jobs [N]` | `-j` | Parallel jobs (default: CPU count) |

## Examples

```bash
# Run default recipe
jake

# Run specific recipe
jake build

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
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Recipe failed |
| 2 | Recipe not found |
| 3 | Jakefile not found |
| 4 | Parse error |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `JAKE_FILE` | Default Jakefile path |
| `NO_COLOR` | Disable colored output |
