# Jake Editor Plugins

This directory contains syntax highlighting and language support plugins for various editors and platforms.

## Plugin Overview

| Plugin                                | Type                  | Status                     | Distribution          |
| ------------------------------------- | --------------------- | -------------------------- | --------------------- |
| [tree-sitter-jake](tree-sitter-jake/) | Tree-sitter grammar   | ✅ Canonical               | npm, crates.io        |
| [vscode-jake](vscode-jake/)           | VS Code extension     | ✅ Canonical (TextMate)    | VS Code Marketplace   |
| [sublime-jake](sublime-jake/)         | Sublime Text package  | ⬅️ Synced from VS Code     | Package Control       |
| [shiki-jake](shiki-jake/)             | Shiki grammar         | ⬅️ Synced from VS Code     | npm                   |
| [intellij-jake](intellij-jake/)       | IntelliJ plugin       | ⬅️ Copies VS Code at build | JetBrains Marketplace |
| [zed-jake](zed-jake/)                 | Zed extension         | ⬅️ Synced from tree-sitter | Zed Extensions        |
| [vim-jake](vim-jake/)                 | Vim/Neovim syntax     | ✅ Standalone              | vim-plug, etc.        |
| [highlightjs-jake](highlightjs-jake/) | highlight.js language | ✅ Standalone              | npm                   |
| [prism-jake](prism-jake/)             | Prism.js language     | ✅ Standalone              | npm                   |

## Canonical Sources

There are two canonical sources for syntax definitions:

### 1. TextMate Grammar (VS Code)

**Source:** `vscode-jake/syntaxes/jake.tmLanguage.json`

Used by editors that support TextMate grammars:

- **VS Code** - Uses directly
- **Sublime Text** - Synced copy
- **Shiki** - Synced copy (for documentation sites)
- **IntelliJ** - Copied at build time via Gradle

### 2. Tree-sitter Grammar

**Source:** `tree-sitter-jake/queries-src/*.scm`

The tree-sitter grammar generates flavored queries for different editors:

- **queries/jake/** - NeoVim/standard format
- **queries-flavored/zed/** - Zed-specific format
- **queries-flavored/helix/** - Helix-specific format
- **queries-flavored/lapce/** - Lapce-specific format

## Synchronization

### Automated Sync Script

Run the sync script after making changes to canonical sources:

```bash
# Sync all plugins
./editors/sync.sh

# Check if files are in sync (for CI)
./editors/sync.sh --check
```

### What Gets Synced

```
vscode-jake/syntaxes/jake.tmLanguage.json
    ├── → sublime-jake/Jake.tmLanguage.json
    └── → shiki-jake/jake.tmLanguage.json

tree-sitter-jake/queries-src/*.scm
    ├── → tree-sitter-jake/queries/jake/*.scm (NeoVim)
    └── → tree-sitter-jake/queries-flavored/zed/*.scm
              └── → zed-jake/languages/jake/*.scm
```

### Using Just/Jake

```bash
# From repository root
just editors-sync        # Sync all plugins
just editors-sync-check  # Check sync status (CI)
```

## Plugin Details

### tree-sitter-jake

The tree-sitter parser is the most complete and accurate grammar. It:

- Parses Jake syntax into an AST
- Provides 93+ test cases
- Generates editor-specific queries via `build-flavored-queries.py`

```bash
cd editors/tree-sitter-jake
npm install
npm test                    # Run grammar tests
python3 build-flavored-queries.py  # Generate flavored queries
```

### vscode-jake

The VS Code extension provides TextMate-based syntax highlighting.

```bash
cd editors/vscode-jake
# Package for distribution
npx vsce package
# Install locally
code --install-extension jake-lang-0.1.0.vsix
```

### sublime-jake

Synced from VS Code. Install via Package Control or manually copy to Sublime's Packages folder.

### shiki-jake

TextMate grammar for Shiki (used in documentation sites, Astro, etc.).

```bash
cd editors/shiki-jake
npm install
npm run build
```

### intellij-jake

IntelliJ plugin that uses the TextMate bundle from VS Code.

```bash
cd editors/intellij-jake
./gradlew buildPlugin      # Build plugin
./gradlew runIde           # Test in sandbox IDE
./gradlew publishPlugin    # Publish to JetBrains Marketplace
```

### zed-jake

Zed extension using tree-sitter queries.

The extension.toml points to the tree-sitter-jake grammar in this repo:

```toml
[grammars.jake]
repository = "https://github.com/HelgeSverre/jake"
path = "editors/tree-sitter-jake"
```

### vim-jake

Standalone Vim syntax file. Install via your plugin manager:

```vim
" vim-plug
Plug 'HelgeSverre/jake', { 'rtp': 'editors/vim-jake' }

" lazy.nvim
{ 'HelgeSverre/jake', config = function()
    vim.opt.runtimepath:append('editors/vim-jake')
end }
```

### highlightjs-jake

highlight.js language definition for web syntax highlighting.

```bash
cd editors/highlightjs-jake
npm install
npm run build
npm test
```

### prism-jake

Prism.js language definition for web syntax highlighting.

```bash
cd editors/prism-jake
npm install
npm test
```

## Built-in Functions Reference

All plugins should recognize these 27 built-in functions:

| Category      | Functions                                                                                                  |
| ------------- | ---------------------------------------------------------------------------------------------------------- |
| **Path**      | `dirname`, `basename`, `extension`, `without_extension`, `without_extensions`, `absolute_path`, `abs_path` |
| **String**    | `uppercase`, `lowercase`, `trim`                                                                           |
| **System**    | `home`, `local_bin`, `shell_config`, `launch`                                                              |
| **Condition** | `env`, `exists`, `eq`, `neq`, `command`                                                                    |
| **Runtime**   | `is_watching`, `is_dry_run`, `is_verbose`                                                                  |
| **Platform**  | `is_platform`, `is_macos`, `is_linux`, `is_windows`, `is_unix`                                             |
| **Loop**      | `item`                                                                                                     |

## Advanced Features

### Runnables (Click-to-Run in Zed)

The `runnables.scm` query enables click-to-run functionality in Zed. When viewing a Jakefile in Zed, you'll see a "Run" button next to each recipe that executes `jake <recipe-name>`.

**File:** `tree-sitter-jake/queries-src/runnables.scm`

```scheme
; Jake recipes are runnable
(recipe
  (recipe_header
    name: (identifier) @run @_recipe_name
  )
) @_jake-recipe
(#set! tag jake-recipe)
```

### Document Outline

The `outline.scm` query provides symbol navigation:

- Document outline panel (Cmd+Shift+O in most editors)
- Breadcrumb navigation
- Go to symbol functionality

**File:** `tree-sitter-jake/queries-src/outline.scm`

### VS Code Task Provider (Future)

VS Code doesn't use tree-sitter runnables. To add click-to-run in VS Code, you would need to:

1. Create a Task Provider that discovers recipes from Jakefiles
2. Register tasks via `vscode.tasks.registerTaskProvider`
3. Optionally add CodeLens decorations above recipes

Example approach (not yet implemented):

```typescript
// In vscode-jake extension
import * as vscode from "vscode";

class JakeTaskProvider implements vscode.TaskProvider {
  async provideTasks(): Promise<vscode.Task[]> {
    // Parse Jakefile, extract recipe names
    // Return Task[] with shell execution: `jake <recipe>`
  }
}

// Register in extension activation
vscode.tasks.registerTaskProvider("jake", new JakeTaskProvider());
```

## Directives Reference

### Global Directives (top-level)

- `@import`, `@dotenv`, `@require`, `@export`, `@default`
- `@pre`, `@post`, `@on_error`, `@before`, `@after`

### Recipe Attributes (before recipe)

- `@group`, `@desc`, `@alias`, `@quiet`
- `@platform`
- `@needs` (with hint/fallback variants)

### Body Directives (inside recipes)

- `@if`, `@elif`, `@else`, `@end`
- `@each`
- `@cd`, `@cache`, `@watch`, `@confirm`, `@ignore`, `@shell`
- `@timeout`, `@launch`
- `@needs`, `@require`, `@export`
- `@pre`, `@post`

## Adding a New Feature

When adding new syntax features (directives, functions, etc.):

1. **Update tree-sitter-jake first** - This is the source of truth
   - Edit `grammar.js`
   - Add tests in `test/corpus/`
   - Update `queries-src/highlights.scm`

2. **Update TextMate grammar**
   - Edit `vscode-jake/syntaxes/jake.tmLanguage.json`

3. **Update standalone plugins**
   - `vim-jake/syntax/jake.vim`
   - `highlightjs-jake/src/languages/jake.js`
   - `prism-jake/index.js`

4. **Run sync script**

   ```bash
   ./editors/sync.sh
   ```

5. **Update this documentation** if adding new built-ins or directives

## CI Integration

Add to your CI workflow:

```yaml
- name: Check editor plugin sync
  run: ./editors/sync.sh --check
```

## Publishing Checklist

Before releasing new plugin versions:

- [ ] All syntax features match across plugins
- [ ] `./editors/sync.sh --check` passes
- [ ] tree-sitter tests pass: `cd tree-sitter-jake && npm test`
- [ ] Update version numbers in all package.json/package files
- [ ] Update CHANGELOG in each plugin directory

## Related Documentation

- [PLUGIN_REVIEW.md](PLUGIN_REVIEW.md) - Detailed review of all plugins
- [tree-sitter-jake/GRAMMAR.md](tree-sitter-jake/GRAMMAR.md) - Grammar specification
- [tree-sitter-jake/README.md](tree-sitter-jake/README.md) - Tree-sitter usage
