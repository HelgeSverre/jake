---
title: Shell Completions
description: Set up tab completion for Jake in your shell.
---

Jake provides tab completion for recipe names and flags in bash, zsh, and fish.

## Quick Install

The easiest way to set up completions:

```bash
jake --completions --install
```

This automatically detects your shell and installs completions to the appropriate location.

## Manual Installation

Generate the completion script and save it:

### Bash

```bash
jake --completions bash > ~/.local/share/bash-completion/completions/jake
```

### Zsh

```bash
jake --completions zsh > ~/.zsh/completions/_jake
```

You may need to add the completions directory to your `fpath` in `~/.zshrc`:

```zsh
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

### Fish

```bash
jake --completions fish > ~/.config/fish/completions/jake.fish
```

## Environment Detection

The `--install` command automatically detects your zsh environment:

| Environment      | Install Location                                  | Configuration           |
| ---------------- | ------------------------------------------------- | ----------------------- |
| **Oh-My-Zsh**    | `~/.oh-my-zsh/custom/completions/_jake`           | None needed             |
| **Homebrew zsh** | `/opt/homebrew/share/zsh/site-functions/_jake`    | None needed             |
| **Vanilla zsh**  | `~/.zsh/completions/_jake`                        | Auto-patches `~/.zshrc` |
| **Bash**         | `~/.local/share/bash-completion/completions/jake` | None needed             |
| **Fish**         | `~/.config/fish/completions/jake.fish`            | None needed             |

For vanilla zsh, the installer adds a configuration block to `~/.zshrc`:

```zsh
# >>> jake completion >>>
# This block is managed by jake. Do not edit manually.
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit -u
# <<< jake completion <<<
```

## Uninstalling

Remove completions and configuration:

```bash
jake --completions --uninstall
```

This removes the completion file and cleans up any `.zshrc` modifications.

## What Gets Completed

Tab completion works for:

- **Recipe names** - Dynamically loaded from your Jakefile
- **CLI flags** - All options like `--list`, `--dry-run`, `--verbose`
- **Flag values** - File paths for `-f/--jakefile`, shell names for `--completions`

## Using Completions

After installation, restart your shell (or source your config file):

```bash
# Complete recipe names
jake bu<TAB>        # → jake build

# Complete flags
jake --<TAB>        # Shows all available flags

# Complete flag values
jake --completions <TAB>    # → bash, zsh, fish
jake -f <TAB>               # → file completion
```

## Machine-Readable Output

For scripting and integration with other tools:

```bash
# Space-separated list of recipe names
jake --summary
# Output: build test deploy clean lint

# One recipe per line
jake -l --short

# Use in scripts
for recipe in $(jake --summary); do
    echo "Found recipe: $recipe"
done
```

## Troubleshooting

### Completions Not Working

1. Restart your shell after installation
2. Verify the completion file exists:
   ```bash
   ls ~/.zsh/completions/_jake  # zsh
   ls ~/.config/fish/completions/jake.fish  # fish
   ```
3. For zsh, ensure `compinit` is called in your config

### Wrong Recipes Showing

Completions load recipes from the Jakefile in the current directory. Make sure you're in the right project directory.

### Slow Completions

Recipe names are loaded dynamically. If you have a very large Jakefile with many imports, completions might be slightly delayed.
