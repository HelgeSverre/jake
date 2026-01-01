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

### With Markdown (e.g., in Astro, VitePress)

Most Shiki integrations support custom languages. For example, in Astro:

```javascript
// astro.config.mjs
import { defineConfig } from "astro/config";
import jake from "shiki-jake";

export default defineConfig({
  markdown: {
    shikiConfig: {
      langs: [jake],
    },
  },
});
```

Then in your Markdown:

````markdown
```jake
task build:
    echo "Building..."
```
````

## Supported Syntax

This package uses the same TextMate grammar as the VS Code extension, providing full syntax highlighting for:

- Recipe definitions (`task`, `file`, simple)
- Directives (`@if`, `@each`, `@needs`, `@import`, etc.)
- Variable assignments and interpolation (`{{variable}}`)
- Shell variables (`$VAR`, `${VAR}`)
- Dependencies (`[dep1, dep2]`)
- Comments (`# comment`)
- Strings (single, double, triple-quoted)
- Command prefixes (`@`, `-`)
- Built-in functions

## License

MIT
