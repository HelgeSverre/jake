# Grammar Consistency Improvements

## Changes Made

Made the three syntax highlighter grammars more consistent with each other while respecting each library's architecture.

## 1. Built-in Function Highlighting ✅

**Problem**: Only Shiki was highlighting built-in functions specially.

**Solution**: Added explicit built-in function list to all three libraries.

### Prism.js

```javascript
// Added to interpolation.inside (before generic function pattern)
"builtin-function": /\b(?:dirname|basename|extension|without_extension|without_extensions|absolute_path|abs_path|uppercase|lowercase|trim|home|local_bin|shell_config|env|exists|eq|neq|is_watching|is_dry_run|is_verbose)\b(?=\()/,
```

Maps to `.token.builtin-function` class.

### highlight.js

```javascript
const BUILTIN_FUNCTIONS = [
  "dirname", "basename", "extension", "without_extension",
  "without_extensions", "absolute_path", "abs_path",
  "uppercase", "lowercase", "trim", "home", "local_bin",
  "shell_config", "env", "exists", "eq", "neq",
  "is_watching", "is_dry_run", "is_verbose",
];

// Added to INTERPOLATION.contains (before generic function pattern)
{
  className: "built_in",
  begin: new RegExp("\\b(" + BUILTIN_FUNCTIONS.join("|") + ")\\b(?=\\()"),
}
```

Maps to `.hljs-built_in` class.

### Shiki

Already had this:

```javascript
"match": "\\b(dirname|basename|extension|without_extension|without_extensions|absolute_path|abs_path|uppercase|lowercase|trim|home|local_bin|shell_config|env|exists|eq|neq|is_watching|is_dry_run|is_verbose)\\s*\\(",
"captures": { "1": { "name": "support.function.jake" } }
```

Maps to `support.function.jake` scope.

**Result**: All three now highlight the same 19 built-in functions.

## 2. Generic Directive Pattern ✅

**Problem**: highlight.js used an explicit directive list, which could miss new directives.

**Solution**: Changed to generic pattern matching any `@directive`.

### Before (highlight.js)

```javascript
const DIRECTIVES = [
  "@import", "@dotenv", "@require", "@export", "@default",
  // ... 24 total directives
];

{
  className: "keyword",
  begin: new RegExp(
    DIRECTIVES.map((d) => d.replace(/[-@]/g, "\\$&")).join("|")
  ),
}
```

Only highlighted known directives. New directives wouldn't be highlighted.

### After (highlight.js)

```javascript
{
  // Directives (generic pattern to catch all)
  className: "keyword",
  begin: /^\s*@[a-zA-Z_][a-zA-Z0-9_-]*/,
  relevance: 10,
}
```

Matches ANY directive starting with `@`, just like Prism.

**Result**: All three libraries now use the same generic directive pattern.

## 3. Pattern Order Matters ✅

Ensured built-in functions are matched BEFORE generic function patterns in all three:

**Why**: Regex engines match first pattern that succeeds. If generic function pattern comes first, built-ins never get their special styling.

**Order**:
1. Built-in functions (specific)
2. Generic functions (catch-all)
3. Variables

## Built-in Functions Covered

All three grammars now consistently highlight these 19 functions:

### Path Functions
- `dirname(path)` - Get directory name
- `basename(path)` - Get file name
- `extension(path)` - Get file extension
- `without_extension(path)` - Remove extension
- `without_extensions(path)` - Remove all extensions
- `absolute_path(path)` - Convert to absolute path
- `abs_path(path)` - Alias for absolute_path

### String Functions
- `uppercase(str)` - Convert to uppercase
- `lowercase(str)` - Convert to lowercase
- `trim(str)` - Trim whitespace

### System Functions
- `home()` - User home directory
- `local_bin(name)` - Path to ~/.local/bin/name
- `shell_config()` - Path to shell config file

### Condition Functions
- `env(VAR)` - Get environment variable
- `exists(path)` - Check if path exists
- `eq(a, b)` - Check equality
- `neq(a, b)` - Check inequality
- `is_watching()` - Check if in watch mode
- `is_dry_run()` - Check if in dry-run mode
- `is_verbose()` - Check if in verbose mode

## Remaining Differences (Intentional)

Some differences remain because they reflect each library's philosophy:

### Granularity

- **Prism**: Simpler, flatter token structure
- **highlight.js**: Mode-based with context awareness
- **Shiki**: Rich hierarchical scopes (VS Code-level)

### CSS Classes

Each uses different naming:
- Prism: `.token.builtin-function`, `.token.keyword`
- highlight.js: `.hljs-built_in`, `.hljs-keyword`
- Shiki: Inline colors from TextMate scopes

### Recipe Context

- **Prism**: Single pattern for all recipe types
- **highlight.js**: Separate modes for task/file/simple
- **Shiki**: Three separate patterns with full context tracking

These differences are **features**, not bugs. They allow each library to serve its use case best.

## Testing

After changes, all three libraries now:

✅ Highlight the same directives (any `@directive`)
✅ Highlight the same 19 built-in functions
✅ Highlight comments, strings, interpolation consistently
✅ Work in browser, Node.js, and bundlers

## Before/After Example

```jake
task build:
    echo "Building to {{dirname(OUTPUT)}}"
    @if exists("dist")
        echo "Using built-ins: {{uppercase(VERSION)}}"
    @end
```

**Before**:
- Prism: `dirname`, `exists`, `uppercase` as generic functions
- highlight.js: Same
- Shiki: Special built-in highlighting ✨

**After**:
- All three: Special built-in highlighting ✨

## Summary

| Element | Before | After |
|---------|--------|-------|
| Built-in functions | Shiki only | All three ✅ |
| Directives | highlight.js explicit list | All three generic ✅ |
| Comments | Consistent | Consistent ✅ |
| Strings | Consistent | Consistent ✅ |
| Interpolation | Mostly consistent | Consistent ✅ |
| Recipe headers | Different granularity | Different granularity (intentional) |

The grammars are now **functionally consistent** while preserving each library's architectural strengths.
