# Jakefile Syntax for Vim/Neovim

Syntax highlighting for Jakefile and .jake modules/files.

Part of the [Jake](https://github.com/HelgeSverre/jake) task runner project.

- **Website**: [jakefile.dev](https://jakefile.dev)
- **Repository**: [github.com/HelgeSverre/jake](https://github.com/HelgeSverre/jake)
- **License**: MIT
- **Author**: [Helge Sverre](https://helgesver.re)

## Features

- Syntax highlighting for `Jakefile` and `*.jake` files
- Comment toggling with `#`
- Proper indentation (4 spaces)
- Folding support

## Syntax Highlighting

The plugin highlights:

- **Keywords**: `task`, `file`, `default`
- **Directives**: `@if`, `@else`, `@each`, `@end`, `@needs`, `@require`, `@cache`, `@watch`, `@confirm`, `@group`, `@desc`, `@alias`, `@quiet`, `@ignore`, `@only-os`, `@platform`, `@cd`, `@shell`, `@export`, `@pre`, `@post`, `@before`, `@after`, `@on_error`, `@import`, `@dotenv`
- **Variables**: `{{variable}}`, `{{function(arg)}}`, `$VAR`, `${VAR}`, `$1`, `$@`
- **Functions**: `dirname()`, `basename()`, `extension()`, `uppercase()`, `lowercase()`, `trim()`, `home()`, `env()`, `exists()`, `eq()`, `neq()`
- **Strings**: Double and single quoted strings with escape sequences
- **Comments**: `# comment`
- **Recipe definitions**: `task name:`, `file output: deps`, `name:`
- **Dependencies**: `[dep1, dep2]`
- **Platform names**: `linux`, `macos`, `windows`, etc.

## Installation

### Using jake (recommended)

```bash
jake editors.vim-install      # Install to ~/.vim
jake editors.neovim-install   # Install to ~/.config/nvim
```

### Manual Installation

#### Vim

```bash
mkdir -p ~/.vim/syntax ~/.vim/ftdetect ~/.vim/ftplugin
cp syntax/jake.vim ~/.vim/syntax/
cp ftdetect/jake.vim ~/.vim/ftdetect/
cp ftplugin/jake.vim ~/.vim/ftplugin/
```

#### Neovim

```bash
mkdir -p ~/.config/nvim/syntax ~/.config/nvim/ftdetect ~/.config/nvim/ftplugin
cp syntax/jake.vim ~/.config/nvim/syntax/
cp ftdetect/jake.vim ~/.config/nvim/ftdetect/
cp ftplugin/jake.vim ~/.config/nvim/ftplugin/
```

### Using a Plugin Manager

#### vim-plug

```vim
Plug 'HelgeSverre/jake', { 'rtp': 'editors/vim-jake' }
```

#### lazy.nvim (Neovim)

```lua
{
  'HelgeSverre/jake',
  config = function()
    vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/jake/editors/vim-jake')
  end
}
```

#### Vundle

```vim
Plugin 'HelgeSverre/jake', { 'rtp': 'editors/vim-jake' }
```

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
