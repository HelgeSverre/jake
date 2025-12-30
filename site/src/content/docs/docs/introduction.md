---
title: Introduction
description: Learn what Jake is and why you should use it.
---

Jake is a modern command runner that combines the best features of GNU Make and Just:

- **From Make**: File-based dependency tracking, parallel execution, incremental builds
- **From Just**: Clean syntax, parameters, conditionals, imports, .env loading
- **New in Jake**: Glob patterns, pre/post hooks, better error messages, watch mode

## Why Jake?

**Make** is powerful but cryptic. **Just** is friendly but limited. **Jake** gives you both:

| Feature | Make | Just | Jake |
|---------|:----:|:----:|:----:|
| File-based dependencies | Yes | No | Yes |
| Clean syntax | No | Yes | Yes |
| Parallel execution | Yes | No | Yes |
| Glob patterns | No | No | Yes |
| Import system | No | Yes | Yes |
| Conditionals | No | Yes | Yes |
| Pre/post hooks | No | No | Yes |
| .env loading | No | Yes | Yes |
| Watch mode | No | No | Yes |

## Key Features

### File Dependencies
Like Make, Jake tracks file modifications and only rebuilds what's changed:

```jake
file dist/app.js: src/**/*.ts
    esbuild src/index.ts --bundle --outfile=dist/app.js
```

### Clean Syntax
Like Just, Jake uses readable syntax without cryptic symbols:

```jake
task deploy env="staging":
    @confirm "Deploy to {{env}}?"
    ./deploy.sh {{env}}
```

### Parallel Execution
Run independent tasks simultaneously:

```bash
jake -j4 all    # Use 4 parallel jobs
```

### Built-in Watch Mode
Re-run tasks automatically when files change:

```bash
jake -w build
```

## Next Steps

- [Install Jake](/docs/installation/)
- [Quick Start Guide](/docs/quick-start/)
