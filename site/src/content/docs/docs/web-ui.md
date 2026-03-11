---
title: Web UI
description: Interactive browser-based task runner with real-time output.
---

## Starting the Web UI

Launch an interactive browser interface:

```bash
jake --web
```

Opens a web dashboard at `http://localhost:8420` where you can:

- Browse all available recipes
- View recipe details, dependencies, and commands
- Run tasks with a single click
- Fill in recipe parameters before running
- Monitor real-time command output

Automatic browser launch is skipped when `CI` or `JAKE_NO_BROWSER` is set.

## Custom Port

Use a different port:

```bash
jake --web --port 9000
```

## Features

### Real-Time Output

Command output streams to the browser via WebSocket as it runs. No need to refresh - see results instantly.

### Console Tee

Output appears in both the browser and your terminal simultaneously. Useful when you want to keep an eye on both.

### CLI Parity

Web-triggered runs inherit the same execution settings as the CLI process that started the server:

- `--verbose` keeps verbose execution enabled
- `-j` / `--jobs` controls parallel execution
- `@require` validation runs before execution starts
- Recipe parameter values entered in the UI are forwarded as normal `name=value` arguments

`@confirm` is the current exception: Web UI runs auto-confirm for now because the browser does not yet provide an interactive confirmation prompt.

### Recipe Browser

View all your recipes with:

- Name and description
- Dependencies
- Commands that will run
- Group organization

### Private Recipe Filtering

Private recipes (names starting with `_` or marked with `@hidden`) are automatically hidden, matching `--list` behavior.

## Workflow

1. Start the server: `jake --web`
2. Open `http://localhost:8420` in your browser
3. Click a recipe to view details
4. Click "Run" to execute
5. Watch output stream in real-time
6. Press `Ctrl+C` in terminal to stop the server

## Combining with Other Flags

```bash
# Web UI with verbose output
jake --web --verbose

# Web UI with parallel execution
jake --web -j4

# Web UI with custom Jakefile
jake --web -f build.jake
```
