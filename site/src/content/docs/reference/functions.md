---
title: Built-in Functions
description: Functions available in variable expansion.
---

Use functions in variable expansion with `{{function(arg)}}` syntax.

## String Functions

| Function       | Description          | Example                          |
| -------------- | -------------------- | -------------------------------- |
| `uppercase(s)` | Convert to uppercase | `{{uppercase(hello)}}` → `HELLO` |
| `lowercase(s)` | Convert to lowercase | `{{lowercase(HELLO)}}` → `hello` |
| `trim(s)`      | Remove whitespace    | `{{trim( hello )}}` → `hello`    |

## Path Functions

| Function                | Description           | Example                                               |
| ----------------------- | --------------------- | ----------------------------------------------------- |
| `dirname(p)`            | Get directory part    | `{{dirname(/a/b/c.txt)}}` → `/a/b`                    |
| `basename(p)`           | Get filename part     | `{{basename(/a/b/c.txt)}}` → `c.txt`                  |
| `extension(p)`          | Get file extension    | `{{extension(file.txt)}}` → `.txt`                    |
| `without_extension(p)`  | Remove last extension | `{{without_extension(file.tar.gz)}}` → `file.tar`     |
| `without_extensions(p)` | Remove ALL extensions | `{{without_extensions(file.tar.gz)}}` → `file`        |
| `absolute_path(p)`      | Get absolute path     | `{{absolute_path(./src)}}` → `/home/user/project/src` |

## System Functions

| Function          | Description                 | Example                                                  |
| ----------------- | --------------------------- | -------------------------------------------------------- |
| `home()`          | User home directory         | `{{home()}}` → `/Users/alice`                            |
| `local_bin(name)` | Path to ~/.local/bin binary | `{{local_bin("jake")}}` → `/Users/alice/.local/bin/jake` |
| `shell_config()`  | Current shell's config file | `{{shell_config()}}` → `/Users/alice/.zshrc`             |

### Shell Config Detection

The `shell_config()` function detects your shell from `$SHELL`:

| Shell | Config File                  |
| ----- | ---------------------------- |
| bash  | `~/.bashrc`                  |
| zsh   | `~/.zshrc`                   |
| fish  | `~/.config/fish/config.fish` |
| sh    | `~/.profile`                 |
| ksh   | `~/.kshrc`                   |
| csh   | `~/.cshrc`                   |
| tcsh  | `~/.tcshrc`                  |

## Using with Variables

```jake
file_path = "src/components/Button.tsx"

task info:
    echo "Directory: {{dirname(file_path)}}"
    echo "Filename: {{basename(file_path)}}"
    echo "Extension: {{extension(file_path)}}"
```

Output:

```
Directory: src/components
Filename: Button.tsx
Extension: .tsx
```

## Chaining with Variables

```jake
src = "src/main.ts"

task compile:
    echo "Compiling {{basename(src)}} to {{without_extension(basename(src))}}.js"
```
