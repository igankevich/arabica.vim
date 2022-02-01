" Vim plugin for Java.
" Author: Ivan Gankevich <igankevich@ya.ru>

" Insert java package name calculated from the current file path.
function! g:JavaPackage()
    let package = expand('%')
    let filename = "\." . expand('%:t') . "$"
    let package = substitute(package, ".*src/main/java/", "", "")
    let package = substitute(package, ".*src/test/java/", "", "")
    let package = substitute(package, filename, "", "")
    let package = substitute(package, "/", ".", "g")
    let firstLine = getline(1)
    if firstLine =~# '^package'
        call setline(1, 'package ' . package . ';')
    else
        call append(firstLine, 'package ' . package . ';')
    endif
endfunction

function! JavaInsertImport(class)
    call append(s:LineNumberOfTheFirstImport(), 'import ' . a:class . ';')
    call g:JavaSortImports()
endfunction

function! JavaImportComplete(ArgLead, CmdLine, CursorPos)
    let className = a:ArgLead
    return s:QueryFast("SELECT name FROM classes WHERE name LIKE '%." . className . "'")
endfunction

function s:LineNumberOfTheFirstImport()
    let lineno = 1
    let num_lines = line('$')
    while lineno <= num_lines
        let line = getline(lineno)
        if line =~# '\v^\s*import\s+.*'
            return lineno
        endif
        let lineno = lineno + 1
    endwhile
    return 1
endfunction

" Sort each paragraph of the source file that contains
" package imports only.
function! g:JavaSortImports()
    let lineno = 1
    let num_lines = line('$')
    let first = 0
    let last = 0
    let paragraphs = []
    while lineno <= num_lines
        let line = getline(lineno)
        if line =~# '\v^\s*import\s+.*'
            if first == 0
                let first = lineno
                let last = lineno
            else
                if last == lineno-1
                    let last = lineno
                else
                    call add(paragraphs, {'first': first, 'last': last})
                    let first = lineno
                    let last = lineno
                endif
            endif
        endif
        let lineno = lineno + 1
    endwhile
    let oldView = winsaveview()
    if first != 0 && last != 0
        call add(paragraphs, {'first': first, 'last': last})
    endif
    "echo paragraphs
    for p in paragraphs
        execute ":silent " . p.first . "," . p.last . "sort u"
    endfor
    call winrestview(oldView)
endfunction

function! FindLinesMatchingPattern(pattern)
    let lineno = 1
    let num_lines = line('$')
    let result = []
    while lineno <= num_lines
        let line = getline(lineno)
        if line =~# a:pattern
            call add(result, {'lineno': lineno, 'line': matchlist(line, a:pattern)})
        endif
        let lineno = lineno + 1
    endwhile
    return result
endfunction

" rename current java file to match package and class name
function! JavaRenameFile() abort
    let className = FindLinesMatchingPattern('\vpublic\s+(class|enum|interface)\s+(\w+)')[0].line[2]
    let packageMatch = FindLinesMatchingPattern('\v\s*package\s+(.*)\s*;\s*')[0].line
    if empty(packageMatch)
        echo 'Can not find the package.'
        return
    endif
    let package = substitute(trim(packageMatch[1]), "\\.", "/", "g")
    let oldFilename = expand('%')
    let prefix = ''
    let middle = ''
    let match = matchlist(oldFilename, '\v(.*)(src/test/java|src/main/java)(.*)')
    if empty(match)
        if className =~# 'Test$'
            let middle = 'src/test/java'
        else
            let middle = 'src/main/java'
        endif
    else
        let prefix = match[1]
        let middle = match[2]
    endif
    let filename = prefix . middle . "/" . package . "/" . className . ".java"
    if oldFilename !=# filename
        if filereadable(filename)
            echo 'File exists: ' . filename
            return
        endif
        call mkdir(fnamemodify(filename, ':h'), 'p')
        execute "saveas " . filename
        call delete(oldFilename)
        redraw!
    else
        echo 'File names are identical.'
    endif
endfunction

" find full Java class name
function! JavaClassName()
    let className = 
        \ FindLinesMatchingPattern('\vpublic\s+class\s+(\w+)')[0].line[1]
    let firstLine = getline(1)
    if firstLine !~# '^package'
        echo 'Can not find package'
    else
        let package = substitute(firstLine, "package\\s*", "", "")
        let package = substitute(package, "\\s*;\\s*", "", "")
        let className = package . '.' . className
    endif
    return className
endfunction

function! JavaSerialVer()
    let className = JavaClassName()
    let classPath = system('mvn dependency:build-classpath -Dmdep.outputFile=/dev/stdout')
    let line = system('serialver -classpath target/classes:' . classPath . ' ' . className)
    let code = split(line, ':\s*')[1]
    call append(getline('.'), code)
endfunction

let s:javaHome = ''
let s:schema = 'CREATE TABLE jars (
            \   id INTEGER NOT NULL PRIMARY KEY,
            \   path TEXT NOT NULL UNIQUE,
            \   hash TEXT NOT NULL);
            \ CREATE TABLE classes (
            \   name TEXT NOT NULL,
            \   jar_id INTEGER NOT NULL,
            \  FOREIGN KEY (jar_id) REFERENCES jars(id) ON DELETE CASCADE ON UPDATE CASCADE);
            \ CREATE INDEX classes_name_index ON classes(name);'
let s:classes = '.git/classes.sqlite3'

function! JavaHome()
    if !empty(s:javaHome)
        return s:javaHome
    endif
    let s:javaHome = $JAVA_HOME
    let javaPath = ''
    if !empty(s:javaHome)
        let javaPath = s:javaHome . '/bin/java'
    else
        let javaPath = system('which java')
    endif
    let realPath = system('realpath ' . javaPath)
    let s:javaHome = fnamemodify(realPath, ':h:h')
    return s:javaHome
endfunction

function! s:Query(sql)
    let path = s:classes
    if !filereadable(path)
        call mkdir(fnamemodify(path, ':h'), 'p')
        call system('sqlite3 ' . path, s:schema)
    endif
    return systemlist('sqlite3 '. path, ".mode list\nPRAGMA foreign_keys = ON;\n" . a:sql)
endfunction

function! s:QueryFast(sql)
    return systemlist("sqlite3 " . s:classes . " " . shellescape(a:sql))
endfunction

function! s:ProjectDependenciesJARs()
    let tmpfile = getcwd() . '/.git/maven.tmp'
    call mkdir(fnamemodify(tmpfile, ':h'), 'p')
    call system('mvn dependency:build-classpath -Dmdep.outputFile=' . shellescape(tmpfile))
    let classPath = readfile(tmpfile)[0]
    return uniq(sort(split(classPath, ':')))
endfunction

function! s:ProjectJARs()
    return systemlist('find ' . shellescape(getcwd()) . ' -type f -name "*.jar"')
endfunction

function! s:SystemJARs()
    return [JavaHome() . '/jre/lib/rt.jar']
endfunction

function! s:NotIndexedJARs(all_jars)
    let sql = join(map(a:all_jars, {key, value -> "('" . value . "')"}), ",\n")
    let sql = "SELECT * FROM (VALUES\n" . sql . ")\nEXCEPT SELECT path FROM jars"
    return s:Query(sql)
endfunction

function! s:PathToClassName(filename)
    return tr(fnamemodify(a:filename, ':r'), '/', '.')
endfunction

function! s:SHA256(filename)
    return split(system('sha256sum ' . shellescape(a:filename)))[0]
endfunction

function! s:DeleteNonExistingJARs()
    let jars = map(s:Query("SELECT id,path,hash FROM jars"), {key, value -> split(value,'|')})
    let ids = []
    for jar in jars
        if !filereadable(jar[1])
            call add(ids, jar[0])
            echo 'remove from index ' . jar[1]
            continue
        endif
        let actualHash = s:SHA256(jar[1])
        if actualHash !=# jar[2]
            call add(ids, jar[0])
            continue
        endif
    endfor
    call s:Query("DELETE FROM jars WHERE id IN (" . join(ids,',') . ")")
    return ids
endfunction

function! JavaIndexClasses()
    let deletedJars = s:DeleteNonExistingJARs()
    let jars = s:NotIndexedJARs(s:ProjectJARs() + s:ProjectDependenciesJARs() + s:SystemJARs())
    let n = 1
    for jar in jars
        let hash = s:SHA256(jar)
        call s:Query("INSERT INTO jars (path,hash) VALUES ('" . jar . "', '" . hash . "')")
        let jarId = s:Query("SELECT id FROM jars WHERE path='" . jar . "'")[0]
        let sql = ''
        let files = systemlist('jar -tf ' . shellescape(jar))
        let lines = []
        for file in files
            if file =~# '\.class$'
                let className = s:PathToClassName(file)
                let lines = add(lines, className . '|' . jarId)
            endif
        endfor
        let tmpfile = '.git/classes.tmp'
        call writefile(lines, tmpfile)
        let ret = s:Query('.import ' . tmpfile . ' classes')
        echo '[' . n . '/' . len(jars) . '] index ' . jar . (empty(ret) ? '' : (': ' . ret))
        let n = n + 1
    endfor
    if len(jars) == 0 && len(deletedJars) == 0
        echo 'Index is up to date.'
    endif
endfunction

command! -nargs=1 -complete=customlist,JavaImportComplete JavaImport
    \ call JavaInsertImport('<args>')

command! JavaIndexClasses call JavaIndexClasses()
command! JavaPackage call JavaPackage()
command! JavaRenameFile call JavaRenameFile()
