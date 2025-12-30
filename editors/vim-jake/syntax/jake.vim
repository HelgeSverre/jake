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
syn match jakeDirective "^\s\+@\(if\|elif\|else\|end\)\>"
syn match jakeDirective "^\s\+@\(each\|needs\|require\|confirm\|cache\|watch\)\>"
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
syn match jakeFunction "\<\(is_watching\|command\|item\)\>" contained

" Shell variables
syn match jakeShellVar "\$[a-zA-Z_][a-zA-Z0-9_]*"
syn match jakeShellVar "\${[a-zA-Z_][a-zA-Z0-9_]*}"
syn match jakePositional "\$[0-9@]"

" Strings
syn region jakeString start=+"+ end=+"+ skip=+\\"+ contains=jakeInterpolation,jakeShellVar,jakeEscape
syn region jakeString start=+'+ end=+'+ skip=+\\'+ contains=jakeEscape
syn match jakeEscape "\\[nrt\"'\\]" contained

" Condition functions (in @if)
syn match jakeCondFunc "\<\(env\|exists\|eq\|neq\|is_watching\|command\)\s*(" contains=jakeCondFuncName
syn match jakeCondFuncName "\<\(env\|exists\|eq\|neq\|is_watching\|command\)\>" contained

" Platform names
syn keyword jakePlatform linux macos windows darwin freebsd openbsd netbsd

" Special recipe prefix (private)
syn match jakePrivate "^_[a-zA-Z0-9_-]*:"

" Colon separator
syn match jakeColon ":"

" Highlighting links
hi def link jakeComment Comment
hi def link jakeTodo Todo
hi def link jakeKeyword Keyword
hi def link jakeRecipeName Function
hi def link jakeRecipeNameDef Function
hi def link jakeSimpleRecipe Function
hi def link jakeParam Identifier
hi def link jakeParamDefault String
hi def link jakeDeps Special
hi def link jakeDepName Function
hi def link jakeImport Include
hi def link jakeImportPath String
hi def link jakeImportAsKeyword Keyword
hi def link jakeNamespace Type
hi def link jakeGlobalDirective PreProc
hi def link jakeGlobalHook PreProc
hi def link jakeDirective Statement
hi def link jakeVarDef Identifier
hi def link jakeVarName Identifier
hi def link jakeOperator Operator
hi def link jakeInterpolation Special
hi def link jakeVarRef Identifier
hi def link jakeFunction Function
hi def link jakeShellVar Identifier
hi def link jakePositional Special
hi def link jakeString String
hi def link jakeEscape SpecialChar
hi def link jakeCondFunc Function
hi def link jakeCondFuncName Function
hi def link jakePlatform Constant
hi def link jakePrivate Comment
hi def link jakeColon Delimiter

let b:current_syntax = "jake"
