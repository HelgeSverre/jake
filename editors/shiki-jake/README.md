# shiki-jake

[Shiki](https://shiki.style/) syntax highlighting for [Jake](https://github.com/HelgeSverre/jake) task runner files.

Shiki is a beautiful syntax highlighter powered by the same language grammars as VS Code. It provides accurate, high-quality syntax highlighting with zero dependencies at runtime.

## Installation

```bash
npm install shiki shiki-jake
```

## Usage

### Basic

```javascript
import { createHighlighter } from "shiki";
import jake from "shiki-jake";

const highlighter = await createHighlighter({
  themes: ["github-dark"],
  langs: [jake],
});

const code = `task build:
    echo "Building..."`;

const html = highlighter.codeToHtml(code, {
  lang: "jake",
  theme: "github-dark",
});

console.log(html);
```

### Load Language Dynamically

```javascript
import { createHighlighter } from "shiki";
import jake from "shiki-jake";

const highlighter = await createHighlighter({
  themes: ["github-dark"],
  langs: [], // Start with no languages
});

// Load Jake when needed
await highlighter.loadLanguage(jake);

const html = highlighter.codeToHtml(code, {
  lang: "jake",
  theme: "github-dark",
});
```

### Multiple Themes

```javascript
import { createHighlighter } from "shiki";
import jake from "shiki-jake";

const highlighter = await createHighlighter({
  themes: ["github-dark", "github-light"],
  langs: [jake],
});

// Dark theme
const darkHtml = highlighter.codeToHtml(code, {
  lang: "jake",
  theme: "github-dark",
});

// Light theme
const lightHtml = highlighter.codeToHtml(code, {
  lang: "jake",
  theme: "github-light",
});
```

### With Markdown Processors

#### Astro

```javascript
// astro.config.mjs
import { defineConfig } from "astro/config";
import jake from "shiki-jake";

export default defineConfig({
  markdown: {
    shikiConfig: {
      themes: {
        light: "github-light",
        dark: "github-dark",
      },
      langs: [jake],
    },
  },
});
```

#### VitePress

```javascript
// .vitepress/config.js
import { defineConfig } from "vitepress";
import jake from "shiki-jake";

export default defineConfig({
  markdown: {
    languages: [jake],
  },
});
```

#### Next.js with MDX

```javascript
import { createHighlighter } from "shiki";
import jake from "shiki-jake";

const highlighter = await createHighlighter({
  themes: ["github-dark"],
  langs: [jake],
});

// Use in your MDX processor
```

Then in your Markdown/MDX:

````markdown
```jake
task build:
    echo "Building..."
```
````

## Supported Syntax

This package uses a TextMate grammar compatible with VS Code, providing full syntax highlighting for:

- **Recipe definitions**: `task`, `file`, and simple recipes
- **Directives**: `@if`, `@each`, `@needs`, `@import`, `@dotenv`, etc.
- **Variables**: Assignment (`var = value`) and interpolation (`{{variable}}`)
- **Shell variables**: `$VAR`, `${VAR}`, `$1`, `$@`
- **Dependencies**: `[dep1, dep2]`
- **Comments**: `# comment`
- **Strings**: Single, double, and triple-quoted
- **Command prefixes**: `@`, `-`
- **Built-in functions**: `dirname()`, `uppercase()`, `trim()`, etc.
- **Conditionals**: `@if`, `@elif`, `@else`, `@end`
- **Platform keywords**: `linux`, `macos`, `windows`, etc.

## Example

```jake
# Build configuration
CC := gcc
CFLAGS := -Wall -O2

@import "common.jake"
@dotenv

task build target="release": [clean]
    @if eq(target, "debug")
        echo "Debug build"
        {{CC}} {{CFLAGS}} -g src/*.c -o bin/app
    @else
        echo "Release build"
        {{CC}} {{CFLAGS}} src/*.c -o bin/app
    @end

task clean:
    rm -rf bin/

file bin/app: [src/main.c, src/utils.c]
    {{CC}} {{CFLAGS}} $^ -o $@
```

## TextMate Grammar

This package exports a TextMate grammar that can be used with any compatible syntax highlighter:

```javascript
import jake from "shiki-jake";

console.log(jake.scopeName); // "source.jake"
console.log(jake.name); // "jake"
console.log(jake.aliases); // ["jakefile"]
```

## License

MIT
