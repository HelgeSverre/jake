/**
 * Prism.js syntax highlighting for Jake
 *
 * Usage:
 *   <script src="prism-jake.js"></script>
 *   <pre><code class="language-jake">...</code></pre>
 *
 * Or with npm:
 *   import Prism from 'prismjs';
 *   import './prism-jake';
 */

(function (Prism) {
  if (typeof Prism === 'undefined') {
    console.warn('Prism not loaded - Jake grammar not registered');
    return;
  }

  Prism.languages.jake = {
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

  // Aliases
  Prism.languages.jakefile = Prism.languages.jake;
}(Prism));
