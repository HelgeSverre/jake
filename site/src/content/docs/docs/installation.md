---
title: Installation
description: How to install Jake on your system.
---

## Quick Install (Recommended)

```bash
curl -fsSL jakefile.dev/install.sh | sh
```

This downloads the latest release binary for your platform (Linux, macOS).

### Environment Variables

- `JAKE_VERSION` - Install a specific version (default: latest)
- `JAKE_INSTALL` - Installation directory (default: ~/.local/bin)

## From Source

Requires [Zig](https://ziglang.org/) 0.15.2 or later:

```bash
git clone https://github.com/HelgeSverre/jake.git
cd jake
zig build -Doptimize=ReleaseFast
```

The binary is at `zig-out/bin/jake`. Copy it to your PATH:

```bash
cp zig-out/bin/jake ~/.local/bin/
# or
sudo cp zig-out/bin/jake /usr/local/bin/
```

## Pre-built Binaries

Download from [GitHub Releases](https://github.com/HelgeSverre/jake/releases) for:

- Linux (x86_64, aarch64)
- macOS (x86_64, aarch64/Apple Silicon)
- Windows (x86_64)

## Verify Installation

```bash
jake --version
```

## Shell Completions

Jake supports shell completions for bash, zsh, and fish:

```bash
# Print completion script to stdout
jake --completions bash
jake --completions zsh
jake --completions fish

# Auto-install to your shell config
jake --install
```

## Uninstall

```bash
jake --uninstall  # Remove completions and config
rm ~/.local/bin/jake
```

## Next Steps

- [Quick Start Guide](/docs/quick-start/)
