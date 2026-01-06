# Jake Editor Plugins - Comprehensive Review

**Date:** 2026-01-06  
**Reviewer:** Amp (AI)

## Executive Summary

After reviewing all 9 editor plugins, I identified several consistency issues and missing features across the ecosystem. The main issues are:

1. **Missing directives**: `@timeout`, `@launch` not in TextMate/Vim grammars
2. **Missing condition function**: `command()` not recognized in any grammar
3. **Incomplete built-in function lists**: Platform functions missing from web grammars
4. **Zed highlights.scm is outdated**: Not synced with improved tree-sitter-jake grammar
5. **Duplication risk**: VS Code and Sublime have identical TextMate grammars (drift risk)

## Plugin Overview

| Plugin | Type | Quality | Missing Features |
|--------|------|---------|------------------|
| **tree-sitter-jake** | Parser | ✅ Excellent (93 tests) | None |
| **vscode-jake** | TextMate | ⚠️ Good | `@timeout`, `@launch`, `command()` |
| **sublime-jake** | TextMate | ⚠️ Good | Same as VS Code (identical file) |
| **intellij-jake** | TextMate (via VS Code) | ⚠️ Good | Inherits VS Code issues |
| **zed-jake** | Tree-sitter queries | ⚠️ Needs update | Outdated highlights.scm |
| **vim-jake** | Vim syntax | ⚠️ Good | `@timeout`, `@launch`, `command()` |
| **highlightjs-jake** | highlight.js | ⚠️ Fair | Platform funcs, `launch`, `command`, `item` |
| **prism-jake** | Prism.js | ⚠️ Fair | Same as highlight.js |
| **shiki-jake** | TextMate | ⚠️ Good | Should sync with VS Code |

## Detailed Findings

### 1. TextMate Grammars (VS Code, Sublime, IntelliJ)

**Files:**
- `vscode-jake/syntaxes/jake.tmLanguage.json`
- `sublime-jake/Jake.tmLanguage.json` (identical copy)
- IntelliJ copies VS Code at build time

**Issues:**

1. **Missing body directives: `@timeout`, `@launch`**
   
   These newer directives are supported by Jake but not highlighted:
   ```jake
   task slow:
       @timeout 30s  # Not highlighted as directive
       @launch "http://localhost:3000"  # Not highlighted
   ```

2. **Missing condition function: `command()`**
   
   The `command()` function for checking if a command exists isn't in the condition pattern:
   ```jake
   @if command(git)  # "command" not highlighted as built-in
       git pull
   @end
   ```

3. **Potential: Add `item` as built-in**
   
   The `{{item}}` variable in `@each` loops is Jake-specific:
   ```jake
   @each foo bar baz
       echo "{{item}}"  # "item" could be highlighted specially
   @end
   ```

**Suggested fixes:**

```jsonc
// Add to recipe-directives patterns:
{
  "name": "meta.directive.timeout.jake",
  "match": "^\\s*(@timeout)\\s+(\\d+[smh])$",
  "captures": {
    "1": { "name": "keyword.control.directive.jake" },
    "2": { "name": "constant.numeric.jake" }
  }
},
{
  "name": "meta.directive.launch.jake",
  "match": "^\\s*(@launch)\\s+(.*)$",
  "captures": {
    "1": { "name": "keyword.control.directive.jake" },
    "2": { "name": "string.unquoted.jake" }
  }
}

// Update condition-expression pattern to include "command":
"match": "\\b(env|exists|eq|neq|command|is_watching|is_dry_run|is_verbose|is_platform|is_macos|is_linux|is_windows|is_unix)\\s*\\("
```

---

### 2. Zed Extension (zed-jake)

**Files:**
- `zed-jake/languages/jake/highlights.scm`
- `zed-jake/extension.toml` (points to tree-sitter-jake)

**Issues:**

1. **Outdated highlights.scm**
   
   The Zed highlights.scm is missing newer tree-sitter-jake nodes:
   - `file_path` (added in recent grammar update)
   - `timeout_value`
   - Proper distinction between `@function.builtin` and `@function`

2. **Incomplete built-in function list**
   
   Current pattern only matches a subset:
   ```scheme
   ; Current (missing many):
   (#match? @function.builtin "^(uppercase|lowercase|trim|dirname|basename|extension|without_extension|without_extensions|absolute_path|home|local_bin|shell_config|launch)$")
   
   ; Should include:
   ; abs_path, env, exists, eq, neq, is_watching, is_dry_run, is_verbose,
   ; is_platform, is_macos, is_linux, is_windows, is_unix, item, command
   ```

3. **Extension.toml uses local path**
   
   ```toml
   repository = "file:///Users/helge/code/jake"  # Should be GitHub URL for release
   ```

**Suggested action:** Copy the improved `highlights.scm` from `tree-sitter-jake/queries/jake/` to `zed-jake/languages/jake/`.

---

### 3. Vim Plugin (vim-jake)

**File:** `vim-jake/syntax/jake.vim`

**Status:** ✅ Good overall - most complete Vim syntax

**Issues:**

1. **Missing directives: `@timeout`, `@launch`**
   
   Need to add:
   ```vim
   syn match jakeDirective "^\s\+@\(timeout\|launch\)\>"
   ```

2. **Missing `command` in condition functions**
   
   ```vim
   " Add 'command' to the pattern:
   syn match jakeCondFunc "\<\(env\|exists\|eq\|neq\|command\|is_watching\|is_dry_run\|is_verbose\|is_platform\|is_macos\|is_linux\|is_windows\|is_unix\)\s*("
   ```

3. **Has `item` (good!)** - Vim is the only plugin that recognizes `item` as built-in

---

### 4. Web Grammars (highlight.js, Prism)

**Files:**
- `highlightjs-jake/src/languages/jake.js`
- `prism-jake/index.js`

**Issues:**

Both are missing from their `BUILTIN_FUNCTIONS` list:
- `launch`
- `is_platform`, `is_macos`, `is_linux`, `is_windows`, `is_unix`
- `command`
- `item`

**Suggested fix for both:**

```javascript
const BUILTIN_FUNCTIONS = [
  // Path functions
  "dirname", "basename", "extension",
  "without_extension", "without_extensions",
  "absolute_path", "abs_path",
  // String functions
  "uppercase", "lowercase", "trim",
  // System functions
  "home", "local_bin", "shell_config", "launch",
  // Condition/check functions
  "env", "exists", "eq", "neq", "command",
  // Runtime state
  "is_watching", "is_dry_run", "is_verbose",
  // Platform checks
  "is_platform", "is_macos", "is_linux", "is_windows", "is_unix",
  // Loop helper
  "item",
];
```

---

### 5. Shiki-jake

**File:** `shiki-jake/jake.tmLanguage.json`

**Status:** Should be synced with VS Code TextMate grammar.

**Action:** Verify it matches `vscode-jake/syntaxes/jake.tmLanguage.json` after updates.

---

## Canonical Reference Lists

To maintain consistency, all plugins should recognize these elements:

### Directives

**Global (top-level):**
- `@import`, `@dotenv`, `@require`, `@export`, `@default`
- `@pre`, `@post`, `@on_error`, `@before`, `@after`

**Recipe attributes (before recipe):**
- `@group`, `@desc`, `@description`, `@alias`, `@quiet`
- `@only`, `@only-os`, `@platform`
- `@needs` (with hint/fallback variants)

**Body directives (inside recipes):**
- `@if`, `@elif`, `@else`, `@end`
- `@each`
- `@cd`, `@cache`, `@watch`, `@confirm`, `@ignore`, `@shell`
- `@timeout`, `@launch`
- `@needs`, `@require`, `@export`
- `@pre`, `@post`

### Built-in Functions (27 total)

**Path functions:**
- `dirname`, `basename`, `extension`
- `without_extension`, `without_extensions`
- `absolute_path`, `abs_path`

**String functions:**
- `uppercase`, `lowercase`, `trim`

**System functions:**
- `home`, `local_bin`, `shell_config`, `launch`

**Condition functions:**
- `env`, `exists`, `eq`, `neq`, `command`

**Runtime state:**
- `is_watching`, `is_dry_run`, `is_verbose`

**Platform checks:**
- `is_platform`, `is_macos`, `is_linux`, `is_windows`, `is_unix`

**Loop helper:**
- `item`

---

## Recommended Actions (Priority Order)

### High Priority

1. **Update TextMate grammar** (affects VS Code, Sublime, IntelliJ, Shiki)
   - Add `@timeout`, `@launch` directives
   - Add `command` to condition functions
   - Effort: 15 minutes

2. **Sync Zed highlights.scm** with tree-sitter-jake
   - Copy from `tree-sitter-jake/queries/jake/highlights.scm`
   - Effort: 5 minutes

3. **Update Vim syntax**
   - Add `@timeout`, `@launch`, `command`
   - Effort: 10 minutes

### Medium Priority

4. **Update web grammars** (highlight.js, Prism)
   - Expand BUILTIN_FUNCTIONS list
   - Effort: 10 minutes

5. **Add `item` to all built-in lists**
   - Currently only Vim has it
   - Effort: 10 minutes

### Low Priority (Maintainability)

6. **Create canonical spec file** (`editors/syntax-spec.json`)
   - Single source of truth for directives and built-ins
   - Use for validation/generation
   - Effort: 30 minutes

7. **Deduplicate TextMate files**
   - Have Sublime/Shiki reference or symlink to VS Code
   - Effort: 15 minutes

8. **Fix Zed extension.toml**
   - Update to use GitHub URL with pinned commit
   - Effort: 5 minutes

---

## Consistency Matrix

| Feature | tree-sitter | VS Code | Sublime | Zed | Vim | hljs | Prism |
|---------|-------------|---------|---------|-----|-----|------|-------|
| `@timeout` | ✅ | ❌ | ❌ | ⚠️ | ❌ | ✅* | ✅* |
| `@launch` | ✅ | ❌ | ❌ | ⚠️ | ❌ | ✅* | ✅* |
| `command()` | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| `item` | ⚠️ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| Platform funcs | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| `file_path` | ✅ | N/A | N/A | ❌ | N/A | N/A | N/A |

*Web grammars use generic `@directive` pattern, so they catch these but don't distinguish

---

## Conclusion

The editor plugin ecosystem is in good shape overall, with the main issues being:
1. Some newer directives (`@timeout`, `@launch`) missing from TextMate/Vim
2. The `command()` condition function missing everywhere except tree-sitter
3. Zed needing an updated highlights.scm

Total estimated effort to fix all issues: **~1.5 hours**
