# Introduction

Arabica is a vim plugin for Java that generates frequently written code.
- Generate import statement for the class under cursor.
- Generate package name from the file system path.
- Generate file name based on the package name.

The following key bindings show how to use the plugin.
Function and command names are self-explanatory.
```vim
nnoremap <leader><enter> "jyiw:JavaImport j<c-z>
nnoremap <silent> <leader>p :call JavaPackage()<cr>
nnoremap <silent> <leader>s :call JavaSortImports()<cr>
nnoremap <silent> <leader>r :call JavaRenameFile()<cr>
```

# License

GPL3+
