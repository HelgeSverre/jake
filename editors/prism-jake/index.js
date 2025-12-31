/**
 * Prism.js syntax highlighting for Jake
 *
 * Usage:
 *   // Modern (recommended)
 *   import Prism from 'prismjs';
 *   import { Jakefile } from 'prism-jake';
 *   Jakefile.register(Prism);
 *
 *   // Or with auto-registration (if Prism is global)
 *   <script src="prism.min.js"></script>
 *   <script src="prism-jake.min.js"></script>
 *   <script>Jakefile.register(Prism);</script>
 *
 *   // Then use:
 *   <pre><code class="language-jake">...</code></pre>
 */

var jakeGrammar = {
  'comment': {
    pattern: /#.*/,
    greedy: true
  },
  'string': [
    {
      // Triple-quoted strings
      pattern: /"""[\s\S]*?"""/,
      greedy: true
    },
    {
      // Triple single-quoted (raw)
      pattern: /'''[\s\S]*?'''/,
      greedy: true
    },
    {
      // Double-quoted strings
      pattern: /"(?:[^"\\]|\\.)*"/,
      greedy: true
    },
    {
      // Single-quoted strings (raw)
      pattern: /'[^']*'/,
      greedy: true
    }
  ],
  'interpolation': {
    pattern: /\{\{[\s\S]*?\}\}/,
    inside: {
      'punctuation': /^\{\{|\}\}$/,
      'function': /\b[a-zA-Z_][a-zA-Z0-9_]*(?=\()/,
      'variable': /\b[a-zA-Z_][a-zA-Z0-9_]*\b/,
      'string': /"(?:[^"\\]|\\.)*"|'[^']*'/,
      'operator': /[+\/]/,
      'punctuation': /[(),]/
    }
  },
  'directive': {
    pattern: /^\s*@[a-zA-Z_][a-zA-Z0-9_-]*/m,
    alias: 'keyword'
  },
  'recipe-header': {
    pattern: /^(task|file)\s+[a-zA-Z_][a-zA-Z0-9_-]*|^[a-zA-Z_][a-zA-Z0-9_-]*(?=\s*[:(])/m,
    inside: {
      'keyword': /^(task|file)\b/,
      'function': /[a-zA-Z_][a-zA-Z0-9_-]*/
    }
  },
  'variable-definition': {
    pattern: /^[a-zA-Z_][a-zA-Z0-9_]*\s*[:=]/m,
    inside: {
      'variable': /^[a-zA-Z_][a-zA-Z0-9_]*/,
      'operator': /[:=]+/
    }
  },
  'shell-variable': {
    pattern: /\$(?:\{[a-zA-Z_][a-zA-Z0-9_]*\}|[a-zA-Z_][a-zA-Z0-9_]*|[0-9@])/,
    alias: 'variable'
  },
  'dependency-list': {
    pattern: /\[[^\]]*\]/,
    inside: {
      'punctuation': /[\[\],]/,
      'function': /[a-zA-Z_][a-zA-Z0-9_:-]*/
    }
  },
  'command-prefix': {
    pattern: /^(\s*)[@-]+/m,
    lookbehind: true,
    alias: 'operator'
  },
  'operator': /[:=]|->|==|!=/,
  'punctuation': /[[\](),{}:]/,
  'keyword': /\b(task|file|as|if|else)\b/,
  'builtin': /\b(linux|macos|darwin|windows|freebsd|openbsd|netbsd)\b/
};

/**
 * Unified Jakefile API for Prism.js
 */
var Jakefile = {
  /** Grammar definition object */
  grammar: jakeGrammar,

  /**
   * Register Jake syntax with Prism.js
   * @param {Object} Prism - Prism.js instance
   * @returns {Object} Jakefile object (chainable)
   */
  register: function(Prism) {
    Prism.languages.jake = jakeGrammar;
    Prism.languages.jakefile = jakeGrammar;
    return this;
  }
};

// Auto-register if Prism is global (backwards compatibility)
if (typeof Prism !== 'undefined') {
  Jakefile.register(Prism);
}

// CommonJS exports
if (typeof module !== 'undefined' && module.exports) {
  module.exports = jakeGrammar;
  module.exports.Jakefile = Jakefile;
  module.exports.default = jakeGrammar;
}

// Browser globals
if (typeof window !== 'undefined') {
  window.Jakefile = Jakefile;
}
