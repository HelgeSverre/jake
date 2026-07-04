; Jake syntax highlighting for tree-sitter

; Comments (highest priority)
(comment) @comment

; Strings
(string) @string
(escape_sequence) @string.escape

; Recipe definitions
(recipe_header
  name: (identifier) @function)

; Recipe type keywords
(recipe_header
  type: _ @keyword)

; Dependencies
(dependency
  name: (dependency_name) @function.call)

; Built-in functions (known list)
(function_call
  name: (identifier) @function.builtin
  (#match? @function.builtin "^(uppercase|lowercase|trim|dirname|basename|extension|without_extension|without_extensions|absolute_path|home|local_bin|shell_config|launch)$"))

; Other function calls
(function_call
  name: (identifier) @function)

; Condition functions (all are built-in)
(condition_function
  name: _ @function.builtin)

; Variables - assignments
(assignment
  name: (identifier) @variable)

; Variables - references in values
(value
  (identifier) @variable)

; Variables inside interpolation
(interpolation
  (expression
    (value
      (identifier) @variable)))

; Parameters
(parameter
  name: (identifier) @variable.parameter)

; Imports
(import_statement
  path: (string) @string
  namespace: (identifier) @namespace)

; Import rooted modifier
(import_statement
  "rooted" @keyword.control.import)

; Recipe metadata directives
(recipe_attribute) @keyword.directive

; Shell variables - environment ($VAR, ${VAR})
((shell_variable) @variable.builtin
  (#match? @variable.builtin "^\\$[A-Za-z_]"))

; Shell variables - positional ($1, $2, $@)
((shell_variable) @variable.parameter
  (#match? @variable.parameter "^\\$[0-9@]"))

; Operators
[
  "="
  ":="
  "->"
  "=="
  "!="
] @operator

; Punctuation
"," @punctuation.delimiter
":" @punctuation.delimiter

[
  "["
  "]"
  "("
  ")"
] @punctuation.bracket

[
  "{{"
  "}}"
] @punctuation.special

; Command prefixes
(command_prefix) @operator

; Numbers
(number) @constant.numeric

; Timeout values
(timeout_value) @constant.numeric

; Glob patterns
(glob_pattern) @string.special

; File paths
(file_path) @string.special.path

; Shebang
(shebang) @keyword.directive

; Errors
(numeric_error) @error

; Directive keywords - control flow
(if_directive) @keyword.control.conditional
(elif_directive) @keyword.control.conditional
(else_directive) @keyword.control.conditional
(end_directive) @keyword.control.conditional

; Directive keywords - loops
(each_directive) @keyword.control.repeat

; Directive keywords - other body directives
(cd_directive) @keyword.directive
(cache_directive) @keyword.directive
(watch_directive) @keyword.directive
(confirm_directive) @keyword.directive
(ignore_directive) @keyword.directive
(shell_directive) @keyword.directive
(timeout_directive) @keyword.directive
(launch_directive) @keyword.directive
(body_needs_directive) @keyword.directive
(body_require_directive) @keyword.directive
(body_export_directive) @keyword.directive
(body_hook) @keyword.directive

; Global directives
(dotenv_directive) @keyword.directive
(require_directive) @keyword.directive
(export_directive) @keyword.directive
(default_directive) @keyword.directive
(rooted_directive) @keyword.directive
(global_hook) @keyword.directive

; Import statement
(import_statement) @keyword.control.import
