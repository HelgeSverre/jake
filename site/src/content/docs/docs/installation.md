---
title: Installation
description: How to install Jake on your system.
---

## From Source (Recommended)

Requires [Zig](https://ziglang.org/) 0.14 or later:

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

## Shell Completion

Jake doesn't currently provide shell completions, but recipe names work well with basic tab completion in most shells.

## Next Steps

- [Quick Start Guide](/docs/quick-start/)
