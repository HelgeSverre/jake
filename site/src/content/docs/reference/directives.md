---
title: Directives
description: All Jake directives reference.
---

## Global Directives

Placed at the top level of a Jakefile (outside any recipe).

| Directive                | Description                                                                 |
| ------------------------ | --------------------------------------------------------------------------- |
| `@default`               | Mark the next recipe as the default (runs when you invoke `jake` with no args) |
| `@dotenv`                | Load `.env` from the current working directory                              |
| `@dotenv "path"`         | Load a specific env file                                                    |
| `@export VAR=value`      | Export an environment variable to all subprocess commands                   |
| `@require VAR...`        | Require environment variables to be set — Jake exits with an error if any are missing |
| `@import "path"`         | Import all recipes from another Jakefile                                    |
| `@import "path" as name` | Import with a namespace prefix (recipes become `name.recipe`)               |
| `@rooted`                | Resolve this file's recipe relative paths (`@cd`, `file` targets) against its own directory when imported (see below) |
| `@pre command`           | Global pre-hook — runs before every recipe                                  |
| `@post command`          | Global post-hook — runs after every recipe                                  |
| `@before recipe command` | Targeted pre-hook — runs before a specific recipe only                      |
| `@after recipe command`  | Targeted post-hook — runs after a specific recipe only                      |
| `@on_error command`      | Global error hook — runs if any recipe fails. For recipe-specific error hooks, use `@on_error` inside the recipe body. |

### @rooted

By default, an imported file's relative paths (`@cd`, `file` targets, relative paths in command bodies) resolve against the **root** Jakefile's directory. `@rooted` opts a file into resolving **its own** recipes' relative paths against **its own** directory when imported from a parent — so you can compose independent sub-project Jakefiles (a `workspace` meta-repo whose sub-directories are self-contained projects).

```jake
# services/api/Jakefile
@rooted

task build:
    cargo build          # runs in services/api/

file dist/bundle.js: src/*.ts
    esbuild src/index.ts --bundle --outfile=dist/bundle.js   # dist/ under services/api/
```

```jake
# workspace Jakefile
@import "services/api/Jakefile" as api

task build: [api.build]
    echo "Workspace build complete"
```

`@rooted` takes no arguments and is backward-compatible — files without it keep the default root-relative behaviour (so `@import "jake/rust.jake"` can still reference repo-root paths like `crates/...`). Running a `@rooted` file directly as the root Jakefile is a no-op, since its directory is already the working directory.

## Recipe Modifiers

Placed immediately before a recipe definition (no blank lines between).

| Directive                               | Description                                              |
| --------------------------------------- | -------------------------------------------------------- |
| `@desc "text"`                          | Description shown in `jake --list` output                |
| `@alias name...`                        | Alternate names for the next recipe (`jake <alias>` runs it) |
| `@group name`                           | Group recipes together in `jake --list` output           |
| `@platform os...`                       | Only register this recipe on the specified OS(es)        |
| `@quiet`                                | Suppress command echoing for this recipe                 |
| `@hidden`                               | Hide from `jake --list` (same as `_` name prefix)       |
| `@timeout duration`                     | Kill the recipe if it runs longer than `duration`        |
| `@needs cmd...`                         | Require commands to exist in PATH before running         |

### @timeout

Accepts `s` (seconds), `m` (minutes), or `h` (hours). The recipe process is killed when the duration is exceeded.

```jake
@timeout 30s
task health-check:
    curl https://example.com/health

@timeout 5m
task integration-test:
    npm run test:integration

@timeout 2h
task full-pipeline:
    ./scripts/ci.sh
```

### @needs

Check that tools exist before attempting to run. If a command is missing, Jake stops with a clear error.

```jake
@needs docker npm node
task build:
    docker build -t myapp .
    npm run build

# With installation hint
@needs terraform "Install from https://terraform.io"
task infra:
    terraform apply

# With auto-install recipe
@needs brew -> install-brew
task setup:
    brew install ripgrep
```

### @platform

Valid values: `linux`, `macos`, `windows`. You can list multiple — the recipe is registered if the current OS matches any of them.

```jake
@platform linux macos
task set-permissions:
    chmod +x ./scripts/*.sh

@platform windows
task set-permissions:
    icacls scripts\*.bat /grant Everyone:F
```

## Recipe Directives

Used inside recipe bodies.

| Directive              | Description                                                                       |
| ---------------------- | --------------------------------------------------------------------------------- |
| `@pre command`         | Run before this recipe's commands                                                 |
| `@post command`        | Run after this recipe's commands (runs even if the recipe fails)                  |
| `@confirm "message"`   | Prompt for confirmation before continuing                                         |
| `@needs cmd...`        | Require commands exist (same as recipe modifier, but scoped to this recipe body)  |
| `@needs cmd "hint"`    | With installation hint shown if command is missing                                |
| `@needs cmd -> recipe` | With auto-install recipe that runs if command is missing                          |
| `@cd path`             | Change working directory for all subsequent commands in this recipe               |
| `@shell name`          | Use a different shell for all commands in this recipe (e.g., `bash`, `fish`, `pwsh`) |
| `@ignore`              | Continue to the next command even if the previous command failed                  |
| `@cache pattern...`    | Skip the recipe if none of the matched files have changed since last run          |
| `@watch pattern...`    | Register additional file patterns to watch in `-w` mode                           |
| `@timeout duration`    | Kill this recipe if it runs longer than the specified duration                     |
| `@launch target`       | Open a file or URL with the OS-default app (`open` / `xdg-open` / `start`)        |

### @ignore

Normally a failing command stops the recipe. `@ignore` marks the *next* command as non-fatal. Place it on its own line, immediately before the command:

```jake
task clean:
    @ignore
    rm -rf dist/             # ok if dist/ doesn't exist
    @ignore
    rm -rf node_modules/
    echo "Cleaned up"
```

Putting the command on the same line as `@ignore` (e.g. `@ignore rm -rf dist/`) is a common mistake — the trailing text is treated as part of the directive and the command is silently dropped.

### @cd

Changes the working directory for all subsequent commands in the recipe:

```jake
task build-frontend:
    @cd frontend
    npm install
    npm run build
```

### @shell

Switches the shell used to execute commands. Useful for fish syntax or PowerShell:

```jake
task fish-example:
    @shell fish
    for f in *.ts
        echo $f
    end
```

### @cache

Skips the recipe if none of the matched files have changed since the last successful run. Useful for tasks with no file output target but expensive to run:

```jake
task lint:
    @cache src/**/*.ts
    eslint src/
```

## Control Flow

| Directive         | Description                    |
| ----------------- | ------------------------------ |
| `@if condition`   | Conditional start              |
| `@elif condition` | Else-if branch                 |
| `@else`           | Else branch                    |
| `@end`            | End a conditional or loop block |
| `@each items...`  | Loop over a list of items      |

See [Conditionals](/docs/conditionals/) for condition function reference.

## Command Prefix: `@`

Prefixing any command line with `@` suppresses echoing for just that command (without silencing all output):

```jake
task build:
    @echo "Building quietly..."   # not echoed to terminal
    npm run build                 # echoed normally
```

This is distinct from the `@quiet` recipe modifier, which suppresses echoing for all commands in the recipe.
