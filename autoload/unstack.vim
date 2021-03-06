"Initialization: {{{
if !exists("s:unstack_signs")
  let s:unstack_signs = {}
endif
"When the user switches tabs, check if it's due to an unstack tab being closed.
"If so, remove signs from the stack trace that was in that tab.
augroup unstack_sign_clear
  autocmd!
  autocmd TabEnter * call unstack#RemoveSignsFromClosedTabs()
augroup end 
"}}}
"unstack#Unstack(selection_type) called by hotkeys {{{
function! unstack#Unstack(selection_type)
  let stack = unstack#ExtractFiles(a:selection_type)
  call unstack#OpenStackTrace(stack)
endfunction
"}}}
"Extraction:
"unstack#ExtractFiles(selection_type) extract files and line numbers {{{
function! unstack#ExtractFiles(selection_type)
  if &buftype == "quickfix"
    let fileList = unstack#ExtractFilesFromQuickfix(a:selection_type)
  else
    let text = unstack#GetSelectedText(a:selection_type)
    let fileList = unstack#ExtractFilesFromText(text)
  endif
  return fileList
endfunction
"}}}
"unstack#ExtractFilesFromQuickfix(type) extract files from selected text or normal cmd range {{{
function! unstack#ExtractFilesFromQuickfix(type)
  if a:type ==# "v" || a:type ==# "V"
    let marks = ["'<", "'>"]
  else
    let marks = ["'[", "']"]
  endif
  let start_line = line(marks[0]) - 1 "lines are 0-indexed in quickfix list
  let stop_line = line(marks[1]) - 1 "lines are 0-indexed in quickfix list
  let file_list = []
  while start_line <= stop_line
    let qfline = getqflist()[start_line]
    let fname = bufname(qfline["bufnr"])
    let lineno = qfline["lnum"]
    call add(file_list, [fname, lineno])
    let start_line = start_line + 1
  endwhile
  return file_list
endfunction
"}}}
"unstack#GetSelectedText(selection_type) extract selected text {{{
function! unstack#GetSelectedText(selection_type)
  "save these values because we have to change them
  let sel_save = &selection
  let reg_save = @@
  let &selection = "inclusive"

  "yank the text
  if a:selection_type ==# 'V'
    execute "normal! `<V`>y"
  elseif a:selection_type ==# 'v'
    execute "normal! `<v`>y"
  elseif a:selection_type ==# 'char'
    execute "normal! `[v`]y"
  elseif a:selection_type ==# 'line'
    execute "normal! `[V`]y"
  else
    "unknown selection type; reset vars and return ""
    let &selection = sel_save
    let @@ = reg_save
    return ""
  endif
  "get the text we just yanked
  let selected_text = @@
  "reset vars
  let &selection = sel_save
  let @@ = reg_save
  "return the text
  return selected_text
endfunction
"}}}
"unstack#ExtractFilesFromText(stacktrace) extract files and lines from a stacktrace {{{
"return [[file1, line1], [file2, line2] ... ] from a stacktrace 
"tries each extractor in order and stops when an extractor returns a non-empty
"stack
function! unstack#ExtractFilesFromText(text)
  for extractor in g:unstack_extractors
    let stack = extractor.extract(a:text)
    if(!empty(stack))
      return stack
    endif
  endfor
endfunction
"}}}
"Opening:
"unstack#OpenStackTrace(files) open extracted files in new tab {{{
"files: [[file1, line1], [file2, line2] ... ] from a stacktrace
function! unstack#OpenStackTrace(files)
  "disable redraw when opening files
  "still redraws when a split occurs but might *slightly* improve performance
  let lazyredrawSet = &lazyredraw
  set lazyredraw
  tabnew
  if (g:unstack_showsigns)
    sign define errline text=>> linehl=Error texthl=Error
    "sign ID's should be unique. If you open a stack trace with 5 levels,
    "you'd have to wait 5 seconds before opening another or risk signs
    "colliding.
    let signId = localtime()
    let t:unstack_tabId = signId
    let s:unstack_signs[t:unstack_tabId] = []
  endif
  for [filepath, lineno] in a:files
    execute "edit" filepath
    "move line with error to top then show 5 lines of context above
    setl scrolloff=5
    execute "normal!" lineno."z+"
    if (g:unstack_showsigns)
      execute "sign place" signId "line=".lineno "name=errline" "buffer=".bufnr('%')
      "store the signs so they can be removed later
      call add(s:unstack_signs[t:unstack_tabId], signId)
      let signId += 1
    endif
    "make a new vertical split for the next file
    botright vnew
  endfor
  "after adding the last file, the loop above calls vnew again.
  "delete this last empty vertical split
  quit
  if (!lazyredrawSet)
    set nolazyredraw
  endif
endfunction
"}}}
"unstack#GetOpenTabIds() get unstack id's for current tabs {{{
function! unstack#GetOpenTabIds()
  let curTab = tabpagenr()
  "determine currently open tabs
  let open_tab_ids = []
  tabdo if exists('t:unstack_tabId') | call add(open_tab_ids, string(t:unstack_tabId)) | endif
  "jump back to prev. tab
  execute "tabnext" curTab 
  return open_tab_ids
endfunction
"}}}
"unstack#RemoveSigns(tabId) remove signs from the files initially opened in a tab {{{
function! unstack#RemoveSigns(tabId)
  for sign_id in s:unstack_signs[a:tabId]
    execute "sign unplace" sign_id
  endfor
  unlet s:unstack_signs[a:tabId]
endfunction
"}}}
"unstack#RemoveSignsFromClosedTabs() remove signs that were placed in tabs that are {{{
"now closed
function! unstack#RemoveSignsFromClosedTabs()
  let openTabIds = unstack#GetOpenTabIds()
  "for each tab with signs
  for tabId in keys(s:unstack_signs)
    "if this tab no longer exists, remove the signs
    if index(openTabIds, tabId) == -1
      call unstack#RemoveSigns(tabId)
    endif
  endfor
endfunction
"}}}
" vim: et sw=2 sts=2 foldmethod=marker foldmarker={{{,}}}
