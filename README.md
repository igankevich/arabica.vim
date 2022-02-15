# Introduction

Arabica is a vim plugin for Java that generates frequently written code.
- Generate import statement for the class under cursor.
- Generate package name from the file system path.
- Generate file system path based on the package name and the class name.

The following key bindings show how to use the plugin.
Command names are self-explanatory.
```vim
nnoremap <leader><enter> "jyiw:JavaImport j<c-z>
" you can type ^R symbol in Vim as <C-v><C-r>
nnoremap <silent> <leader>r :JavaRenameClass<cr>
nnoremap <silent> <leader>R :JavaRenameFile<cr>
nnoremap <silent> <leader>s :JavaSerialVersion<cr>
```

# License

GPL3+
