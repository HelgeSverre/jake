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

### Interactive Prompts

`@confirm` prompts are forwarded to the browser so you can approve or reject them without leaving the Web UI.

Subprocess prompts are different: commands that try to read from stdin themselves, such as `npx` install prompts or other terminal-driven wizards, are not interactive in the Web UI. Browser-triggered runs disable child stdin so those commands fail instead of hanging indefinitely. Use tool-specific non-interactive flags such as `npx --yes`, or run those recipes from a terminal instead.

### Stop / Cancel

Use the stop control in the browser to cancel the active run. Jake terminates the running command tree and reports the cancellation back through the normal task output and summary stream.

### Run State and Reconnection

One execution can run at a time per server. A request from another tab is rejected
promptly while that execution is active. With `-j`, dependencies within the run
can execute in parallel; the UI tracks each active task and attaches the summary
to the requested recipe.

After a disconnect, launch controls stay disabled until the browser receives the
server's current run state. Reconnecting restores the active recipe, tasks, timer
and pending confirmation. Output produced while disconnected is not replayed.
Cancellation and failures produce one completion per started task and one run
summary. The run lock is released after execution cleanup finishes.

Dependency badges are keyboard-accessible buttons: use Tab to focus one and
Enter or Space to select its recipe.

### Console Tee

Output appears in both the browser and your terminal simultaneously. Useful when you want to keep an eye on both.

### CLI Parity

Web-triggered runs inherit the same execution settings as the CLI process that started the server:

- `--verbose` keeps verbose execution enabled
- `-j` / `--jobs` controls parallel execution
- `@require` validation runs before execution starts
- Recipe parameter values entered in the UI are forwarded as normal `name=value` arguments
- `@confirm` prompts are handled interactively in the browser
- Child-process stdin is disabled to avoid browser-triggered runs hanging on terminal-only prompts

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
