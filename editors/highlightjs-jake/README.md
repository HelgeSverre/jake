# highlightjs-jake

[highlight.js](https://highlightjs.org/) syntax highlighting for [Jake](https://github.com/HelgeSverre/jake) task runner files.

## Installation

```bash
npm install highlightjs-jake
```

## Usage

### Node.js / Bundlers

```javascript
import hljs from 'highlight.js/lib/core';
import jake from 'highlightjs-jake';

hljs.registerLanguage('jake', jake);

const code = `task build:
    echo "Building..."`;

const result = hljs.highlight(code, { language: 'jake' });
console.log(result.value);
```

### Browser

```html
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/default.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script src="jake.js"></script>
<script>
  hljs.registerLanguage('jake', hljsDefineJake);
  hljs.highlightAll();
</script>

<pre><code class="language-jake">
task build:
    echo "Building..."
</code></pre>
```

## Supported Syntax

- Recipe definitions (`task`, `file`, simple)
- Directives (`@if`, `@each`, `@needs`, `@import`, etc.)
- Variable assignments and interpolation (`{{variable}}`)
- Shell variables (`$VAR`, `${VAR}`)
- Dependencies (`[dep1, dep2]`)
- Comments (`# comment`)
- Strings (single, double, triple-quoted)
- Command prefixes (`@`, `-`)
- Backtick commands

## License

MIT
