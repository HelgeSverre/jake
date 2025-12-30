/**
 * @file Jake grammar for tree-sitter
 * @author Jake contributors
 * @license MIT
 * @description Forked from tree-sitter-just by Anshuman Medhi, Trevor Gross, Amaan Qureshi
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

const ESCAPE_SEQUENCE = token(/\\([nrt"\\]|(\r?\n))/);
// Flags to `/usr/bin/env`, anything that starts with a dash
const SHEBANG_ENV_FLAG = token(/-\S*/);

/**
 * Creates a rule to match one or more of the rules separated by a comma
 *
 * @param {RuleOrLiteral} rule
 *
 * @return {SeqRule}
 */
function comma_sep1(rule) {
  return seq(rule, repeat(seq(",", rule)));
}

/**
 * Creates a rule to match an array-like structure filled with `item`
 *
 * @param {RuleOrLiteral} rule
 *
 * @return {Rule}
 */
function array(rule) {
  const item = field("element", rule);
  return field(
    "array",
    seq(
      "[",
      optional(field("content", seq(comma_sep1(item), optional(item)))),
      "]",
    ),
  );
}

module.exports = grammar({
  name: "jake",

  externals: ($) => [
    $._indent,
    $._dedent,
    $._newline,
    $.text,
    $.error_recovery,
  ],

  // Allow comments, backslash-escaped newlines (with optional trailing whitespace),
  // and whitespace anywhere
  extras: ($) => [$.comment, /\\(\n|\r\n)\s*/, /\s/],

  inline: ($) => [
    $._string,
    $._string_indented,
    $._raw_string_indented,
    $._expression_recurse,
  ],
  word: ($) => $.identifier,

  rules: {
    // justfile      : item* EOF
    source_file: ($) =>
      seq(optional(seq($.shebang, $._newline)), repeat($._item)),

    // Jake items - recipes and top-level directives
    _item: ($) =>
      choice(
        $.recipe,
        $.assignment,
        $.import_statement,
        $.global_directive,
      ),

    // Jake assignment: NAME = expression (or NAME := expression for compatibility)
    assignment: ($) =>
      seq(
        field("name", $.identifier),
        choice("=", ":="),
        field("value", $.expression),
        $._newline,
      ),

    // Jake import: @import "file.jake" as namespace
    import_statement: ($) =>
      seq(
        "@import",
        field("path", $.string),
        optional(seq("as", field("namespace", $.identifier))),
        $._newline,
      ),

    // Jake global directives (top-level, not indented)
    global_directive: ($) =>
      choice(
        $.dotenv_directive,
        $.require_directive,
        $.export_directive,
        $.default_directive,
        $.global_hook,
      ),

    // @dotenv or @dotenv .env.local
    dotenv_directive: ($) =>
      seq(
        "@dotenv",
        optional(field("path", choice($.string, $.identifier))),
        $._newline,
      ),

    // @require VAR1 VAR2
    require_directive: ($) =>
      seq(
        "@require",
        repeat1(field("variable", $.identifier)),
        $._newline,
      ),

    // @export VAR = value or @export VAR
    export_directive: ($) =>
      seq(
        "@export",
        field("name", $.identifier),
        optional(seq("=", field("value", $.expression))),
        $._newline,
      ),

    // @default (marks next recipe as default)
    default_directive: (_) => seq("@default", /\s*\n/),

    // @pre, @post, @on_error, @before, @after hooks
    global_hook: ($) =>
      choice(
        seq(
          choice("@pre", "@post", "@on_error"),
          field("command", $.hook_command),
          $._newline,
        ),
        seq(
          choice("@before", "@after"),
          field("target", $.identifier),
          field("command", $.hook_command),
          $._newline,
        ),
      ),

    // Command text for hooks (everything until newline)
    hook_command: ($) => repeat1(choice($.text, $.interpolation, /[^\n]+/)),

    // expression    : 'if' condition '{' expression '}' 'else' '{' expression '}'
    //               | value '/' expression
    //               | value '+' expression
    //               | value
    expression: ($) => seq(optional("/"), $._expression_inner),

    _expression_inner: ($) =>
      choice(
        $.if_expression,
        prec.left(2, seq($._expression_recurse, "+", $._expression_recurse)),
        prec.left(1, seq($._expression_recurse, "/", $._expression_recurse)),
        $.value,
      ),

    // We can't mark `_expression_inner` inline because it causes an infinite
    // loop at generation, so we just alias it.
    _expression_recurse: ($) => alias($._expression_inner, "expression"),

    if_expression: ($) =>
      seq(
        "if",
        $.condition,
        field("consequence", $._braced_expr),
        repeat(field("alternative", $.else_if_clause)),
        optional(field("alternative", $.else_clause)),
      ),

    else_if_clause: ($) => seq("else", "if", $.condition, $._braced_expr),

    else_clause: ($) => seq("else", $._braced_expr),

    _braced_expr: ($) => seq("{", field("body", $.expression), "}"),

    // condition     : expression '==' expression
    //               | expression '!=' expression
    //               | expression '=~' expression
    condition: ($) =>
      choice(
        seq($.expression, "==", $.expression),
        seq($.expression, "!=", $.expression),
        seq($.expression, "=~", choice($.regex_literal, $.expression)),
        // verify whether this is valid
        $.expression,
      ),

    // Capture this special for injections
    regex_literal: ($) => prec(1, $.string),

    // value         : NAME '(' sequence? ')'
    //               | BACKTICK
    //               | INDENTED_BACKTICK
    //               | NAME
    //               | string
    //               | shell_variable
    //               | '(' expression ')'
    value: ($) =>
      prec.left(
        choice(
          $.function_call,
          $.external_command,
          $.identifier,
          $.string,
          $.shell_variable,
          $.numeric_error,
          seq("(", $.expression, ")"),
        ),
      ),

    // Shell/positional variables: $1, $@, $VAR, ${VAR}
    shell_variable: (_) => choice(
      /\$[0-9@]/,          // $1, $2, $@
      /\$[a-zA-Z_][a-zA-Z0-9_]*/,  // $VAR
      /\$\{[a-zA-Z_][a-zA-Z0-9_]*\}/,  // ${VAR}
    ),

    function_call: ($) =>
      seq(
        field("name", $.identifier),
        "(",
        optional(field("arguments", $.sequence)),
        ")",
      ),

    external_command: ($) =>
      choice(seq($._backticked), seq($._indented_backticked)),

    // sequence      : expression ',' sequence
    //               | expression ','?
    sequence: ($) => comma_sep1($.expression),

    attribute: ($) =>
      seq(
        "[",
        comma_sep1(
          choice(
            $.identifier,
            seq(
              $.identifier,
              "(",
              field("argument", comma_sep1($.string)),
              ")",
            ),
            seq($.identifier, ":", field("argument", $.string)),
          ),
        ),
        "]",
        $._newline,
      ),

    // Jake recipe with optional metadata directives
    // recipe : metadata* (task|file)? NAME parameters? ':' dependencies? body?
    recipe: ($) =>
      seq(
        repeat($.recipe_attribute),
        $.recipe_header,
        $._newline,
        optional($.recipe_body),
      ),

    // Recipe metadata directives (@group, @desc, @alias, @needs, @quiet, @only, etc.)
    recipe_attribute: ($) =>
      choice(
        seq("@group", field("name", choice($.identifier, $.string)), $._newline),
        seq(choice("@desc", "@description"), field("text", $.string), $._newline),
        seq("@alias", repeat1(field("name", $.identifier)), $._newline),
        seq("@quiet", $._newline),
        seq(choice("@only", "@only-os", "@platform"), repeat1(field("platform", $.identifier)), $._newline),
        seq("@needs", repeat1(choice(
          seq($.identifier, "->", $.identifier),  // cmd -> install_task
          seq($.identifier, $.string),             // cmd "install hint"
          $.identifier,                            // just cmd
        )), $._newline),
      ),

    recipe_header: ($) =>
      seq(
        optional(field("type", choice("task", "file"))),
        field("name", $.identifier),
        optional($.parameters),
        ":",
        optional($.dependencies),
      ),

    parameters: ($) =>
      seq(repeat($.parameter), choice($.parameter, $.variadic_parameter)),

    // FIXME: do we really have leading `$`s here?`
    // parameter     : '$'? NAME
    //               | '$'? NAME '=' value
    parameter: ($) =>
      seq(
        optional("$"),
        field("name", $.identifier),
        optional(seq("=", field("default", $.value))),
      ),

    // variadic_parameters      : '*' parameter
    //               | '+' parameter
    variadic_parameter: ($) =>
      seq(field("kleene", choice("*", "+")), $.parameter),

    // Jake dependencies: [dep1, dep2, dep3] or [dep1, dep2]
    dependencies: ($) =>
      seq(
        "[",
        optional(seq(
          $.dependency,
          repeat(seq(",", $.dependency)),
          optional(","),
        )),
        "]",
      ),

    // dependency: identifier or namespaced (namespace:recipe)
    dependency: ($) => field("name", $.dependency_name),

    // Dependency name can include namespace prefix (ns:recipe or ns.recipe)
    dependency_name: (_) => /[a-zA-Z_][a-zA-Z0-9_:-]*/,

    // body : INDENT (directive | command)+ DEDENT
    recipe_body: ($) =>
      seq(
        $._indent,
        optional(seq(field("shebang", $.shebang), $._newline)),
        repeat(choice(
          seq($.body_directive, $._newline),
          seq($.command_line, $._newline),
          $._newline,
        )),
        $._dedent,
      ),

    // Body directives: @if, @elif, @else, @end, @each, @cd, etc.
    body_directive: ($) =>
      choice(
        $.if_directive,
        $.elif_directive,
        $.else_directive,
        $.end_directive,
        $.each_directive,
        $.cd_directive,
        $.cache_directive,
        $.watch_directive,
        $.confirm_directive,
        $.ignore_directive,
        $.shell_directive,
        $.body_needs_directive,
        $.body_require_directive,
        $.body_export_directive,
        $.body_hook,
      ),

    // @if condition
    if_directive: ($) =>
      seq("@if", field("condition", $.condition_expression)),

    // @elif condition
    elif_directive: ($) =>
      seq("@elif", field("condition", $.condition_expression)),

    // @else
    else_directive: (_) => "@else",

    // @end
    end_directive: (_) => "@end",

    // @each item1 item2 item3 or @each {{variable}} or @each 10 50 100
    each_directive: ($) =>
      seq("@each", repeat1(choice($.identifier, $.interpolation, $.number))),

    // Simple number for @each
    number: (_) => /\d+/,

    // @cd path
    cd_directive: ($) =>
      seq("@cd", field("path", choice($.string, $.identifier, $.interpolation))),

    // @cache file1 file2
    cache_directive: ($) =>
      seq("@cache", repeat1(field("path", choice($.string, $.identifier, $.glob_pattern)))),

    // @watch pattern
    watch_directive: ($) =>
      seq("@watch", repeat1(field("pattern", choice($.string, $.identifier, $.glob_pattern)))),

    // @confirm "message" or @confirm unquoted message with {{interpolation}}
    confirm_directive: ($) =>
      seq("@confirm", optional(field("message", choice(
        $.string,
        repeat1(choice($.text, $.interpolation, /[^\n]+/)),
      )))),

    // @ignore
    ignore_directive: (_) => "@ignore",

    // @shell bash
    shell_directive: ($) =>
      seq("@shell", field("shell", $.identifier)),

    // @needs cmd or @needs cmd "hint" or @needs cmd -> task (inside recipe body)
    body_needs_directive: ($) =>
      seq("@needs", repeat1(choice(
        seq($.identifier, "->", $.identifier),  // cmd -> install_task
        seq($.identifier, $.string),             // cmd "install hint"
        $.identifier,                            // just cmd
      ))),

    // @require VAR (inside recipe body)
    body_require_directive: ($) =>
      seq("@require", repeat1(field("variable", $.identifier))),

    // @export VAR = value (inside recipe body)
    body_export_directive: ($) =>
      seq(
        "@export",
        field("name", $.identifier),
        optional(seq("=", field("value", $.expression))),
      ),

    // @pre, @post hooks inside recipe body
    body_hook: ($) =>
      seq(
        choice("@pre", "@post"),
        field("command", repeat1(choice($.text, $.interpolation, /[^\n]+/))),
      ),

    // Condition expression for @if/@elif
    condition_expression: ($) =>
      choice(
        // Function calls: env(VAR), exists(path), eq(a, b), neq(a, b)
        $.condition_function,
        // Simple identifier
        $.identifier,
      ),

    condition_function: ($) =>
      seq(
        field("name", choice(
          "env", "exists", "eq", "neq",
          "is_watching", "is_dry_run", "is_verbose",
        )),
        "(",
        optional(field("arguments", $.sequence)),
        ")",
      ),

    // Glob pattern (contains * or **)
    glob_pattern: (_) => /[a-zA-Z0-9_.*\/\-]+\*[a-zA-Z0-9_.*\/\-]*/,

    // Command line in recipe body
    command_line: ($) =>
      seq(
        optional($.command_prefix),
        repeat1(choice($.text, $.interpolation)),
      ),

    // Command prefix: @ (quiet), - (ignore errors), or combination
    command_prefix: (_) => choice("@-", "-@", "@", "-"),

    // Any shebang. Needs a named field to apply injection queries correctly.
    shebang: ($) =>
      seq(/#![ \t]*/, choice($._shebang_with_lang, $._opaque_shebang)),

    // Shebang with a nested `language` token that we can extract
    _shebang_with_lang: ($) =>
      seq(
        /\S*\//,
        optional(seq("env", repeat(SHEBANG_ENV_FLAG))),
        alias($.identifier, $.language),
        /.*/,
      ),

    // Fallback shebang, any string
    _opaque_shebang: (_) => /[^/\n]+/,

    // string        : STRING
    //               | INDENTED_STRING
    //               | RAW_STRING
    //               | INDENTED_RAW_STRING
    string: ($) =>
      choice(
        $._string_indented,
        $._raw_string_indented,
        $._string,
        // _raw_string, can't be written as a separate inline for osm reason
        /'[^']*'/,
      ),

    _raw_string_indented: (_) => seq("'''", repeat(/./), "'''"),
    _string: ($) => seq('"', repeat(choice($.escape_sequence, /[^\\"]+/)), '"'),
    // We need try two separate munches so neither escape sequences nor
    // potential closing quotes get eaten.
    _string_indented: ($) =>
      seq('"""', repeat(choice($.escape_sequence, /[^\\]?[^\\"]+/)), '"""'),

    escape_sequence: (_) => ESCAPE_SEQUENCE,

    _backticked: ($) => seq("`", optional($.command_body), "`"),
    _indented_backticked: ($) => seq("```", optional($.command_body), "```"),

    command_body: ($) => repeat1(choice($.interpolation, /./)),

    // interpolation : '{{' expression '}}'
    interpolation: ($) => seq("{{", $.expression, "}}"),

    identifier: (_) => /[a-zA-Z_][a-zA-Z0-9_-]*/,

    // Numbers aren't allowed as values, but we capture them anyway as errors so
    // they don't mess up the whole syntax
    numeric_error: (_) => /(\d+\.\d*|\d+)/,

    // `# ...` comment
    comment: (_) => token(prec(-1, /#.*/)),
  },
});
