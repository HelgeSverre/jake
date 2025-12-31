/**
 * highlight.js syntax highlighting for Jake
 *
 * Usage:
 *   // Modern (recommended)
 *   import hljs from 'highlight.js/lib/core';
 *   import { Jakefile } from 'highlightjs-jake';
 *   Jakefile.register(hljs);
 *
 *   // Or with legacy API
 *   import hljs from 'highlight.js/lib/core';
 *   import jake from 'highlightjs-jake';
 *   hljs.registerLanguage('jake', jake);
 *
 *   // Browser
 *   <script src="highlight.min.js"></script>
 *   <script src="highlightjs-jake.min.js"></script>
 *   <script>Jakefile.register(hljs);</script>
 */

function hljsDefineJake(hljs) {
    const DIRECTIVES = [
        '@import', '@dotenv', '@require', '@export', '@default',
        '@pre', '@post', '@before', '@after', '@on_error',
        '@group', '@desc', '@description', '@alias', '@quiet',
        '@only', '@only-os', '@platform', '@needs',
        '@if', '@elif', '@else', '@end', '@each',
        '@cd', '@cache', '@watch', '@confirm', '@ignore', '@shell'
    ];

    const PLATFORMS = [
        'linux', 'macos', 'darwin', 'windows', 'freebsd', 'openbsd', 'netbsd'
    ];

    const INTERPOLATION = {
        className: 'subst',
        begin: /\{\{/,
        end: /\}\}/,
        contains: [
            {
                className: 'title.function',
                begin: /[a-zA-Z_][a-zA-Z0-9_]*(?=\()/
            },
            {
                className: 'variable',
                begin: /[a-zA-Z_][a-zA-Z0-9_]*/
            },
            hljs.QUOTE_STRING_MODE,
            hljs.APOS_STRING_MODE
        ]
    };

    const STRING = {
        className: 'string',
        variants: [
            {begin: /"""/, end: /"""/},
            {begin: /'''/, end: /'''/},
            {begin: /"/, end: /"/, contains: [hljs.BACKSLASH_ESCAPE, INTERPOLATION]},
            {begin: /'/, end: /'/}
        ]
    };

    const SHELL_VARIABLE = {
        className: 'variable',
        variants: [
            {begin: /\$\{[a-zA-Z_][a-zA-Z0-9_]*\}/},
            {begin: /\$[a-zA-Z_][a-zA-Z0-9_]*/},
            {begin: /\$[0-9@]/}
        ]
    };

    const COMMENT = hljs.COMMENT('#', '$');

    return {
        name: 'Jake',
        aliases: ['jakefile'],
        case_insensitive: false,
        keywords: {
            keyword: 'task file as if else',
            built_in: PLATFORMS.join(' ')
        },
        contains: [
            COMMENT,
            STRING,
            INTERPOLATION,
            SHELL_VARIABLE,
            {
                // Directives
                className: 'keyword',
                begin: new RegExp(DIRECTIVES.map(d => d.replace(/[-@]/g, '\\$&')).join('|'))
            },
            {
                // Recipe header: task name or file name
                className: 'title.function',
                begin: /^(task|file)\s+/,
                end: /:/,
                excludeEnd: true,
                contains: [
                    {
                        className: 'keyword',
                        begin: /^(task|file)\b/
                    },
                    {
                        className: 'title.function',
                        begin: /[a-zA-Z_][a-zA-Z0-9_-]*/
                    },
                    {
                        // Parameters
                        className: 'params',
                        begin: /[a-zA-Z_][a-zA-Z0-9_]*/,
                        relevance: 0
                    }
                ]
            },
            {
                // Simple recipe header (no task/file keyword)
                className: 'title.function',
                begin: /^[a-zA-Z_][a-zA-Z0-9_-]*(?=\s*:)/
            },
            {
                // Variable assignment
                className: 'variable',
                begin: /^[a-zA-Z_][a-zA-Z0-9_]*(?=\s*[:=])/
            },
            {
                // Dependency list
                className: 'meta',
                begin: /\[/,
                end: /\]/,
                contains: [
                    {
                        className: 'title.function',
                        begin: /[a-zA-Z_][a-zA-Z0-9_:-]*/
                    }
                ]
            },
            {
                // Command prefix
                className: 'operator',
                begin: /^(\s*)[@-]+/
            },
            {
                // Operators
                className: 'operator',
                begin: /->|==|!=|:=|=/
            },
            {
                // Backtick commands
                className: 'code',
                begin: /`/,
                end: /`/
            }
        ]
    };
}

/**
 * Unified Jakefile API for highlight.js
 */
var Jakefile = {
    /** Language definition function (for manual registration) */
    definition: hljsDefineJake,

    /**
     * Register Jake syntax with highlight.js
     * @param {Object} hljs - highlight.js instance
     * @returns {Object} Jakefile object (chainable)
     */
    register: function(hljs) {
        hljs.registerLanguage('jake', hljsDefineJake);
        hljs.registerLanguage('jakefile', hljsDefineJake);
        return this;
    }
};

// CommonJS exports
if (typeof module !== 'undefined' && module.exports) {
    module.exports = hljsDefineJake;
    module.exports.Jakefile = Jakefile;
    module.exports.default = hljsDefineJake;
}

// Browser globals
if (typeof window !== 'undefined') {
    window.hljsDefineJake = hljsDefineJake;
    window.Jakefile = Jakefile;
}
