# prism-jake

[Prism.js](https://prismjs.com/) syntax highlighting for [Jake](https://github.com/HelgeSverre/jake) task runner files.

## Installation

```bash
npm install prism-jake
```

## Usage

### Node.js / ES Modules

```javascript
import Prism from "prismjs";
import jake from "prism-jake";

// Register the language
Prism.languages.jake = jake;
Prism.languages.jakefile = jake;

// Highlight code
const code = `task build:
    echo "Building..."`;

const html = Prism.highlight(code, jake, "jake");
console.log(html);
```

### Browser

```html
<!DOCTYPE html>
<html>
  <head>
    <link
      rel="stylesheet"
      href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism.min.css"
    />
  </head>
  <body>
    <pre><code class="language-jake">
task build:
    echo "Building..."
  </code></pre>

    <script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js"></script>
    <script src="prism-jake.js"></script>
    <!-- Language auto-registers when Prism is global -->
  </body>
</html>
```

### With Bundlers (Webpack, Vite, etc.)

```javascript
import Prism from "prismjs";
import jake from "prism-jake";

Prism.languages.jake = jake;

// Use in your framework
const highlighted = Prism.highlight(jakeCode, jake, "jake");
```

## Supported Syntax

The grammar supports all Jake language features:

- **Recipe definitions**: `task`, `file`, and simple recipes
- **Directives**: `@if`, `@each`, `@needs`, `@import`, `@dotenv`, etc.
- **Variables**: Assignment (`var = value`) and interpolation (`{{variable}}`)
- **Shell variables**: `$VAR`, `${VAR}`
- **Dependencies**: `[dep1, dep2]`
- **Comments**: `# comment`
- **Strings**: Single, double, and triple-quoted
- **Command prefixes**: `@`, `-`
- **Built-in functions**: `dirname()`, `uppercase()`, etc.
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
```

## License

MIT
