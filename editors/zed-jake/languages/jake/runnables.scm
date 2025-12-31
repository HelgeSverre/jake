; Jake recipe runnables - enables "Run" button in Zed editor
; Recipes can be run via: jake <recipe_name>

(
  (recipe
    (recipe_header
      name: (identifier) @run @recipe_name))
  (#set! tag jake-recipe)
)
