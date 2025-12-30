; This file tells us about the scope of variables so e.g. local
; variables override global functions with the same name

; Scope

(recipe) @local.scope

; Definitions

(assignment
  name: (identifier) @local.definition.variable)

(parameter
  name: (identifier) @local.definition.variable)

(recipe_header
  name: (identifier) @local.definition.function)

(import_statement
  namespace: (identifier) @local.definition.namespace)

; References

(function_call
  name: (identifier) @local.reference.function)

(dependency
  name: (dependency_name) @local.reference.function)

(value
  (identifier) @local.reference.variable)
