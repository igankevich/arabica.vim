" Vim plugin for Java.
" Author: Ivan Gankevich <igankevich@ya.ru>

" script guard
if exists("arabica_loaded")
    finish
endif
let arabica_loaded = 1

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
    let channel = s:GetChannel()
    call ch_sendraw(channel, 'select ' . className . "\n")
    return split(ch_read(channel))
endfunction

function! s:GetChannel()
    call JavaCompileArabica()
    if !s:jobStarted
        let s:job = job_start('java -cp ' . s:classPath . ' Arabica')
        let s:jobStarted = 1
    endif
    return job_getchannel(s:job)
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
let s:classPath = expand("<sfile>:h")
let s:jobStarted = 0

function! JavaCompileArabica()
    if filereadable(s:classPath . '/Arabica.class')
        return
    endif
    let output = system('javac ' . s:classPath . '/Arabica.java')
    if v:shell_error
        echo output
        return
    endif
endfunction

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
    let realPath = resolve(javaPath)
    let s:javaHome = fnamemodify(realPath, ':h:h')
    return s:javaHome
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

function! JavaIndexClasses()
    let jars = uniq(sort(s:ProjectDependenciesJARs() + s:SystemJARs()))
    let channel = s:GetChannel()
    call ch_sendraw(channel, 'index ' . join(jars, ' ') . "\n")
    let nlines = str2nr(ch_read(channel))
    for i in range(nlines)
        echo ch_read(channel)
    endfor
endfunction

command! -nargs=1 -complete=customlist,JavaImportComplete JavaImport
            \ call JavaInsertImport('<args>')

command! JavaIndexClasses call JavaIndexClasses()
command! JavaPackage call JavaPackage()
command! JavaRenameFile call JavaRenameFile()
