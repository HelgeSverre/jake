" Vim filetype plugin for Jake
" Language: Jake
" Maintainer: Jake contributors

if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1

" Comment settings
setlocal commentstring=#\ %s
setlocal comments=:#

" Indentation
setlocal expandtab
setlocal shiftwidth=4
setlocal softtabstop=4
setlocal tabstop=4

" Fold on recipe definitions
setlocal foldmethod=indent
setlocal foldlevel=99

" Make patterns
setlocal iskeyword+=-
setlocal iskeyword+=@-@

" Format options
setlocal formatoptions-=t
setlocal formatoptions+=croql

" Undo settings when switching filetype
let b:undo_ftplugin = "setlocal commentstring< comments< expandtab< shiftwidth< softtabstop< tabstop< foldmethod< foldlevel< iskeyword< formatoptions<"
