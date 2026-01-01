/**
 * highlight.js syntax highlighting for Jake
 *
 * @example
 * // Node.js / ES Modules
 * import hljs from 'highlight.js/lib/core';
 * import jake from 'highlightjs-jake';
 * hljs.registerLanguage('jake', jake);
 * hljs.registerLanguage('jakefile', jake);
 *
 * @example
 * // Browser (after loading highlight.js)
 * <script src="highlightjs-jake.js"></script>
 * <script>hljs.registerLanguage('jake', hljsDefineJake);</script>
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
    root.hljsDefineJake = factory();
  }
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  return function (hljs) {
    const BUILTIN_FUNCTIONS = [
      "dirname",
      "basename",
      "extension",
      "without_extension",
      "without_extensions",
      "absolute_path",
      "abs_path",
      "uppercase",
      "lowercase",
      "trim",
      "home",
      "local_bin",
      "shell_config",
      "env",
      "exists",
      "eq",
      "neq",
      "is_watching",
      "is_dry_run",
      "is_verbose",
    ];

    const PLATFORMS = [
      "linux",
      "macos",
      "darwin",
      "windows",
      "freebsd",
      "openbsd",
      "netbsd",
    ];

    const INTERPOLATION = {
      className: "subst",
      begin: /\{\{/,
      end: /\}\}/,
      contains: [
        {
          // Built-in functions (must come before generic function)
          className: "built_in",
          begin: new RegExp(
            "\\b(" + BUILTIN_FUNCTIONS.join("|") + ")\\b(?=\\()",
          ),
        },
        {
          className: "title.function",
          begin: /[a-zA-Z_][a-zA-Z0-9_]*(?=\()/,
        },
        {
          className: "variable",
          begin: /[a-zA-Z_][a-zA-Z0-9_]*/,
        },
        hljs.QUOTE_STRING_MODE,
        hljs.APOS_STRING_MODE,
      ],
    };

    const STRING = {
      className: "string",
      variants: [
        { begin: /"""/, end: /"""/ },
        { begin: /'''/, end: /'''/ },
        {
          begin: /"/,
          end: /"/,
          contains: [hljs.BACKSLASH_ESCAPE, INTERPOLATION],
        },
        { begin: /'/, end: /'/ },
      ],
    };

    const SHELL_VARIABLE = {
      className: "variable",
      variants: [
        { begin: /\$\{[a-zA-Z_][a-zA-Z0-9_]*\}/ },
        { begin: /\$[a-zA-Z_][a-zA-Z0-9_]*/ },
        { begin: /\$[0-9@]/ },
      ],
    };

    const COMMENT = hljs.COMMENT("#", "$");

    return {
      name: "Jake",
      aliases: ["jakefile"],
      case_insensitive: false,
      keywords: {
        keyword: "task file as if else",
        built_in: PLATFORMS.join(" "),
      },
      contains: [
        COMMENT,
        STRING,
        INTERPOLATION,
        SHELL_VARIABLE,
        {
          // Directives (generic pattern to catch all)
          className: "keyword",
          begin: /^\s*@[a-zA-Z_][a-zA-Z0-9_-]*/,
          relevance: 10,
        },
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
            {
              // Parameters
              className: "params",
              begin: /[a-zA-Z_][a-zA-Z0-9_]*/,
              relevance: 0,
            },
          ],
        },
        {
          // Simple recipe header (no task/file keyword)
          className: "title.function",
          begin: /^[a-zA-Z_][a-zA-Z0-9_-]*(?=\s*:)/,
        },
        {
          // Variable assignment
          className: "variable",
          begin: /^[a-zA-Z_][a-zA-Z0-9_]*(?=\s*[:=])/,
        },
        {
          // Dependency list
          className: "meta",
          begin: /\[/,
          end: /\]/,
          contains: [
            {
              className: "title.function",
              begin: /[a-zA-Z_][a-zA-Z0-9_:-]*/,
            },
          ],
        },
        {
          // Command prefix
          className: "operator",
          begin: /^(\s*)[@-]+/,
        },
        {
          // Operators
          className: "operator",
          begin: /->|==|!=|:=|=/,
        },
        {
          // Backtick commands
          className: "code",
          begin: /`/,
          end: /`/,
        },
      ],
    };
  };
});
