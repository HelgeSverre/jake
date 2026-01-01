# highlightjs-jake

[highlight.js](https://highlightjs.org/) syntax highlighting for [Jake](https://github.com/HelgeSverre/jake) task runner files.

## Installation

```bash
npm install highlightjs-jake
```

## Usage

### Node.js / ES Modules

```javascript
import hljs from 'highlight.js/lib/core';
import jake from 'highlightjs-jake';

// Register the language (standard highlight.js pattern)
hljs.registerLanguage('jake', jake);
hljs.registerLanguage('jakefile', jake);

// Highlight code
const code = `task build:
    echo "Building..."`;

const result = hljs.highlight(code, { language: 'jake' });
console.log(result.value);
```

### CommonJS

```javascript
const hljs = require('highlight.js/lib/core');
const jake = require('highlightjs-jake');

hljs.registerLanguage('jake', jake);
hljs.registerLanguage('jakefile', jake);

const html = hljs.highlight(jakeCode, { language: 'jake' }).value;
```

### Browser

```html
<!DOCTYPE html>
<html>
<head>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/default.min.css" />
</head>
<body>
  <pre><code class="language-jake">
task build:
    echo "Building..."
  </code></pre>

  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
  <script src="highlightjs-jake.js"></script>
  <script>
    hljs.registerLanguage('jake', hljsDefineJake);
    hljs.highlightAll();
  </script>
</body>
</html>
```

### CommonJS

```javascript
const hljs = require('highlight.js/lib/core');
const jake = require('highlightjs-jake');

hljs.registerLanguage('jake', jake);

const html = hljs.highlight(jakeCode, { language: 'jake' }).value;
```

### With Automatic Language Detection

```javascript
import hljs from 'highlight.js/lib/core';
import jake from 'highlightjs-jake';

hljs.registerLanguage('jake', jake);

// Will auto-detect Jake syntax
const result = hljs.highlightAuto(code);
```

## Supported Syntax

The grammar supports all Jake language features:

- **Recipe definitions**: `task`, `file`, and simple recipes
- **Directives**: `@if`, `@each`, `@needs`, `@import`, `@dotenv`, etc.
- **Variables**: Assignment (`var = value`) and interpolation (`{{variable}}`)
- **Shell variables**: `$VAR`, `${VAR}`, `$1`, `$@`
- **Dependencies**: `[dep1, dep2]`
- **Comments**: `# comment`
- **Strings**: Single, double, and triple-quoted
- **Command prefixes**: `@`, `-`
- **Built-in functions**: `dirname()`, `uppercase()`, etc.
- **Platform keywords**: `linux`, `macos`, `windows`, etc.
- **Backtick commands**: `` `command` ``

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