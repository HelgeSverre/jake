# Jake Language Support for VS Code

Syntax highlighting for [Jake](https://github.com/helgeblod/jake) task runner files.

## Features

- Syntax highlighting for `Jakefile` and `*.jake` files
- Comment toggling with `#`
- Bracket matching and auto-closing
- Code folding for recipes

## Syntax Highlighting

The extension provides highlighting for:

- **Keywords**: `task`, `file`, `import`, `as`
- **Directives**: `@if`, `@else`, `@each`, `@end`, `@needs`, `@require`, `@cache`, `@watch`, `@confirm`, `@group`, `@desc`, `@alias`, `@quiet`, `@ignore`, `@only-os`, `@platform`, `@cd`, `@shell`, `@export`, `@pre`, `@post`, `@before`, `@after`, `@on_error`
- **Variables**: `{{variable}}`, `{{function(arg)}}`, `$VAR`, `${VAR}`, `$1`, `$@`
- **Functions**: `dirname()`, `basename()`, `extension()`, `uppercase()`, `lowercase()`, `trim()`, `home()`, `env()`, `exists()`, `eq()`, `neq()`
- **Strings**: Double and single quoted strings with escape sequences
- **Comments**: `# comment`
- **Recipe definitions**: `task name:`, `file output: deps`, `name:`
- **Dependencies**: `[dep1, dep2]`
- **Parameters**: `task name param="default":`

## Installation

### From VSIX (Local)

1. Download or build the `.vsix` file
2. In VS Code, open the Command Palette (`Cmd+Shift+P` / `Ctrl+Shift+P`)
3. Run "Extensions: Install from VSIX..."
4. Select the `.vsix` file

### Development

1. Clone this repository
2. Open the `editors/vscode-jake` folder in VS Code
3. Press `F5` to launch the Extension Development Host
4. Open a `Jakefile` to test the highlighting

## Building

```bash
# Install vsce if not already installed
npm install -g @vscode/vsce

# Package the extension
cd editors/vscode-jake
vsce package
```

This creates a `.vsix` file that can be installed locally or published.

## Example Jakefile

```jake
# Variables
version = "1.0.0"
app_name = "myapp"

@import "lib/helpers.jake" as helpers
@dotenv
@require API_KEY

# Global hooks
@pre echo "Starting..."
@post echo "Finished!"

@default
@group build
@desc "Build the project"
task build:
    @needs node npm
    echo "Building {{app_name}} v{{version}}"
    npm run build

task test: [build]
    @if env(CI)
        npm run test:ci
    @else
        npm run test
    @end

file dist/bundle.js: src/**/*.ts
    esbuild src/index.ts -o dist/bundle.js

task deploy:
    @confirm "Deploy to production?"
    @only-os linux macos
    ./scripts/deploy.sh
```

## License

MIT
