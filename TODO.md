# Jake TODO

---

## NOW

### Args Library Improvements (`src/args.zig`)

Comprehensive overhaul inspired by Clap, Cobra, Click, Typer, Commander.js, Yargs, Picocli, zig-clap.

| #  | Feature                       | Complexity | Effort | Impact | Tests |
|----|-------------------------------|:----------:|:------:|:------:|:-----:|
| 1  | "Did you mean?" suggestions   |    Low     |  2-3h  |  High  | 8-10  |
| 2  | Environment variable fallback |   Medium   |  4-6h  |  High  | 12-15 |
| 3  | Double-dash (`--`) separator  |    Low     |  1-2h  | Medium |  5-6  |
| 4  | Negatable flags (`--no-X`)    |   Medium   |  3-4h  | Medium | 10-12 |
| 5  | Repeatable flags (`-vvv`)     |    Low     |  2-3h  | Medium | 8-10  |
| 6  | Flag aliases                  |    Low     |  2-3h  |  Low   |  6-8  |
| 7  | Hidden flags                  |    Low     |   1h   |  Low   |  3-4  |
| 8  | Deprecated flag warnings      |    Low     |   2h   | Medium |  5-6  |
| 9  | Mutually exclusive groups     |   Medium   |  4-5h  | Medium | 10-12 |
| 10 | Required-together groups      |   Medium   |  4-5h  |  Low   | 8-10  |
| 11 | Default values in help        |    Low     |  1-2h  |  High  |  4-5  |
| 12 | Value validation callbacks    |   Medium   |  3-4h  | Medium | 8-10  |
| 13 | Enum/choice restrictions      |   Medium   |  3-4h  | Medium | 8-10  |
| 14 | Flag categories in help       |    Low     |  2-3h  |  High  |  4-5  |
| 15 | NO_COLOR/CLICOLOR support     |    Low     |  1-2h  | Medium |  4-6  |
| 16 | Compile-time validation       |    High    |  6-8h  |  High  |  6-8  |
| 17 | Streaming parser              |    High    | 8-12h  |  Low   | 15-20 |
| 18 | Better error messages         |   Medium   |  4-6h  |  High  | 10-12 |
| 19 | Short flag value (`-fVAL`)    |   Medium   |  3-4h  | Medium | 8-10  |
| 20 | Config file support           |    High    | 10-15h | Medium | 15-20 |

---

#### Phase 1 - Quick Wins (~6h, ~20 tests) ✓ DONE

- [x] **#11 Default values in help** - Show `(default: X)` in help text
- [x] **#3 Double-dash separator** - `--` stops flag parsing (POSIX standard)
- [x] **#7 Hidden flags** - `.hidden = true` excludes from help
- [x] **#15 NO_COLOR support** - Respect `NO_COLOR`, `CLICOLOR`, `CLICOLOR_FORCE` env vars
    - Created `src/color.zig` with runtime Color struct and writer methods
    - Created `src/context.zig` for shared execution context
    - Replaced hardcoded ANSI codes in executor.zig, parallel.zig, hooks.zig, watch.zig
    - **Remaining:** Early error messages in `args.zig` and `main.zig` use comptime `ansi.err_prefix` - would need
      refactoring to use runtime color detection

---

#### Phase 2 - High Impact (~12h, ~30 tests)

- [ ] **#1 "Did you mean?" suggestions** - Levenshtein for unknown flags (reuse suggest.zig)
    - `error: Unknown option: --vrsbose` → `Did you mean '--verbose'?`
- [ ] **#14 Flag categories in help** - Group flags by category
  ```
  GENERAL OPTIONS:
      -h, --help          Show help
  EXECUTION OPTIONS:
      -n, --dry-run       Print without executing
  ```
- [ ] **#8 Deprecated flag warnings** - `.deprecated = "Use --new instead"`
- [ ] **#5 Repeatable/countable flags** - `-vvv` → `verbose_level = 3`

---

#### Phase 3 - Medium Effort (~18h, ~45 tests)

- [ ] **#2 Environment variable fallback** - `.env = "JAKEFILE"` for flag defaults
    - Precedence: CLI arg → env var → default
- [ ] **#18 Better error messages** - Rich context with usage hint
  ```
  error: Invalid value for --jobs: "abc"
         Expected a positive integer
  Usage: jake --jobs [N] [RECIPE]
  ```
- [ ] **#4 Negatable boolean flags** - `--no-verbose` to explicitly disable
- [ ] **#13 Enum/choice restrictions** - `.choices = &.{"json", "yaml", "toml"}`

---

#### Phase 4 - Advanced (~25h, ~45 tests)

- [ ] **#16 Compile-time validation** - Verify Args struct matches flags array
- [ ] **#9 Mutually exclusive groups** - `--list` and `--show` can't be used together
- [ ] **#10 Required-together groups** - If `--username`, must also have `--password`
- [ ] **#12 Value validation callbacks** - Custom validation functions
- [ ] **#6 Flag aliases** - `.aliases = &.{"dryrun", "simulate"}` for `--dry-run`
- [ ] **#19 Short flag value attachment** - `-fcustom.jake` (generalize `-j4`)
- [ ] **#17 Streaming parser** - Process args incrementally for early exit
- [ ] **#20 Config file support** - Load defaults from `.jakeconfig`

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

- [x] `jake fmt` - Auto-format Jakefile
    - [x] Consistent 4-space indentation
    - [x] Align `=` in variable definitions
    - [ ] Sort imports alphabetically (deferred to v2)
    - [x] `--check` flag for CI
    - [x] `--dump` flag for stdout output

---

- [ ] `--json` flag - Machine-readable output
    - `--list --json` - recipes as JSON array
    - `--dry-run --json` - execution plan as JSON
    - `--vars --json` - resolved variables as JSON

---

### List Filtering

- [ ] `--group GROUP` - Filter recipes to specified group (aka, show only "dev" commands with `jake --group dev`, etc.)
- [ ] `--filter PATTERN` - Filter recipes by glob pattern: `jake --filter "test*"` shows all recipes starting with "test"
- [ ] `--type TYPE` - Filter recipes by type: `jake --type file` or `jake --type task` or `jake --type simple` (?)
- [ ] `--groups` - List available group names

---

### Remote commands (task runs on ssh server, ala laravel envoy)

```
task backup:
    @remote 

```

---

### New Directives

- [ ] `@timeout 30s` - Kill recipe if exceeds time limit
- [ ] `@retry 3` - Retry failed commands N times
- [ ] `@env-file .env.local` - Load env file for specific recipe
- [ ] `@silent` - Suppress all output (vs @quiet which hides command echo)
- [ ] `@parallel` - Run commands within recipe in parallel

---

### New Functions

- [ ] `git_branch()` - Current git branch name (e.g. `main`, `feature/x`)
- [ ] `git_hash()` - Short commit hash (7 chars), e.g. `a1b2c3d`
- [ ] `git_dirty()` - Returns "dirty" if uncommitted changes (or true/false?)
- [ ] `git_author_name()` - Current git author name
- [ ] `git_author_email()` - Current git author email
- [ ] `git_tag()` - Current git tag (or empty string)
- [ ] `uuid()` - Generate a random UUIDv4
- [ ] `unix()` - Shorthand/alias for `timestamp()`
- [ ] `kebab()` - Example Text -> example-text 
- [ ] `snake()` - Example Text -> example_text 
- [ ] `upper()` - Example Text -> EXAMPLE TEXT 
- [ ] `lower()` - Example Text -> example text 
- [ ] `timestamp()` - Current Unix timestamp (seconds since epoch, 1970-01-01 eg: `1700000000` -> `Tue Nov 14 2023 22:13:20 GMT+0000`)
- [ ] `datetime(format)` - Formatted date/time string (Which format patterns? PHP, JS, Python?)
- [ ] `read_file(path)` - Read file contents into variable
- [ ] `json(file, path)` - Extract JSON value
- [ ] `env_or(name, default)` - Get env var with fallback (maybe)

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

---

#### Homebrew Formula

Custom tap approach (homebrew-core requires source builds and 500+ stars).

**Repository:** `github.com/<user>/homebrew-tap`

**Files needed:**
- `Formula/jake.rb` - Ruby formula with platform conditionals

**Formula structure:**
```ruby
class Jake < Formula
  desc "Modern command runner/build system written in Zig"
  homepage "https://github.com/<user>/jake"
  version "X.Y.Z"
  license "MIT"

  # Platform-specific binaries
  if OS.mac? && Hardware::CPU.intel?
    url "https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-macos-x86_64.tar.gz"
    sha256 "..."
  end
  if OS.mac? && Hardware::CPU.arm?
    url "https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-macos-aarch64.tar.gz"
    sha256 "..."
  end
  if OS.linux? && Hardware::CPU.intel?
    url "https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-linux-x86_64.tar.gz"
    sha256 "..."
  end
  if OS.linux? && Hardware::CPU.arm?
    url "https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-linux-aarch64.tar.gz"
    sha256 "..."
  end

  def install
    bin.install "jake"
    bash_completion.install "completions/jake.bash" => "jake"
    zsh_completion.install "completions/_jake"
    fish_completion.install "completions/jake.fish"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/jake --version")
  end
end
```

**User installation:** `brew install <user>/tap/jake`

**Checklist:**
- [ ] Create `homebrew-tap` repository
- [ ] Add `Formula/jake.rb`
- [ ] Include shell completions in release tarballs
- [ ] Add GitHub Action to auto-update formula on release
- [ ] Document in README

---

#### AUR Package (Arch Linux)

Binary package with `-bin` suffix convention.

**Package name:** `jake-bin`

**Files needed:**
- `PKGBUILD` - Build script
- `.SRCINFO` - Generated metadata (via `makepkg --printsrcinfo > .SRCINFO`)
- `LICENSE` - 0BSD for the PKGBUILD itself

**PKGBUILD structure:**
```bash
# Maintainer: Name <email>
pkgname=jake-bin
pkgver=X.Y.Z
pkgrel=1
pkgdesc="Modern command runner/build system written in Zig"
arch=('x86_64' 'aarch64')
url="https://github.com/<user>/jake"
license=('MIT')
depends=('glibc')
provides=('jake')
conflicts=('jake' 'jake-git')

source_x86_64=("${url}/releases/download/v${pkgver}/jake-linux-x86_64.tar.gz")
source_aarch64=("${url}/releases/download/v${pkgver}/jake-linux-aarch64.tar.gz")
sha256sums_x86_64=('...')
sha256sums_aarch64=('...')

package() {
    install -Dm755 jake "$pkgdir/usr/bin/jake"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    # Shell completions
    install -Dm644 completions/jake.bash "$pkgdir/usr/share/bash-completion/completions/jake"
    install -Dm644 completions/_jake "$pkgdir/usr/share/zsh/site-functions/_jake"
    install -Dm644 completions/jake.fish "$pkgdir/usr/share/fish/vendor_completions.d/jake.fish"
}
```

**Publishing:**
1. Create AUR account, add SSH key
2. `git clone ssh://aur@aur.archlinux.org/jake-bin.git`
3. Add PKGBUILD, generate .SRCINFO
4. `git push`

**Checklist:**
- [ ] Create AUR account
- [ ] Add SSH key to AUR profile
- [ ] Create and test PKGBUILD locally (`makepkg -si`)
- [ ] Push to AUR
- [ ] Monitor for out-of-date flags

---

#### Scoop Manifest (Windows)

Custom bucket approach (Main bucket requires 500+ stars/150+ forks).

**Repository:** `github.com/<user>/scoop-jake` (or `jake-bucket`)

**Files needed:**
- `bucket/jake.json` - JSON manifest

**Manifest structure:**
```json
{
  "version": "X.Y.Z",
  "description": "Modern command runner/build system written in Zig",
  "homepage": "https://github.com/<user>/jake",
  "license": "MIT",
  "architecture": {
    "64bit": {
      "url": "https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-windows-x86_64.zip",
      "hash": "sha256:..."
    },
    "arm64": {
      "url": "https://github.com/<user>/jake/releases/download/vX.Y.Z/jake-windows-aarch64.zip",
      "hash": "sha256:..."
    }
  },
  "bin": "jake.exe",
  "checkver": "github",
  "autoupdate": {
    "architecture": {
      "64bit": {
        "url": "https://github.com/<user>/jake/releases/download/v$version/jake-windows-x86_64.zip"
      },
      "arm64": {
        "url": "https://github.com/<user>/jake/releases/download/v$version/jake-windows-aarch64.zip"
      }
    }
  }
}
```

**User installation:**
```powershell
scoop bucket add jake https://github.com/<user>/scoop-jake
scoop install jake
```

**Checklist:**
- [ ] Create bucket repo from `ScoopInstaller/BucketTemplate`
- [ ] Enable GitHub Actions (for auto-updates)
- [ ] Add `bucket/jake.json`
- [ ] Add `scoop-bucket` topic for discoverability
- [ ] Document in README

---

#### Nix Flake

Build from source using `zig.hook` (preferred for nixpkgs).

**Files needed:**
- `flake.nix` - In jake repository root

**Flake structure:**
```nix
{
  description = "Jake - Modern command runner/build system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "jake";
          version = self.shortRev or "dirty";
          src = ./.;

          nativeBuildInputs = [ pkgs.zig.hook ];
          zigBuildFlags = [ "-Doptimize=ReleaseFast" ];
          dontUseZigCheck = true;

          postInstall = ''
            mkdir -p $out/share/bash-completion/completions
            $out/bin/jake --completions bash > $out/share/bash-completion/completions/jake
            mkdir -p $out/share/zsh/site-functions
            $out/bin/jake --completions zsh > $out/share/zsh/site-functions/_jake
            mkdir -p $out/share/fish/vendor_completions.d
            $out/bin/jake --completions fish > $out/share/fish/vendor_completions.d/jake.fish
          '';

          meta = with pkgs.lib; {
            description = "Modern command runner/build system";
            homepage = "https://github.com/<user>/jake";
            license = licenses.mit;
            mainProgram = "jake";
            platforms = platforms.unix;
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ pkgs.zig pkgs.zls ];
        };
      }
    );
}
```

**User installation:** `nix run github:<user>/jake` or `nix profile install github:<user>/jake`

**For nixpkgs submission (later):**
1. Add yourself to `maintainers/maintainer-list.nix`
2. Create `pkgs/by-name/ja/jake/package.nix`
3. PR title: `jake: init at X.Y.Z`

**Checklist:**
- [ ] Add `flake.nix` to repository
- [ ] Test with `nix build` and `nix run`
- [ ] Document in README
- [ ] Later: Submit to nixpkgs when project matures

---

#### Docker Image (Deferred)

- [ ] Create minimal Dockerfile
- [ ] Publish to GitHub Container Registry
- [ ] Auto-build on release

---

### Quality & Testing

- [ ] Benchmarks suite (track performance over time)
- [ ] Property-based/generative tests (structured fuzzing)
- [ ] Integration test suite with real-world Jakefiles
- [ ] Regression test for each bug fix

---

### Documentation

- [x] Cookbook: Common patterns (Docker, CI, monorepo)
- [x] Migration guide: Makefile to Jakefile
- [x] Migration guide: Justfile to Jakefile
- [ ] Video tutorial / screencast
- [ ] Man page (`man jake`) (automatically generated from CLI docs)

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

### Remote Cache Support (unlikely to be useful)

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

Runtime detection: podman > docker > nerdctl. Auto-mount pwd (or a specified path), forward @export vars.

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


> TODO: needs more details and though into how workflows would look like, what directives are needed, and how it differs
> from regular mode, what scopes and inheritance should be etc.

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
- [x] GitHub Linguist upstream (submit PR to github-linguist/linguist)

**Publishing:**

- [ ] Publish VS Code extension to Marketplace
- [ ] Publish IntelliJ plugin to JetBrains Marketplace
- [ ] Publish tree-sitter-jake, shiki-jake, prism-jake, highlightjs-jake to npm

**Testing:**

- [ ] Zed isolated testing with `zed --user-data-dir /tmp/zed-test` for extension development

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

---

### Optional Telemetry

Opt-in anonymous usage telemetry via Sentry for crash reporting and usage analytics.

- Disabled by default, enable with `JAKE_TELEMETRY=1`
- Respect `DO_NOT_TRACK` env var
- Track: crash reports, feature usage counts, OS/arch distribution
- No PII, no Jakefile contents, no command arguments
