# Editor extension build tasks

# ============================================================================
# VS Code Extension
# ============================================================================

@group editors
@desc "Package VS Code extension as .vsix"
task vscode-package:
    @needs npm
    @cd editors/vscode-jake
        npm install --silent
        npx @vscode/vsce package --no-dependencies
    echo "Package created: editors/vscode-jake/*.vsix"

@group editors
@desc "Install VS Code extension locally"
task vscode-install: [vscode-package]
    @needs code "VS Code CLI (install from VS Code command palette)"
    code --install-extension editors/vscode-jake/*.vsix
    echo "Extension installed! Reload VS Code to activate."

@group editors
@desc "Publish VS Code extension to marketplace"
task vscode-publish:
    @needs npm
    @confirm Publish to VS Code Marketplace? (requires VSCE_PAT env var)
    @require VSCE_PAT
    @cd editors/vscode-jake
        npx @vscode/vsce publish
    echo "Extension published!"

@group editors
@desc "Validate VS Code extension package.json"
task vscode-validate:
    @needs node
    @cd editors/vscode-jake
        node -e "const p = require('./package.json'); console.log('Name:', p.name); console.log('Version:', p.version); console.log('Languages:', p.contributes.languages.length); console.log('Grammars:', p.contributes.grammars.length);"

@group editors
@desc "Clean VS Code extension build artifacts"
task vscode-clean:
    @ignore
    rm -rf editors/vscode-jake/node_modules editors/vscode-jake/*.vsix
    echo "VS Code extension cleaned"

@group editors
@desc "Launch VS Code with extension loaded from source (fast dev mode)"
task vscode-run:
    @needs code "VS Code CLI (install from VS Code command palette)"
    code --extensionDevelopmentPath=editors/vscode-jake
    echo "Launched VS Code Extension Development Host"
    echo "Open a Jakefile to test syntax highlighting"

@group editors
@desc "Package, install, and validate extension"
task vscode-dev: [vscode-package, vscode-install, vscode-validate]
    echo ""
    echo "VS Code extension installed and validated!"
    echo ""
    echo "Tips:"
    echo "  - Run 'jake editors.vscode-run' for fast testing from source"
    echo "  - Run 'jake editors.vscode-dev -w' to auto-rebuild on changes"

# ============================================================================
# Tree-sitter Grammar (for Zed, Neovim, Helix)
# ============================================================================

@group editors
@desc "Generate tree-sitter parser (requires grammar.js)"
task tree-sitter-generate:
    @needs npx
    @if exists(editors/tree-sitter-jake/grammar.js)
        @cd editors/tree-sitter-jake
            npx tree-sitter generate
        echo "Parser generated: editors/tree-sitter-jake/src/parser.c"
    @else
        echo "Tree-sitter grammar not yet created."
        echo "Create editors/tree-sitter-jake/grammar.js first."
    @end

@group editors
@desc "Test tree-sitter grammar"
task tree-sitter-test:
    @needs npx
    @if exists(editors/tree-sitter-jake/grammar.js)
        @cd editors/tree-sitter-jake
            npx tree-sitter test
    @else
        echo "Tree-sitter grammar not yet created."
    @end

@group editors
@desc "Parse a file with tree-sitter (for debugging)"
task tree-sitter-parse:
    @needs npx
    @if exists(editors/tree-sitter-jake/grammar.js)
        @cd editors/tree-sitter-jake
            npx tree-sitter parse ../../Jakefile
    @else
        echo "Tree-sitter grammar not yet created."
    @end

# ============================================================================
# Vim/Neovim
# ============================================================================

@group editors
@desc "Install Vim syntax files to ~/.vim"
task vim-install:
    @if exists(editors/vim-jake/syntax/jake.vim)
        mkdir -p ~/.vim/syntax ~/.vim/ftdetect ~/.vim/ftplugin
        cp editors/vim-jake/syntax/jake.vim ~/.vim/syntax/
        cp editors/vim-jake/ftdetect/jake.vim ~/.vim/ftdetect/
        cp editors/vim-jake/ftplugin/jake.vim ~/.vim/ftplugin/
        echo "Vim syntax files installed to ~/.vim"
    @else
        echo "Vim plugin not yet created at editors/vim-jake/"
    @end

@group editors
@desc "Install Neovim syntax files to ~/.config/nvim"
task neovim-install:
    @if exists(editors/vim-jake/syntax/jake.vim)
        mkdir -p ~/.config/nvim/syntax ~/.config/nvim/ftdetect ~/.config/nvim/ftplugin
        cp editors/vim-jake/syntax/jake.vim ~/.config/nvim/syntax/
        cp editors/vim-jake/ftdetect/jake.vim ~/.config/nvim/ftdetect/
        cp editors/vim-jake/ftplugin/jake.vim ~/.config/nvim/ftplugin/
        echo "Neovim syntax files installed to ~/.config/nvim"
    @else
        echo "Vim plugin not yet created at editors/vim-jake/"
    @end

@group editors
@desc "Launch Neovim with plugin loaded from source (fast dev mode)"
task neovim-run:
    @needs nvim
    nvim --cmd "set rtp+=editors/vim-jake" Jakefile

@group editors
@desc "Launch Vim with plugin loaded from source (fast dev mode)"
task vim-run:
    @needs vim
    vim --cmd "set rtp+=editors/vim-jake" Jakefile

# ============================================================================
# IntelliJ IDEA / JetBrains
# ============================================================================

@group editors
@desc "Build IntelliJ plugin"
task intellij-build:
    @if exists(editors/intellij-jake/build.gradle.kts)
        @cd editors/intellij-jake
            ./gradlew buildPlugin
        echo "Plugin built: editors/intellij-jake/build/distributions/"
    @else
        echo "IntelliJ plugin not yet created at editors/intellij-jake/"
    @end

@group editors
@desc "Clean IntelliJ plugin build artifacts"
task intellij-clean:
    @ignore
    rm -rf editors/intellij-jake/build editors/intellij-jake/.gradle
    echo "IntelliJ plugin cleaned"

@group editors
@desc "Build and launch JetBrains IDE (ide=idea|goland|phpstorm|pycharm|rustrover|webstorm|all)"
task intellij-dev ide="idea": [intellij-build]
    @if eq({{ide}}, "all")
        echo "Launching all JetBrains IDEs..."
        @cd editors/intellij-jake
            ./gradlew runIde &
            ./gradlew runIde -PalternativeIdePath="/Applications/GoLand.app" &
            ./gradlew runIde -PalternativeIdePath="/Applications/PhpStorm.app" &
            ./gradlew runIde -PalternativeIdePath="/Applications/PyCharm.app" &
            ./gradlew runIde -PalternativeIdePath="/Applications/RustRover.app" &
            ./gradlew runIde -PalternativeIdePath="/Applications/WebStorm.app" &
            wait
    @elif eq({{ide}}, "idea")
        @cd editors/intellij-jake
            ./gradlew runIde
    @elif eq({{ide}}, "goland")
        @cd editors/intellij-jake
            ./gradlew runIde -PalternativeIdePath="/Applications/GoLand.app"
    @elif eq({{ide}}, "phpstorm")
        @cd editors/intellij-jake
            ./gradlew runIde -PalternativeIdePath="/Applications/PhpStorm.app"
    @elif eq({{ide}}, "pycharm")
        @cd editors/intellij-jake
            ./gradlew runIde -PalternativeIdePath="/Applications/PyCharm.app"
    @elif eq({{ide}}, "rustrover")
        @cd editors/intellij-jake
            ./gradlew runIde -PalternativeIdePath="/Applications/RustRover.app"
    @elif eq({{ide}}, "webstorm")
        @cd editors/intellij-jake
            ./gradlew runIde -PalternativeIdePath="/Applications/WebStorm.app"
    @else
        echo "Unknown IDE: {{ide}}"
        echo "Valid options: idea, goland, phpstorm, pycharm, rustrover, webstorm, all"
    @end

@group editors
@desc "Publish IntelliJ plugin to JetBrains Marketplace"
task intellij-publish:
    @confirm Publish to JetBrains Marketplace? (requires PUBLISH_TOKEN env var)
    @require PUBLISH_TOKEN
    @cd editors/intellij-jake
        ./gradlew publishPlugin
    echo "Plugin published!"

# ============================================================================
# All Editors
# ============================================================================

@group editors
@desc "Build all editor extensions"
task all: [vscode-package, intellij-build]
    echo "All editor extensions built!"
    @if exists(editors/tree-sitter-jake/grammar.js)
        echo "  - Tree-sitter: run 'jake editors.tree-sitter-generate'"
    @end

@group editors
@desc "Show status of all editor extensions"
task status:
    echo "Editor Extension Status:"
    echo ""
    @if exists(editors/vscode-jake/package.json)
        echo "  VS Code:      OK (editors/vscode-jake/)"
    @else
        echo "  VS Code:      NOT CREATED"
    @end
    @if exists(editors/intellij-jake/build.gradle.kts)
        echo "  IntelliJ:     OK (editors/intellij-jake/)"
    @else
        echo "  IntelliJ:     NOT CREATED"
    @end
    @if exists(editors/tree-sitter-jake/grammar.js)
        echo "  Tree-sitter:  OK (editors/tree-sitter-jake/)"
    @else
        echo "  Tree-sitter:  NOT CREATED"
    @end
    @if exists(editors/vim-jake/syntax/jake.vim)
        echo "  Vim/Neovim:   OK (editors/vim-jake/)"
    @else
        echo "  Vim/Neovim:   NOT CREATED"
    @end
    @if exists(editors/sublime-jake/Jake.sublime-syntax)
        echo "  Sublime Text: OK (editors/sublime-jake/)"
    @else
        echo "  Sublime Text: NOT CREATED"
    @end
    @if exists(editors/zed-jake/extension.toml)
        echo "  Zed:          OK (editors/zed-jake/)"
    @else
        echo "  Zed:          NOT CREATED"
    @end
