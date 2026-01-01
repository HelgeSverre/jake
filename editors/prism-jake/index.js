/**
 * Prism.js syntax highlighting for Jake
 *
 * @example
 * // Node.js / ES Modules
 * import Prism from 'prismjs';
 * import jake from 'prism-jake';
 * Prism.languages.jake = jake;
 * Prism.languages.jakefile = jake;
 *
 * @example
 * // Browser (after loading prism.js)
 * <script src="prism-jake.js"></script>
 * <pre><code class="language-jake">task build: ...</code></pre>
 */

(function (root, factory) {
  if (typeof define === "function" && define.amd) {
    // AMD
    define([], factory);
  } else if (typeof module === "object" && module.exports) {
    // CommonJS
    module.exports = factory();
  } else {
    // Browser globals
    var jake = factory();
    // Auto-register if Prism is global
    if (typeof root.Prism !== "undefined") {
      root.Prism.languages.jake = jake;
      root.Prism.languages.jakefile = jake;
    }
    // Also expose as global for manual registration
    root.jakeGrammar = jake;
  }
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  return {
    comment: {
      pattern: /#.*/,
      greedy: true,
    },
    string: [
      {
        // Triple-quoted strings
        pattern: /"""[\s\S]*?"""/,
        greedy: true,
      },
      {
        // Triple single-quoted (raw)
        pattern: /'''[\s\S]*?'''/,
        greedy: true,
      },
      {
        // Double-quoted strings
        pattern: /"(?:[^"\\]|\\.)*"/,
        greedy: true,
      },
      {
        // Single-quoted strings (raw)
        pattern: /'[^']*'/,
        greedy: true,
      },
    ],
    interpolation: {
      pattern: /\{\{[\s\S]*?\}\}/,
      inside: {
        punctuation: /^\{\{|\}\}$/,
        // Built-in functions (must come before generic function)
        "builtin-function":
          /\b(?:dirname|basename|extension|without_extension|without_extensions|absolute_path|abs_path|uppercase|lowercase|trim|home|local_bin|shell_config|env|exists|eq|neq|is_watching|is_dry_run|is_verbose)\b(?=\()/,
        function: /\b[a-zA-Z_][a-zA-Z0-9_]*(?=\()/,
        variable: /\b[a-zA-Z_][a-zA-Z0-9_]*\b/,
        string: /"(?:[^"\\]|\\.)*"|'[^']*'/,
        operator: /[+\/]/,
        punctuation: /[(),]/,
      },
    },
    directive: {
      pattern: /^\s*@[a-zA-Z_][a-zA-Z0-9_-]*/m,
      alias: "keyword",
    },
    "recipe-header": {
      pattern:
        /^(task|file)\s+[a-zA-Z_][a-zA-Z0-9_-]*|^[a-zA-Z_][a-zA-Z0-9_-]*(?=\s*[:(])/m,
      inside: {
        keyword: /^(task|file)\b/,
        function: /[a-zA-Z_][a-zA-Z0-9_-]*/,
      },
    },
    "variable-definition": {
      pattern: /^[a-zA-Z_][a-zA-Z0-9_]*\s*[:=]/m,
      inside: {
        variable: /^[a-zA-Z_][a-zA-Z0-9_]*/,
        operator: /[:=]+/,
      },
    },
    "shell-variable": {
      pattern: /\$(?:\{[a-zA-Z_][a-zA-Z0-9_]*\}|[a-zA-Z_][a-zA-Z0-9_]*|[0-9@])/,
      alias: "variable",
    },
    "dependency-list": {
      pattern: /\[[^\]]*\]/,
      inside: {
        punctuation: /[\[\],]/,
        function: /[a-zA-Z_][a-zA-Z0-9_:-]*/,
      },
    },
    "command-prefix": {
      pattern: /^(\s*)[@-]+/m,
      lookbehind: true,
      alias: "operator",
    },
    operator: /[:=]|->|==|!=/,
    punctuation: /[[\](),{}:]/,
    keyword: /\b(task|file|as|if|else)\b/,
    builtin: /\b(linux|macos|darwin|windows|freebsd|openbsd|netbsd)\b/,
  };
});
