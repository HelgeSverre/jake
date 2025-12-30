; Outline for Jake - shows recipes in the outline panel

(recipe
  (recipe_header
    name: (identifier) @name)) @item

(assignment
  name: (identifier) @name) @item

(import_statement
  path: (string) @name
  namespace: (identifier)? @context) @item
