---
title: Built-in Functions
description: Functions available in variable expansion.
---

Call functions inside `{{...}}` expressions. Arguments can be literal strings or variable names — Jake resolves variable names first, then passes the value to the function.

```jake
src = "src/components/Button.tsx"

task info:
    echo "{{basename(src)}}"         # uses variable → Button.tsx
    echo "{{basename(lib/util.ts)}}" # literal       → util.ts
```

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

| Function           | Description                             | Example                                                              |
| ------------------ | --------------------------------------- | -------------------------------------------------------------------- |
| `home()`           | User home directory                     | `{{home()}}` → `/Users/alice` or `C:\Users\alice`                    |
| `local_bin(name)`  | Path to `~/.local/bin` binary           | `{{local_bin(jake)}}` → `/Users/alice/.local/bin/jake`               |
| `shell_config()`   | Current shell's config file             | `{{shell_config()}}` → `/Users/alice/.zshrc`                         |
| `launch(target)`   | Platform command to open a file or URL  | `{{launch(https://example.com)}}` → `open https://example.com`       |

### launch(target)

`launch()` returns the platform-specific command for opening a file or URL in the default application. It doesn't open the target directly — it expands to the correct command, which then runs as part of the recipe.

| Platform | Expands to               |
| -------- | ------------------------ |
| macOS    | `open {target}`          |
| Linux    | `xdg-open {target}`      |
| Windows  | `cmd /c start "" {target}` |

```jake
docs_url = "https://jake.helge.dev"

task open-docs:
    {{launch(docs_url)}}

task open-report:
    {{launch(coverage/index.html)}}
```

On unsupported platforms (anything other than macOS, Linux, or Windows), `launch()` produces an error at evaluation time and the recipe will not run.

### Shell Config Detection

`shell_config()` detects your shell from `$SHELL`. On Windows, it understands Windows-style shell paths and falls back to PowerShell or `COMSPEC` when needed.

| Shell      | Config File                                                               |
| ---------- | ------------------------------------------------------------------------- |
| bash       | `~/.bashrc`                                                               |
| zsh        | `~/.zshrc`                                                                |
| fish       | `~/.config/fish/config.fish`                                              |
| sh         | `~/.profile`                                                              |
| ksh        | `~/.kshrc`                                                                |
| csh / tcsh | `~/.cshrc` / `~/.tcshrc`                                                  |
| powershell | `~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1`          |
| pwsh       | `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`                 |

`shell_config()` returns nothing for plain `cmd.exe`. `home()` resolves from `HOME` on Unix and from `HOME`, `USERPROFILE`, or `HOMEDRIVE` + `HOMEPATH` on Windows.

## Composing Functions

Each `{{...}}` expansion takes a single function call. Nested calls inside a single
expansion (e.g. `{{outer(inner(x))}}`) are **not** evaluated recursively — the inner
text is passed to `outer` as a literal string. Use one of these patterns instead:

**Top-level variable for the intermediate value:**

```jake
src      = "src/main.ts"
src_base = "main"   # precomputed

task compile:
    tsc --outFile {{src_base}}.js {{src}}
```

**Shell substitution inside the command** (cleanest when the intermediate isn't
reused):

```jake
src = "src/main.ts"

task compile:
    tsc --outFile $(basename {{src}} .ts).js {{src}}
```

```jake
component = "src/components/Button.tsx"

task deploy-component:
    cp {{component}} dist/$(basename {{component}} .tsx | tr A-Z a-z).js
```

## Error Behavior

If a function receives an argument it can't handle (e.g., `launch()` on an unsupported OS), Jake reports the error and stops before executing any commands in the recipe. The error identifies the failing expression.

If the argument to a function is an identifier that doesn't match any defined variable, Jake passes the literal identifier text through to the function. So `{{basename(unknown)}}` becomes `basename("unknown")` → `unknown`. This is intentional: it lets you write `{{basename(src/main.ts)}}` without quoting. If you want the empty-string-on-undefined behavior, define the variable up top with an empty default:

```jake
maybe = ""

task show:
    echo "{{basename(maybe)}}"   # prints empty
```
