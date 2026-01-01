# prism-jake

[Prism.js](https://prismjs.com/) syntax highlighting for [Jake](https://github.com/HelgeSverre/jake) task runner files.

## Installation

```bash
npm install prism-jake
```

## Usage

### Browser

```html
<link
  rel="stylesheet"
  href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism.min.css"
/>
<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js"></script>
<script src="prism-jake.js"></script>

<pre><code class="language-jake">
task build:
    echo "Building..."
</code></pre>
```

### Node.js / Bundlers

```javascript
import Prism from "prismjs";
import "prism-jake";

const code = `task build:
    echo "Building..."`;

const html = Prism.highlight(code, Prism.languages.jake, "jake");
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

## License

MIT
