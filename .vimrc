"for light, fast, effective navigation
"------------------------------------------------------------
"install
"curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
"
"then
":PlugInstall
":PlugUpdate
":PlugClean

call plug#begin('~/.vim/plugged')
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'w0ng/vim-hybrid'
Plug 'dracula/vim'
Plug 'vv9k/vim-github-dark'
Plug 'brafales/vim-desert256'
Plug 'frazrepo/vim-rainbow'
Plug 'valloric/youcompleteme', { 'do': 'python3 ./install.py --clang-completer --verbose'}
Plug 'SirVer/ultisnips'
Plug 'al-hub/vim-snippets'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'wfxr/minimap.vim'
"Plug 'puremourning/vimspector' #not ready yet
Plug 'scrooloose/nerdtree'
Plug 'majutsushi/tagbar'
Plug 'vim-scripts/taglist.vim'
Plug 'wesleyche/srcexpl'
Plug 'al-hub/vim-mark'
Plug 'inkarkat/vim-ingo-library'
Plug 'vim-scripts/Marks-Browser'
Plug 'vim-syntastic/syntastic'
Plug 'ctrlpvim/ctrlp.vim'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'valloric/python-indent'
Plug 'christoomey/vim-tmux-navigator'
Plug 'mileszs/ack.vim'
Plug 'yegappan/grep'
Plug 'vimwiki/vimwiki'
Plug 'vim-scripts/ZoomWin'
Plug 'tpope/vim-fugitive'
Plug 'mtdl9/vim-log-highlighting'
call plug#end()
"------------------------------------------------------------


"basic setting
"------------------------------------------------------------
set nu
set mouse=a
set hlsearch
set splitright
set splitbelow
scriptencoding utf-8
set encoding=utf-8
"set tabstop=8
set softtabstop=4
"set shiftwidth=4
"set textwidth=100
"set expandtab
"set smartindent cinwords=if,elif,else,for,while,try,except,finally,def,class
"set nocindent

"for speedup https://vi.stackexchange.com/questions/10495/most-annoying-slow-down-of-a-plain-text-editor
set regexpengine=1
set lazyredraw
set ttyfast
"syntax off
"------------------------------------------------------------


"basic keymap
"------------------------------------------------------------
let mapleader      = ' '

nnoremap <C-s> :w <CR>
inoremap <C-s> <Esc> :w <CR>
inoremap <C-w> <Esc><C-w>
nnoremap Q :qa <CR>
"xnoremap <C-s> <Esc> :w <CR>
"https://devhints.io/vimscript "https://vi.stackexchange.com/questions/5484/get-the-current-window-buffer-tabpage-in-vimscript
func! s:my_close()
    let current_win = winnr()
    "https://superuser.com/questions/345520/vim-number-of-total-buffers
    "let current_buff = bufnr("%")
    let current_buff = len(filter(range(1, bufnr('$')), 'buflisted(v:val)'))
    let current_tabpage = tabpagenr()

    if ( current_win != 1 )
	    :close
    elseif ( current_buff != 1 )
	    :bd
    elseif ( current_tabpage != 1 )
	    :td
    else
	    :q
    endif
endfunc
nmap <C-w>q :call <SID>my_close() <CR>
nmap <C-w>d :qa <CR>
"nmap <C-w>z :resize 4096 <CR> :vertical-resize 4096 <CR>
nmap <C-w>z :call <sid>zoom()<cr>
nmap <C-w>\| :vsplit <CR>
nmap <C-w>% :vsplit <CR>
nmap <C-w>_ :split <CR>
nmap <C-w>" :split <CR>
nnoremap <C-w>t  :bNext<CR>
nnoremap <S-tab>  :bNext<CR>

"weird but <S-F8> is Shift-F10 for build
"autocmd FileType python nmap <S-F8> :w !python<CR>
"autocmd FileType sh     nmap <S-F8> :w !/bin/bash<CR>
"autocmd FileType c      nmap <S-F8> :w <CR> :!gcc % && ./a.out<CR>
"autocmd FileType cpp    nmap <S-F8> :w <CR> :!g++ % <CR> :!./a.out<CR>
"autocmd FileType java    nmap <S-F8> :w <CR> :!javac % && java %:r<CR>

"for v8.0 https://vi.stackexchange.com/questions/14519/how-to-run-internal-vim-terminal-at-current-files-dir
"https://vi.stackexchange.com/questions/20577/send-cr-to-ipython-in-term
autocmd FileType python nmap <S-F8> :w<CR>:let $vim_file=expand('%:p')<CR>:term<CR><C-l>python $vim_file<CR>exit
autocmd FileType sh     nmap <S-F8> :w<CR>:let $vim_file=expand('%:p')<CR>:term<CR><C-l>sh $vim_file<CR>exit
autocmd FileType c      nmap <S-F8> :w<CR>:let $vim_file=expand('%:p')<CR>:term<CR><C-l>gcc $vim_file && ./a.out<CR>exit
autocmd FileType cpp    nmap <S-F8> :w<CR>:let $vim_file=expand('%:p')<CR>:term<CR><C-l>g++ $vim_file && ./a.out<CR>exit
autocmd FileType java   nmap <S-F8> :w<CR>:let $vim_file=expand('%:p')<CR>:let $vim_jname=expand('%:r')<CR> :terminal<CR><C-l> javac $vim_file && java $vim_jname<CR>exit

noremap <F2> :NERDTreeToggle<CR><C-w><C-w>
noremap <F3> :Tagbar<CR>

""nnoremap <F4> :vimgrep <C-R><C-W> **/*.c **/*.h <Bar> cw <CR><C-W><C-J>
"map <f4> :s#/\* \(.*\) \*/#\1<CR>:nohlsearch<CR>
"nnoremap <F3> :Ack % <space>
"nnoremap <F2> :Rgrep <CR>

""nmap <F5> :TlistToggle<CR>
"nmap <F7> :NERDTreeToggle<CR>
""nmap <F8> :SrcExplToggle<CR>
""nmap <F9> <F5><CR> <F7><CR> <F8><CR>
"nnoremap <C-w>z :ZoomWin <CR>

"https://vim.fandom.com/wiki/Scroll_using_arrow_keys_like_in_a_web_browser
"J is dd delete, K is  help keyword
"map <S-J> <C-E>
"map <S-K> <C-Y>
"------------------------------------------------------------


"scheme
"------------------------------------------------------------
set cursorline
"set cursorcolumn

"set list
"set list lcs=tab:\│\
"nmap <leader>l :set list!<CR>
"hi NoneText cterm=None ctermfg=darkgrey
"hi SpecialKey cterm=None ctermfg=darkgrey

"https://www.slant.co/topics/480/~best-vim-color-schemes etc: ghdark dracula desert256
set background=dark
colorscheme hybrid

"https://github.com/vim-airline/vim-airline/issues/421
"let g:airline_extensions = ['branch','ctrlp','fugitiveline','fzf','keymap','netrw','po','quickfix','searchcount','syntastic','tabline','tagbar','taglist','term','whitespace','wordcount']
let g:airline_theme='hybrid'
let g:airline#extensions#tabline#enabled = 1              " vim-airline
let g:airline#extensions#tabline#fnamemod = ':t'          " vim-airline
let g:airline#extensions#tabline#buffer_nr_show = 1       " buffer number? ????
let g:airline#extensions#tabline#buffer_nr_format = '%s:' " buffer number format

"for speedup
"let g:airline_extensions = []
let g:airline#extensions#searchcount#enabled = 0
let g:airline#extensions#tagbar#enabled = 0

let g:rainbow_active = 1

set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

"https://github.com/nathanaelkane/vim-indent-guides
"filetype plugin indent on
let g:indent_guides_auto_colors = 0
let g:indent_guides_enable_on_vim_startup = 1
"let g:indent_guides_start_level = 0 '0' is error
let g:indent_guides_guide_size = 4
set ts=4 sw=4 et
"hi IndentGuidesOdd  ctermbg=green
"hi IndentGuidesEven guibg=red ctermbg=4
hi IndentGuidesOdd ctermbg=234
hi IndentGuidesEven ctermbg=0
"------------------------------------------------------------


"ycm & syntastic
"------------------------------------------------------------
" https://johngrib.github.io/wiki/vim-ycm-python3/
"let g:loaded_youcompleteme = 1
"let g:enable_ycm_at_startup = 1
let g:ycm_server_python_interpreter = '/usr/bin/python3'
let g:ycm_global_ycm_extra_conf = '~/.vim/plugged/youcompleteme/third_party/ycmd/.ycm_extra_conf.py'

let g:ycm_key_list_select_completion = ['<C-n>']
let g:ycm_key_list_previous_completion=['<C-p>']

"let g:ycm_filetype_specific_completion_to_disable = { 'cpp': 1 }
"set completeopt-=preview

"for speedup
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 0
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 0

let g:ycm_show_diagnostics_ui = 0

"sh: sudo apt-get install shellcheck
let g:syntastic_cpp_compiler = 'g++'
let g:syntastic_cpp_compiler_options = "-ansi -std=c++11 -Wall -Wextra -Wpedantic"
let g:syntastic_c_compiler_options = "-ansi -std=c11 -Wall -Wextra -Wpedantic"
"could not find java syntatic method
"let g:syntastic_java_checkers=['javac']
"let g:syntastic_java_javac_config_file_enabled = 1

"set listchars=eol:$,tab:>-,trail:·,extends:>,precedes:<
"https://stackoverflow.com/questions/11269066/toggling-a-match-in-vimrc
let s:hilightws = 1
hi ExtraWhitespace ctermbg=52 ctermfg=darkred
match ExtraWhitespace /\s\+$/

function ToggleWhitespaceMatching()
  if s:hilightws
    match ExtraWhitespace //
  else
    match ExtraWhitespace /\s\+$/
  endif
  let s:hilightws = !s:hilightws
endfunction

nnoremap s <esc>
nnoremap <leader>w :call ToggleWhitespaceMatching()<CR>
nnoremap <leader>s :SyntasticCheck<CR>:lwindow<CR>
nnoremap <leader>S :lclose<CR> ToggleWhitespaceMatching()<CR>

abbr wq1 wq!
abbr wqa1 wqa!
abbr q1 q!

"usefull when I use snips
let g:UltiSnipsJumpForwardTrigger="<Tab>"
"------------------------------------------------------------


"fzf
"------------------------------------------------------------
" https://github.com/junegunn/fzf.vim
function! RipgrepFzf(query, fullscreen)
  let command_fmt = 'rg --column --line-number --no-heading --color=always --smart-case -- %s|| true'
  let initial_command = printf(command_fmt, shellescape(a:query))
  let reload_command = printf(command_fmt, '{q}')
  let spec = {'options': ['--bind', 'page-up:preview-up,page-down:preview-down', '--phony', '--query', a:query, '--bind', 'change:reload:'.reload_command]}
  call fzf#vim#grep(initial_command, 1, fzf#vim#with_preview(spec), a:fullscreen)
endfunction

command! -nargs=* -bang RG call RipgrepFzf(<q-args>, <bang>0)

"https://github.com/junegunn/dotfiles/blob/master/vimrc
"https://soooprmx.com/archives/6808
"https://stackoverflow.com/questions/9051837/how-to-map-c-to-toggle-comments-in-vim
nnoremap <C-_> :RG <C-R><C-W>
nnoremap <silent> <Leader><Leader> :RG <C-R><C-W><CR>
nnoremap <silent> <expr> <Leader>f (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":Files\<cr>"
nnoremap <silent> <Leader>C        :Colors<CR>
nnoremap <silent> <Leader><Enter>  :Buffers<CR>
nnoremap <silent> <Leader>L        :Lines<CR>
nnoremap <silent> <Leader>rg       :Rg <C-R><C-W><CR>
nnoremap <silent> <Leader>`        :Marks<CR>

"https://github.com/junegunn/fzf.vim
let g:fzf_preview_window = ['right:50%', 'ctrl-/']

let g:fzf_buffers_jump = 1
let g:fzf_tags_command = 'ctags -R'
let g:fzf_commands_expect = 'alt-enter,ctrl-x'
"------------------------------------------------------------


"tmux
"------------------------------------------------------------
"https://gist.github.com/junegunn/2f271e4cab544e86a37e239f4be98e74
"------------------------------------------------------------


"Plug 'puremourning/vimspector' #not ready yet
"------------------------------------------------------------
"let g:vimspector_enable_mappings = 'HUMAN'
"nmap <leader>dd :call vimspector#Launch()<CR>
"nmap <leader>dx :VimspectorReset<CR>
"nmap <Leader>di <Plug>VimspectorBalloonEval
"nmap <leader>de :VimspectorEval
"nmap <leader>dw :VimspectorWatch
"nmap <leader>do :VimspectorShowOutput
"nmap <leader>dc :!cc -g -I./libft/libft.h -L./libft/ -lft % -o main<CR>
""nmap <leader>dp <Plug>VimSpectorRunToCursor
"
"autocmd FileType cpp nmap <C-F5> :w <CR> :!g++ -g % -o
"autocmd FileType cpp nmap <C-F10> <Plug>VimspectorRunToCursor
"autocmd FileType cpp nmap <S-F5> <Plug>VimspectorReset
"------------------------------------------------------------


"current function name return
"------------------------------------------------------------
fun! ShowFuncName()
    let lnum = line(".")
    let col = col(".")
    echohl ModeMsg
    echo getline(search("^[^ \t#/]\\{2}.*[^:]\s*$", 'bW'))
    echohl None
    call search("\\%" . lnum . "l" . "\\%" . col . "c")
endfun
"map f :call ShowFuncName() <CR>
"------------------------------------------------------------


"hlsearch with minimap
"------------------------------------------------------------
let g:minimap_width = 10
let g:minimap_auto_start = 0
let g:minimap_auto_start_win_enter = 0
let g:minimap_highlight_search=0

nnoremap <silent> <Leader>mm :MinimapToggle<CR>
"nnoremap <silent> <Leader>* *``:Minimap<CR>:call minimap#vim#UpdateColorSearch(1)<CR>
nnoremap <silent> * *``:Minimap<CR>:call minimap#vim#UpdateColorSearch(1)<CR>
"https://vi.stackexchange.com/questions/2614/why-does-this-esc-normal-mode-mapping-affect-startup
"nnoremap <silent> <esc> :noh<CR>:MinimapClose<CR><esc>
nnoremap <silent> ** :noh<CR>:MinimapClose<CR><esc>
"------------------------------------------------------------


"Advanced keymap
"------------------------------------------------------------
"https://vi.stackexchange.com/questions/8451/is-it-possible-to-have-vim-show-the-list-of-available-marks-when-using-marks
"nnoremap ' :Marks<CR>

" jk | Escaping!
inoremap jk <Esc>
"xnoremap jk <Esc>
"cnoremap jk <C-c>

" qq to record, Q to replay
"nnoremap Q @q

" Zoom
function! s:zoom()
  if winnr('$') > 1
    tab split
  elseif len(filter(map(range(tabpagenr('$')), 'tabpagebuflist(v:val + 1)'),
                  \ 'index(v:val, '.bufnr('').') >= 0')) > 1
    tabclose
  endif
endfunction
nnoremap <silent> <leader>z :call <sid>zoom()<cr>

" Last inserted text
" nnoremap g. :normal! `[v`]<cr><left>

"urxvt 에서 정상동작되지 않는 이슈
"https://rampart81.github.io/post/vim-clipboard-share/
"set clipboard=unnamedplus
"https://vi.stackexchange.com/questions/84/how-can-i-copy-text-to-the-system-clipboard-from-vim
"noremap <Leader>y "+y
"noremap <Leader>p "+p
"
"workaroud
"https://doocong.com/tools/vim-xclip/
"vmap <C-c> y:call system("xclip -i -selection clipboard", getreg("\""))<CR>
vmap y y:call system("xclip -i -selection clipboard", getreg("\""))<CR>
noremap yy yy:call system("xclip -i -selection clipboard", getreg("\""))<CR>

"debug https://unix.stackexchange.com/questions/212360/copying-pasting-with-urxvt
"relate for urxtve https://github.com/muennich/urxvt-perls
"------------------------------------------------------------
