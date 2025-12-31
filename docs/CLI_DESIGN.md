# Jake CLI Design Specification

This document defines the visual design language for Jake's command-line interface output.

## Color Palette

### Brand Colors (True Color / 24-bit)

| Name | Hex | RGB | ANSI Code | Usage |
|------|-----|-----|-----------|-------|
| Jake Rose | `#f43f5e` | 244,63,94 | `\x1b[38;2;244;63;94m` | Recipe names, branding |
| Success | `#22c55e` | 34,197,94 | `\x1b[38;2;34;197;94m` | Checkmarks, completion |
| Error | `#ef4444` | 239,68,68 | `\x1b[38;2;239;68;68m` | Failures, errors |
| Warning | `#eab308` | 234,179,8 | `\x1b[38;2;234;179;8m` | Warnings, skipped |
| Info | `#60a5fa` | 96,165,250 | `\x1b[38;2;96;165;250m` | Arrows, info text |
| Muted | `#71717a` | 113,113,122 | `\x1b[38;2;113;113;122m` | Comments, secondary |

### Fallback Colors (16-color ANSI)

For terminals without true color support:

| Brand Color | Fallback ANSI | Code |
|-------------|---------------|------|
| Jake Rose | Bold Magenta | `\x1b[1;35m` |
| Success | Bold Green | `\x1b[1;32m` |
| Error | Bold Red | `\x1b[1;31m` |
| Warning | Bold Yellow | `\x1b[1;33m` |
| Info | Bold Blue | `\x1b[1;34m` |
| Muted | Dark Gray | `\x1b[90m` |

## Symbols

| Symbol | Unicode | Usage |
|--------|---------|-------|
| Arrow | `→` (U+2192) | Recipe execution start |
| Success | `✓` (U+2713) | Task completed |
| Failure | `✗` (U+2717) | Task failed |
| Warning | `~` | Skipped/warning |

## Output Formats

### Task Execution

```
$ jake build
→ build
  cargo build --release
✓ build (2.4s)
```

With dependencies:
```
$ jake deploy
→ build
  cargo build --release
✓ build (2.4s)
→ test
  cargo test
✓ test (1.2s)
→ deploy
  ./deploy.sh production
✓ deploy (0.8s)
```

### Recipe List (`jake -l`)

```
$ jake -l
Available recipes:

build:
  build        [task]  Build the application
  clean        [task]  Remove build artifacts

test:
  test         [task]  Run all tests
  test-unit    [task]  Run unit tests only

(2 hidden recipes)
```

With `--all`:
```
$ jake -la
Available recipes:

build:
  build        [task]  Build the application

(hidden):
  _helper      [task]  Internal helper
```

### Error Messages

Recipe not found:
```
$ jake buidl
error: Recipe 'buidl' not found

Did you mean: build?

Run 'jake -l' to see available recipes.
```

Command failed:
```
$ jake test
→ test
  npm test
✗ test (failed)

error: Command exited with code 1
```

Missing dependency:
```
$ jake deploy
error: Required command not found: helm

hint: Install with: brew install helm
```

### Watch Mode

```
$ jake -w build
[watch] Watching src/**/*.ts
→ build
  npm run build
✓ build (0.82s)

[watch] Changed: src/index.ts
→ build
  npm run build
✓ build (0.34s)

Press Ctrl+C to stop watching
```

### Dry Run (`jake -n`)

```
$ jake -n deploy
[dry-run] Would execute:

→ build
  would run: cargo build --release

→ test
  would run: cargo test

→ deploy
  would run: ./deploy.sh production

3 tasks would run (not executed)
```

### Recipe Inspection (`jake -s`)

```
$ jake -s deploy
Recipe: deploy
Type: task
Group: production
Doc: Deploy to production servers

Dependencies:
  build, test

Commands:
  @confirm "Deploy to production?"
  ./scripts/deploy.sh $env

Quiet: no
```

For hidden recipes:
```
$ jake -s _helper
Recipe: _helper (hidden)
Type: task
...
```

## Semantic Color Mapping

| Element | Color | Notes |
|---------|-------|-------|
| Recipe name (execution) | Jake Rose | `→ build` |
| Recipe name (listing) | Jake Rose | In recipe lists |
| Success message | Success Green | `✓ build` |
| Error message | Error Red | `error:`, `✗` |
| Warning message | Warning Yellow | `warning:`, `~` |
| Group header | Jake Rose (bold) | `build:` |
| Section header | Bold | `Available recipes:` |
| Hidden marker | Muted | `(hidden)` |
| Type badge | Muted | `[task]`, `[file]` |
| Description | Muted | `# comment text` |
| Directive | Warning Yellow | `@needs`, `@confirm` |
| Hook label | Success Green | `@pre`, `@post` |
| Watch prefix | Info Blue | `[watch]` |
| Dry-run prefix | Info Blue | `[dry-run]` |

## Implementation Notes

### Color Detection

1. Check `NO_COLOR` environment variable - if set, disable all colors
2. Check `CLICOLOR_FORCE` - if set and non-zero, force colors even without TTY
3. Check `CLICOLOR` - if set to 0, disable colors
4. Check if stderr is a TTY - enable colors if true
5. Check `COLORTERM=truecolor` or `COLORTERM=24bit` for true color support
6. Fall back to 16-color ANSI if true color not detected

### Theme Structure

```
Theme (semantic layer)
├── err()           → Error Red
├── warning()       → Warning Yellow
├── success()       → Success Green
├── recipe()        → Jake Rose
├── hidden()        → Muted
├── group()         → Jake Rose Bold
├── section()       → Bold
├── directive()     → Warning Yellow
├── hook()          → Success Green
├── muted()         → Muted
└── info()          → Info Blue
```
