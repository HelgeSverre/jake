; Specify how to navigate around logical blocks in code
; Zed only supports: @function.around, @function.inside, @class.around, @class.inside, @comment.around, @comment.inside

(recipe
  (recipe_body) @function.inside) @function.around

(comment) @comment.around
