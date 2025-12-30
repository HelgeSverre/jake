" Vim syntax file for Jake
" Language: Jake
" Maintainer: Jake contributors

if exists("b:current_syntax")
  finish
endif

" Comments
syn match jakeComment "#.*$" contains=jakeTodo
syn keyword jakeTodo contained TODO FIXME XXX NOTE HACK

" Recipe keywords
syn keyword jakeKeyword task file default nextgroup=jakeRecipeName skipwhite

" Recipe names (after task/file keyword)
syn match jakeRecipeName "\<[a-zA-Z_][a-zA-Z0-9_-]*\>" contained nextgroup=jakeParams,jakeColon skipwhite

" Simple recipe names (name followed by colon at start of line)
syn match jakeSimpleRecipe "^[a-zA-Z_][a-zA-Z0-9_-]*\ze:" contains=jakeRecipeNameDef
syn match jakeRecipeNameDef "[a-zA-Z_][a-zA-Z0-9_-]*" contained

" Parameters
syn region jakeParams start="\s" end=":"me=e-1 contained contains=jakeParam,jakeParamDefault
syn match jakeParam "\<[a-zA-Z_][a-zA-Z0-9_]*\>" contained
syn match jakeParamDefault "\<[a-zA-Z_][a-zA-Z0-9_]*\s*=\s*\"[^\"]*\"" contained contains=jakeString

" Dependency list
syn region jakeDeps start="\[" end="\]" contains=jakeDepName
syn match jakeDepName "\<[a-zA-Z_][a-zA-Z0-9_:-]*\>" contained

" Import statements
syn match jakeImport "^@import\s\+" nextgroup=jakeImportPath
syn match jakeImportPath "\"[^\"]*\"" contained nextgroup=jakeImportAs skipwhite
syn match jakeImportAs "\<as\>\s\+[a-zA-Z_][a-zA-Z0-9_]*" contained contains=jakeImportAsKeyword,jakeNamespace
syn keyword jakeImportAsKeyword as contained
syn match jakeNamespace "\<[a-zA-Z_][a-zA-Z0-9_]*\>" contained

" Top-level directives
syn match jakeGlobalDirective "^@\(dotenv\|require\|export\|default\)\>"
syn match jakeGlobalHook "^@\(pre\|post\|on_error\|before\|after\)\>"

" Recipe-level directives (indented)
" Conditionals get their own group for distinct highlighting
syn match jakeConditional "^\s\+@\(if\|elif\|else\|end\)\>"
" Loop directive
syn match jakeLoop "^\s\+@each\>"
" Other directives
syn match jakeDirective "^\s\+@\(needs\|require\|confirm\|cache\|watch\)\>"
syn match jakeDirective "^\s\+@\(cd\|shell\|group\|desc\|description\|alias\)\>"
syn match jakeDirective "^\s\+@\(quiet\|ignore\|only\|only-os\|platform\)\>"
syn match jakeDirective "^\s\+@\(export\|pre\|post\)\>"

" Variable definitions (top-level)
syn match jakeVarDef "^[a-zA-Z_][a-zA-Z0-9_]*\s*\(:=\|=\)" contains=jakeVarName,jakeOperator
syn match jakeVarName "^[a-zA-Z_][a-zA-Z0-9_]*" contained
syn match jakeOperator "\(:=\|=\)" contained

" Jake variable interpolation {{...}}
syn region jakeInterpolation start="{{" end="}}" contains=jakeFunction,jakeVarRef
syn match jakeVarRef "\<[a-zA-Z_][a-zA-Z0-9_]*\>" contained
syn match jakeFunction "\<\(dirname\|basename\|extension\|without_extension\|without_extensions\)\>" contained
syn match jakeFunction "\<\(absolute_path\|abs_path\|uppercase\|lowercase\|trim\)\>" contained
syn match jakeFunction "\<\(home\|local_bin\|shell_config\|env\|exists\|eq\|neq\)\>" contained
syn match jakeFunction "\<\(is_watching\|is_dry_run\|is_verbose\|is_platform\|is_macos\|is_linux\|is_windows\|is_unix\|item\)\>" contained

" Shell variables
syn match jakeShellVar "\$[a-zA-Z_][a-zA-Z0-9_]*"
syn match jakeShellVar "\${[a-zA-Z_][a-zA-Z0-9_]*}"
syn match jakePositional "\$[0-9@]"

" Strings
syn region jakeString start=+"+ end=+"+ skip=+\\"+ contains=jakeInterpolation,jakeShellVar,jakeEscape
syn region jakeString start=+'+ end=+'+ skip=+\\'+ contains=jakeEscape
syn match jakeEscape "\\[nrt\"'\\]" contained

" Condition functions (in @if)
syn match jakeCondFunc "\<\(env\|exists\|eq\|neq\|is_watching\|is_dry_run\|is_verbose\|is_platform\|is_macos\|is_linux\|is_windows\|is_unix\)\s*(" contains=jakeCondFuncName
syn match jakeCondFuncName "\<\(env\|exists\|eq\|neq\|is_watching\|is_dry_run\|is_verbose\|is_platform\|is_macos\|is_linux\|is_windows\|is_unix\)\>" contained

" Platform names
syn keyword jakePlatform linux macos windows darwin freebsd openbsd netbsd

" Special recipe prefix (private)
syn match jakePrivate "^_[a-zA-Z0-9_-]*:"

" Colon separator
syn match jakeColon ":"

" Highlighting links
" Comments (gray)
hi def link jakeComment Comment
hi def link jakeTodo Todo

" Keywords (purple/magenta)
hi def link jakeKeyword Keyword
hi def link jakeImport Include
hi def link jakeImportAsKeyword Keyword
hi def link jakeGlobalDirective PreProc
hi def link jakeGlobalHook PreProc
hi def link jakeConditional Conditional
hi def link jakeLoop Repeat
hi def link jakeDirective Statement

" Recipe/function names (blue)
hi def link jakeRecipeName Function
hi def link jakeRecipeNameDef Function
hi def link jakeSimpleRecipe Function
hi def link jakeDepName Function

" Parameters (orange - use Special to differentiate from variables)
hi def link jakeParam Special
hi def link jakeParamDefault String

" Variables (cyan)
hi def link jakeVarDef Identifier
hi def link jakeVarName Identifier
hi def link jakeVarRef Identifier
hi def link jakeShellVar Identifier
hi def link jakePositional Special

" Strings (green)
hi def link jakeString String
hi def link jakeEscape SpecialChar

" Built-in functions (yellow/gold - use Type for distinct color)
hi def link jakeFunction Type
hi def link jakeCondFunc Type
hi def link jakeCondFuncName Type

" Constants (red/pink)
hi def link jakePlatform Constant

" Namespaces (light blue)
hi def link jakeNamespace Type

" Operators
hi def link jakeOperator Operator

" Special elements
hi def link jakeDeps Special
hi def link jakeInterpolation Special
hi def link jakeImportPath String
hi def link jakePrivate Comment
hi def link jakeColon Delimiter

let b:current_syntax = "jake"
