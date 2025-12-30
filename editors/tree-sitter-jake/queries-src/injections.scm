; Specify nested languages that live within a Jakefile

; ================ Always applicable ================

((comment) @injection.content
  (#set! injection.language "comment"))

; Highlight the RHS of `=~` as regex
((regex_literal
  (_) @injection.content)
  (#set! injection.language "regex"))

; ================ Default to bash ================

; Default recipe bodies to bash
(recipe_body
  !shebang
  (#set! injection.language "bash")
  (#set! injection.include-children)) @injection.content

; External commands (backticks) are bash
(external_command
  (command_body) @injection.content
  (#set! injection.language "bash"))

; ================ Shebang-based language detection ================

; Set highlighting for recipes that specify a language using builtin shebang matching
(recipe_body
  (shebang) @injection.shebang
  (#set! injection.include-children)) @injection.content
