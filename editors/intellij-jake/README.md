# Jakefile Syntax for IntelliJ IDEA

Syntax highlighting for Jakefile and .jake modules/files.

Part of the [Jake](https://github.com/HelgeSverre/jake) task runner project.

- **Website**: [jakefile.dev](https://jakefile.dev)
- **Repository**: [github.com/HelgeSverre/jake](https://github.com/HelgeSverre/jake)
- **License**: MIT
- **Author**: [Helge Sverre](https://helgesver.re)

## Features

- Syntax highlighting for `Jakefile` and `*.jake` files
- Works in all JetBrains IDEs (IntelliJ IDEA, WebStorm, PyCharm, etc.)
- Uses TextMate grammar for consistent highlighting

## Highlighted Elements

- **Keywords**: `task`, `file`, `import`, `as`
- **Directives**: `@if`, `@else`, `@each`, `@end`, `@needs`, `@require`, `@cache`, `@watch`, `@confirm`, `@group`, `@desc`, `@alias`, `@quiet`, `@ignore`, `@only-os`, `@platform`, `@cd`, `@shell`, `@export`, `@pre`, `@post`, `@before`, `@after`, `@on_error`
- **Variables**: `{{variable}}`, `{{function(arg)}}`, `$VAR`, `${VAR}`, `$1`, `$@`
- **Functions**: `dirname()`, `basename()`, `extension()`, `uppercase()`, `lowercase()`, `trim()`, `home()`, `env()`, `exists()`, `eq()`, `neq()`
- **Strings**: Double and single quoted strings with escape sequences
- **Comments**: `# comment`
- **Recipe definitions**: `task name:`, `file output: deps`, `name:`
- **Dependencies**: `[dep1, dep2]`

## Installation

### From JetBrains Marketplace

1. Open your JetBrains IDE
2. Go to Settings → Plugins → Marketplace
3. Search for "Jakefile"
4. Click Install

### From Disk

1. Download the `.zip` file from [Releases](https://github.com/HelgeSverre/jake/releases)
2. Go to Settings → Plugins → ⚙️ → Install Plugin from Disk
3. Select the downloaded `.zip` file

### Building from Source

```bash
cd editors/intellij-jake
./gradlew buildPlugin
```

The plugin will be in `build/distributions/`.

## Development

### Prerequisites

- JDK 17+
- Gradle (wrapper included)

### Building

```bash
./gradlew buildPlugin
```

### Running in Development IDE

```bash
./gradlew runIde
```

### Publishing

```bash
# Requires PUBLISH_TOKEN environment variable
./gradlew publishPlugin
```

## Example Jakefile

```jake
# Variables
version = "1.0.0"
app_name = "myapp"

@import "jake/helpers.jake" as helpers
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
