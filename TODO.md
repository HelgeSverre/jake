# Jake TODO

---

## NOW

### Test Coverage Gaps

**System Functions (functions.zig):**
- [ ] `home()` returns error when HOME unset
- [ ] `shell_config()` with unknown shell falls back to profile

---

## NEXT

### CLI Commands

- [ ] `jake upgrade` - Self-update from GitHub releases
  - Check version against latest release tag
  - Detect OS/arch, download appropriate binary
  - Optional signature verification (minisign)
  - `--check` flag to only check for updates

---

- [ ] `jake init` - Scaffold Jakefile from templates
  - Auto-detect project type (Node, Go, Rust, Python)
  - `--template=node` for explicit selection

---

- [ ] `jake fmt` - Auto-format Jakefile
  - Consistent 4-space indentation
  - Align `=` in variable definitions
  - Sort imports alphabetically
  - `--check` flag for CI

---

- [ ] `--json` flag - Machine-readable output
  - `--list --json` - recipes as JSON array
  - `--dry-run --json` - execution plan as JSON
  - `--vars --json` - resolved variables as JSON

---

### List Filtering

- [ ] `--group GROUP` - Filter recipes to specified group
- [ ] `--filter PATTERN` - Filter recipes by glob pattern
- [ ] `--groups` - List available group names

---

### New Directives

- [ ] `@timeout 30s` - Kill recipe if exceeds time limit
- [ ] `@retry 3` - Retry failed commands N times
- [ ] `@env-file .env.local` - Load env file for specific recipe
- [ ] `@silent` - Suppress all output (vs @quiet which hides command echo)
- [ ] `@parallel` - Run commands within recipe in parallel

---

### New Functions

- [ ] `git_branch()` - Current git branch name
- [ ] `git_hash()` - Short commit hash (7 chars)
- [ ] `git_dirty()` - Returns "dirty" if uncommitted changes
- [ ] `timestamp()` - Current Unix timestamp
- [ ] `datetime(format)` - Formatted date/time string
- [ ] `read_file(path)` - Read file contents into variable
- [ ] `json(file, path)` - Extract JSON value
- [ ] `env_or(name, default)` - Get env var with fallback

---

### New Conditions

- [ ] `file_newer(a, b)` - True if file A newer than file B
- [ ] `contains(str, sub)` - True if string contains substring
- [ ] `matches(str, pattern)` - True if string matches regex
- [ ] `is_file(path)` - True if path is a file
- [ ] `is_dir(path)` - True if path is a directory

---

## LATER

### CI/CD & Distribution

- [ ] GitHub Actions matrix testing (Linux, macOS, Windows)
- [ ] Automated release workflow (build binaries on tag)
- [ ] Homebrew formula (`brew install jake`)
- [ ] AUR package for Arch Linux
- [ ] Scoop manifest for Windows
- [ ] Nix flake
- [ ] Docker image

---

### Quality & Testing

- [ ] Benchmarks suite (track performance over time)
- [ ] Property-based/generative tests (structured fuzzing)
- [ ] Integration test suite with real-world Jakefiles
- [ ] Regression test for each bug fix

---

### Documentation

- [ ] Cookbook: Common patterns (Docker, CI, monorepo)
- [ ] Migration guide: Makefile to Jakefile
- [ ] Migration guide: Justfile to Jakefile
- [ ] Video tutorial / screencast
- [ ] Man page (`man jake`)

---

### Error Message Improvements

- [ ] Parse errors with source context (show line with caret)
- [ ] Dependency cycle visualization (`build -> test -> lint -> build`)
- [ ] `home()` failure hint when HOME unset

---

### Deferred Refactoring

- [ ] executor.zig modularization (see REFACTOR.md)
  - Extract platform.zig (~40 lines)
  - Extract system.zig (~30 lines)
  - Extract expansion.zig (~80 lines)
  - Extract directive_parser.zig (~200 lines)
  - Extract display.zig (~360 lines)

---

## IDEA

### Remote Cache Support

HTTP/S3 backend for CI/CD cache sharing. Cache key = sha256(recipe + inputs + command).

```jake
@cache-backend http "https://cache.example.com"
@cache-auth env(JAKE_CACHE_TOKEN)

file dist/bundle.js: src/**/*.ts
    @remote-cache
    esbuild src/index.ts --bundle -o dist/bundle.js
```

---

### Container Execution

Run recipe commands in Docker/Podman containers.

```jake
task build:
    @container node:20-alpine
    npm install
    npm run build
```

Runtime detection: podman > docker > nerdctl. Auto-mount pwd, forward @export vars.

---

### Workspace/Monorepo Support

Multi-package coordination with dependency ordering.

```jake
@workspace packages/*
@workspace-order topological

task build:
    @workspace-run build --parallel
```

CLI: `jake build --package=core`, `jake build --changed`, `jake --list-packages`

---

### Built-in Recipes

Common task templates embedded in binary.

```jake
@builtin docker
@builtin npm
@builtin git
```

Catalog: docker (build/push/run), npm (install/build/test), git (commit/release/changelog), go, rust.

---

### Module-Level @group

Default group for all recipes in a module file.

```jake
@group "web"

task dev:
    npm run dev
```

---

### Editor Support - Remaining

Editor integrations exist for: VS Code, Vim/Neovim, Sublime, IntelliJ, Zed, Tree-sitter, Highlight.js, Prism.js, Shiki.

**Blocked on repo being public:**
- [ ] Zed extension (uses `path` to tree-sitter grammar in monorepo)
- [ ] GitHub Linguist upstream (submit PR to github-linguist/linguist)

**Publishing:**
- [ ] Publish VS Code extension to Marketplace
- [ ] Publish IntelliJ plugin to JetBrains Marketplace
- [ ] Publish tree-sitter-jake, shiki-jake, prism-jake, highlightjs-jake to npm

---

### Language Server Protocol

Built into binary: `jake --lsp`

- Diagnostics (parse errors, unknown recipes, undefined vars)
- Completion (recipe names, directives, variables, functions)
- Hover (recipe docs, resolved variable values)
- Go to definition (dependency -> recipe, @import -> file)
- Document symbols (recipe outline)

---

### @needs Enhancements

- Shell alias detection via `type -t cmd`
- Shell function detection
- Version checking: `@needs node>=18`
