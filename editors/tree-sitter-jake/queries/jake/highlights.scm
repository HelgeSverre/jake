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

; Function calls in expressions
(function_call
  name: (identifier) @function.builtin)

; Condition functions
(condition_function
  name: _ @function.builtin)

; Variables - assignments
(assignment
  name: (identifier) @variable)

; Variables - references in values
(value
  (identifier) @variable)

; Parameters
(parameter
  name: (identifier) @variable.parameter)

; Imports
(import_statement
  path: (string) @string
  namespace: (identifier) @namespace)

; Recipe attributes (directives above recipes)
(recipe_attribute
  name: (identifier) @constant)

; Shell variables
(shell_variable) @variable.builtin

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

; Glob patterns
(glob_pattern) @string.special

; Shebang
(shebang) @keyword.directive

; Errors
(numeric_error) @error

; Directive nodes - highlight the whole directive
(if_directive) @keyword.control
(elif_directive) @keyword.control
(else_directive) @keyword.control
(end_directive) @keyword.control
(each_directive) @keyword.control

(cd_directive) @keyword.directive
(cache_directive) @keyword.directive
(watch_directive) @keyword.directive
(confirm_directive) @keyword.directive
(ignore_directive) @keyword.directive
(shell_directive) @keyword.directive
(body_needs_directive) @keyword.directive
(body_require_directive) @keyword.directive
(body_export_directive) @keyword.directive
(body_hook) @keyword.directive

; Global directives
(dotenv_directive) @keyword.directive
(require_directive) @keyword.directive
(export_directive) @keyword.directive
(default_directive) @keyword.directive
(global_hook) @keyword.directive

; Import statement
(import_statement) @keyword.control.import
