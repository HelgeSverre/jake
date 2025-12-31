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
  name: (dependency_name) @function)

; Function calls in expressions
(function_call
  name: (identifier) @function)

; Condition functions
(condition_function
  name: _ @function)

; Variables - assignments
(assignment
  name: (identifier) @variable)

; Variables - references in values
(value
  (identifier) @variable)

; Parameters
(parameter
  name: (identifier) @variable)

; Imports
(import_statement
  path: (string) @string
  namespace: (identifier) @type)

; Recipe attributes (directives above recipes)
(recipe_attribute
  name: (identifier) @constant)

; Shell variables
(shell_variable) @variable.special

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
(number) @number

; Glob patterns
(glob_pattern) @string.special

; Shebang
(shebang) @keyword

; Directive nodes - highlight the whole directive
(if_directive) @keyword
(elif_directive) @keyword
(else_directive) @keyword
(end_directive) @keyword
(each_directive) @keyword

(cd_directive) @keyword
(cache_directive) @keyword
(watch_directive) @keyword
(confirm_directive) @keyword
(ignore_directive) @keyword
(shell_directive) @keyword
(body_needs_directive) @keyword
(body_require_directive) @keyword
(body_export_directive) @keyword
(body_hook) @keyword

; Global directives
(dotenv_directive) @keyword
(require_directive) @keyword
(export_directive) @keyword
(default_directive) @keyword
(global_hook) @keyword

; Import statement
(import_statement) @keyword
