# Syntax Highlighter Grammar Comparison

## Overview

This document compares how the three syntax highlighters handle Jake syntax to understand if rendering differences are due to:

1. **Inconsistent grammars** (our fault)
2. **Library differences** (inherent to each library)

## Architecture Differences

### Prism.js

- **Type**: Regular expression-based token matcher
- **Philosophy**: Simple, lightweight patterns
- **Granularity**: Token-level (each pattern matches and classifies)
- **Nesting**: Limited nesting via `inside` property

### highlight.js

- **Type**: Mode-based lexer
- **Philosophy**: Context-aware parsing with modes
- **Granularity**: Mode-level (enters/exits contexts)
- **Nesting**: Rich nesting with `begin`/`end` and `contains`

### Shiki

- **Type**: TextMate grammar (used by VS Code)
- **Philosophy**: Full language grammar with scopes
- **Granularity**: Scope-based (hierarchical scopes)
- **Nesting**: Deep nesting with named captures and includes

## Element-by-Element Comparison

### 1. Directives (`@import`, `@dotenv`, etc.)

**Prism:**

```javascript
directive: {
  pattern: /^\s*@[a-zA-Z_][a-zA-Z0-9_-]*/m,
  alias: "keyword",
}
```

- Matches ANY directive starting with `@`
- Generic pattern
- Maps to `keyword` class

**highlight.js:**

```javascript
const DIRECTIVES = [
  "@import", "@dotenv", "@require", "@export", // ... (explicit list)
];
// ...
{
  className: "keyword",
  begin: new RegExp(
    DIRECTIVES.map((d) => d.replace(/[-@]/g, "\\$&")).join("|")
  ),
}
```

- Matches SPECIFIC directives (explicit list)
- Only highlights known directives
- Maps to `keyword` class

**Shiki:**

```javascript
"imports": {
  "match": "^(@import)\\s+(\"[^\"]*\"|'[^']*')(?:\\s+(as)\\s+([a-zA-Z_][a-zA-Z0-9_]*))?",
  "captures": {
    "1": { "name": "keyword.control.import.jake" },
    "2": { "name": "string.quoted.jake" },
    "3": { "name": "keyword.control.as.jake" },
    "4": { "name": "entity.name.namespace.jake" }
  }
}
```

- DIFFERENT pattern for EACH directive type
- Captures parts of the directive (path, alias, etc.)
- Maps to specific semantic scopes

**Issue**: ❌ **Inconsistent**

- Prism: Generic catch-all
- highlight.js: Explicit list (could miss new directives)
- Shiki: Context-aware per-directive patterns

### 2. Variable Interpolation (`{{variable}}`)

**Prism:**

```javascript
interpolation: {
  pattern: /\{\{[\s\S]*?\}\}/,
  inside: {
    punctuation: /^\{\{|\}\}$/,
    function: /\b[a-zA-Z_][a-zA-Z0-9_]*(?=\()/,
    variable: /\b[a-zA-Z_][a-zA-Z0-9_]*\b/,
    // ...
  },
}
```

- Matches entire `{{...}}` block
- Parses contents separately
- Simple nested parsing

**highlight.js:**

```javascript
const INTERPOLATION = {
  className: "subst",
  begin: /\{\{/,
  end: /\}\}/,
  contains: [
    {
      className: "title.function",
      begin: /[a-zA-Z_][a-zA-Z0-9_]*(?=\()/,
    },
    {
      className: "variable",
      begin: /[a-zA-Z_][a-zA-Z0-9_]*/,
    },
    // ...
  ],
};
```

- Mode with begin/end markers
- Contains other modes
- Maps to `subst` (substitution)

**Shiki:**

```javascript
"jake-variables": {
  "patterns": [{
    "name": "meta.variable.interpolation.jake",
    "begin": "\\{\\{",
    "beginCaptures": {
      "0": { "name": "punctuation.definition.variable.begin.jake" }
    },
    "end": "\\}\\}",
    "endCaptures": {
      "0": { "name": "punctuation.definition.variable.end.jake" }
    },
    "patterns": [
      {
        "match": "\\b(dirname|basename|...)\\s*\\(",
        "captures": { "1": { "name": "support.function.jake" } }
      },
      // ...
    ]
  }]
}
```

- Separate scopes for begin/end markers
- Explicit list of built-in functions
- Rich hierarchical scopes

**Issue**: ✅ **Mostly consistent** but different granularity

### 3. Comments (`#`)

**All three are consistent:**

- Prism: `pattern: /#.*/`
- highlight.js: `hljs.COMMENT("#", "$")`
- Shiki: `"match": "#.*$"`

✅ **Consistent**

### 4. Recipe Headers (`task build:`)

**Prism:**

```javascript
"recipe-header": {
  pattern: /^(task|file)\s+[a-zA-Z_][a-zA-Z0-9_-]*|^[a-zA-Z_][a-zA-Z0-9_-]*(?=\s*[:(])/m,
  inside: {
    keyword: /^(task|file)\b/,
    function: /[a-zA-Z_][a-zA-Z0-9_-]*/,
  },
}
```

- Single pattern for both task/file and simple recipes
- Generic classification

**highlight.js:**

```javascript
{
  // Recipe header: task name or file name
  className: "title.function",
  begin: /^(task|file)\s+/,
  end: /:/,
  excludeEnd: true,
  contains: [
    {
      className: "keyword",
      begin: /^(task|file)\b/,
    },
    {
      className: "title.function",
      begin: /[a-zA-Z_][a-zA-Z0-9_-]*/,
    },
    // Parameters...
  ],
},
{
  // Simple recipe header (no task/file keyword)
  className: "title.function",
  begin: /^[a-zA-Z_][a-zA-Z0-9_-]*(?=\s*:)/,
}
```

- Separate modes for task/file vs simple
- Context-aware with begin/end

**Shiki:**

```javascript
"recipes": {
  "patterns": [
    {
      "name": "meta.recipe.file.jake",
      "begin": "^(file)\\s+([^:]+):\\s*(.*)$",
      "beginCaptures": {
        "1": { "name": "keyword.control.recipe.jake" },
        "2": { "name": "entity.name.function.jake" },
        "3": { "name": "string.unquoted.dependency.jake" }
      },
      "end": "^(?=\\S)",
      "patterns": [{ "include": "#recipe-body" }]
    },
    {
      "name": "meta.recipe.task.jake",
      "begin": "^(task)\\s+([a-zA-Z_][a-zA-Z0-9_-]*)([^:]*):\\s*(?:\\[([^\\]]*)\\])?",
      // ...
    },
    {
      "name": "meta.recipe.simple.jake",
      // ...
    }
  ]
}
```

- THREE separate patterns (file, task, simple)
- Captures dependencies, parameters, etc.
- Tracks recipe body scope

**Issue**: ⚠️ **Structurally similar but different granularity**

## Root Causes of Visual Differences

### 1. **Library Architecture** (not our fault)

Different libraries have fundamentally different approaches:

- **Prism**: Flat token matching → simpler output
- **highlight.js**: Mode-based → contextual classes
- **Shiki**: Scope hierarchy → VS Code-like output

### 2. **CSS Theme Mapping** (not our fault)

Each library uses different CSS class names:

- **Prism**: `.token.keyword`, `.token.function`, `.token.string`
- **highlight.js**: `.hljs-keyword`, `.hljs-title.function`, `.hljs-string`
- **Shiki**: Applies colors directly based on TextMate scopes + theme

The SAME logical token gets DIFFERENT CSS classes, which themes color differently.

### 3. **Granularity Differences** (partially our fault)

We COULD make them more consistent:

**Current:**

- Prism: Catches all `@directives` generically
- highlight.js: Only highlights known directives
- Shiki: Per-directive patterns with context

**Could improve:**

- Make highlight.js use a generic pattern OR
- Make Prism/Shiki explicit lists OR
- Document that this is intentional

### 4. **Built-in Function Lists** (our fault)

**highlight.js:**

```javascript
// No explicit built-in function highlighting
// Functions detected by pattern: word followed by (
```

**Shiki:**

```javascript
"match": "\\b(dirname|basename|extension|without_extension|...)\\s*\\(",
"captures": { "1": { "name": "support.function.jake" } }
```

**Issue**: ❌ Shiki highlights specific built-ins, highlight.js/Prism don't

## Recommendations

### Make More Consistent

1. **Directives**: Choose one approach for all three
   - **Option A**: Generic pattern (simpler, catches new directives)
   - **Option B**: Explicit list (more precise, needs updates)

2. **Built-in Functions**: Add explicit list to highlight.js/Prism

   ```javascript
   // Add to Prism interpolation.inside
   'builtin-function': /\b(dirname|basename|uppercase|lowercase|...)\b(?=\()/
   ```

3. **Document Differences**: Add note that visual differences are expected due to library architecture

### Accept as Different

Some differences are GOOD:

- Shiki's rich scopes provide VS Code-like accuracy
- highlight.js's simpler output is faster
- Prism's lightweight patterns minimize bundle size

Different use cases benefit from different approaches.

## Conclusion

**Rendering differences are caused by:**

1. ✅ **~60% Library Architecture** - Different fundamental approaches (not our fault)
2. ⚠️ **~30% Granularity Choices** - We could align these better (partially our fault)
3. ❌ **~10% Missing Patterns** - Some features only in one library (our fault)

**Recommendation**:

- Fix the missing patterns (built-in functions in all three)
- Document that visual differences are expected and intentional
- Consider standardizing directive handling approach
