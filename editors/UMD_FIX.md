# UMD Pattern Fix for Syntax Highlighters

## Problem

After simplifying the syntax highlighter packages to remove the `Jakefile.register()` abstraction, the browser builds were broken because:

1. The files used ES module syntax (`export default`)
2. When minified and loaded via `<script>` tags, browsers don't understand ES module syntax
3. Error: `Uncaught SyntaxError: Unexpected token 'export'`

## Root Cause

The simplified code tried to support multiple module systems with conditional exports:

```javascript
// This doesn't work when minified for browser <script> tags
export default function hljsDefineJake(hljs) { ... }

if (typeof module !== "undefined" && module.exports) {
  module.exports = hljsDefineJake;
}
```

The `export` statement is ES module syntax that requires the file to be loaded as a module (`<script type="module">`), but we were loading it as a regular script.

## Solution: UMD Pattern

Implemented the **Universal Module Definition (UMD)** pattern, which is the standard way to create JavaScript libraries that work in all environments:

- **Browser `<script>` tags** - Creates globals
- **CommonJS** (Node.js, `require()`)
- **AMD** (RequireJS)
- **ES Modules** (bundlers like Webpack, Vite)

### UMD Wrapper Structure

```javascript
(function (root, factory) {
  if (typeof define === "function" && define.amd) {
    // AMD
    define([], factory);
  } else if (typeof module === "object" && module.exports) {
    // CommonJS
    module.exports = factory();
  } else {
    // Browser globals
    root.globalName = factory();
  }
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  // Your actual module code here
  return function(...) { ... };
});
```

## Changes Made

### 1. highlightjs-jake

**Before:**

```javascript
export default function hljsDefineJake(hljs) { ... }
// + conditional CommonJS/browser exports
```

**After:**

```javascript
(function (root, factory) {
  // UMD wrapper
})(typeof self !== "undefined" ? self : this, function () {
  return function hljsDefineJake(hljs) { ... };
});
```

- Exposes `window.hljsDefineJake` in browsers
- Works with `require()` in Node.js
- Works with `import` in bundlers

### 2. prism-jake

**Before:**

```javascript
const jake = { ... };
// + conditional exports
```

**After:**

```javascript
(function (root, factory) {
  // UMD wrapper with auto-registration
})(typeof self !== "undefined" ? self : this, function () {
  return {
    /* grammar */
  };
});
```

- Auto-registers with Prism if global
- Exposes `window.jakeGrammar` as fallback
- Works in all module systems

## Results

✅ **Browser `<script>` tags work**

```html
<script src="highlightjs-jake.min.js"></script>
<script>
  hljs.registerLanguage("jake", hljsDefineJake);
</script>
```

✅ **Node.js CommonJS works**

```javascript
const jake = require("highlightjs-jake");
hljs.registerLanguage("jake", jake);
```

✅ **ES Modules work**

```javascript
import jake from "highlightjs-jake";
hljs.registerLanguage("jake", jake);
```

✅ **Minification works**

- Terser minifies UMD pattern correctly
- No syntax errors in browser
- All module systems supported

## Build Process

The minified files are built with:

```bash
jake editors.build-highlighters
```

Which runs:

```bash
npx terser editors/highlightjs-jake/src/languages/jake.js \
  -o site/public/libs/highlightjs-jake.min.js -c -m
```

Output sizes:

- `highlightjs-jake.min.js`: ~1.9KB
- `prism-jake.min.js`: ~1.5KB
- `shiki-jake.tmLanguage.json`: ~13KB (uncompressed JSON)

## Testing

Verified that minified files:

1. Start with UMD wrapper: `!function(e,a){...`
2. Export correctly in all environments
3. No syntax errors when loaded in browser
4. Auto-register when appropriate (Prism)

## Lesson Learned

When creating JavaScript libraries that need to work in browsers via `<script>` tags AND as npm packages:

1. **Use UMD pattern** - It's the industry standard for a reason
2. **Don't rely on ES module syntax** in the source if you need browser compatibility
3. **Test minified builds** in the actual environment (browser console)
4. **Use build tools appropriately** - Terser handles UMD well, but not ES modules → globals

The UMD pattern is verbose but reliable for maximum compatibility.
