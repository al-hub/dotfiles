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
Plug 'blueyed/vim-diminactive'
Plug 'w0ng/vim-hybrid'
Plug 'dracula/vim'
Plug 'vv9k/vim-github-dark'
Plug 'brafales/vim-desert256'
Plug 'frazrepo/vim-rainbow'
Plug 'valloric/youcompleteme'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
"Plug 'puremourning/vimspector' #not ready yet
Plug 'scrooloose/nerdtree'
Plug 'majutsushi/tagbar'
Plug 'vim-scripts/taglist.vim'
Plug 'wesleyche/srcexpl'
Plug 'vim-scripts/Mark'
Plug 'vim-scripts/Marks-Browser'
Plug 'scrooloose/syntastic'
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
"------------------------------------------------------------


"basic keymap
"------------------------------------------------------------
let mapleader      = ' '

nmap <C-s> :w <CR>
"https://devhints.io/vimscript "https://vi.stackexchange.com/questions/5484/get-the-current-window-buffer-tabpage-in-vimscript
func! s:my_close()
    let current_win = winnr()
    let current_buff = bufnr("%")
    let current_tabpage = tabpagenr()
    "echo current_buff current_win current_tabpage

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
nmap <C-w>z :resize 4096 <CR> :vertical-resize 4096 <CR>
nmap <C-w>\| :vsplit <CR>
nmap <C-w>% :vsplit <CR>
nmap <C-w>_ :split <CR>
nmap <C-w>" :split <CR>

"weird but <S-F8> is Shift-F10 for build
autocmd FileType python nmap <S-F8> :w !python<CR>
autocmd FileType sh     nmap <S-F8> :w !/bin/bash<CR>
autocmd FileType c      nmap <S-F8> :w <CR> :!gcc % && ./a.out<CR>
autocmd FileType cpp    nmap <S-F8> :w <CR> :!g++ % <CR> :!./a.out<CR>
"autocmd FileType cpp    nmap <S-F8> :w <CR> :!g++ % <CR> :term ./a.out<CR>

noremap <F2> :NERDTreeToggle<CR> :vertical resize 45<CR>
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

"filetype plugin indent on
let g:indent_guides_auto_colors = 0
let g:indent_guides_enable_on_vim_startup = 1
"let g:indent_guides_start_level = 2
"let g:indent_guides_guide_size = 1
"set ts=4 sw=4 noet
"hi IndentGuidesOdd  ctermbg=darkgrey
"hi IndentGuidesEven ctermbg=black
hi IndentGuidesEven ctermbg=0
hi IndentGuidesOdd ctermbg=237
"hi IndentGuidesOdd  guibg=red   ctermbg=3
"hi IndentGuidesEven guibg=green ctermbg=4

"set list
"set list lcs=tab:\│\
"nmap <leader>l :set list!<CR>
"hi NoneText cterm=None ctermfg=darkgrey
"hi SpecialKey cterm=None ctermfg=darkgrey

"https://www.slant.co/topics/480/~best-vim-color-schemes etc: ghdark dracula desert256
colorscheme hybrid
"filetype plugin indent on 

"https://github.com/vim-airline/vim-airline/issues/421
"let g:airline_extensions = []
let g:airline_theme='hybrid'
let g:airline#extensions#tabline#enabled = 1              " vim-airline ?? ?? ??
let g:airline#extensions#tabline#fnamemod = ':t'          " vim-airline ?? ?? ???? ??
let g:airline#extensions#tabline#buffer_nr_show = 1       " buffer number? ????
let g:airline#extensions#tabline#buffer_nr_format = '%s:' " buffer number format

let g:rainbow_active = 1

set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*
"------------------------------------------------------------


"ycm & syntastic
"------------------------------------------------------------
" https://johngrib.github.io/wiki/vim-ycm-python3/
"let g:loaded_youcompleteme = 1
"let g:enable_ycm_at_startup = 1
let g:ycm_server_python_interpreter = '/usr/bin/python'
"let g:ycm_global_ycm_extra_conf = '/home-mc/core.choi/.vim/plugged/youcompleteme/third_party/ycmd/.ycm_extra_conf.py'

"let g:ycm_filetype_specific_completion_to_disable = { 'cpp': 1 }
"set completeopt-=preview
"
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 0

let g:syntastic_cpp_compiler = 'g++'
let g:syntastic_cpp_compiler_options = "-std=c++11 -Wall -Wextra -Wpedantic"
let g:syntastic_c_compiler_options = "-std=c11 -Wall -Wextra -Wpedantic"
"------------------------------------------------------------


"fzf
"------------------------------------------------------------
"https://github.com/junegunn/dotfiles/blob/master/vimrc
"https://soooprmx.com/archives/6808
nnoremap <silent> <expr> <Leader><Leader> (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":Files\<cr>"
nnoremap <silent> <Leader>C        :Colors<CR>
nnoremap <silent> <Leader><Enter>  :Buffers<CR>
nnoremap <silent> <Leader>L        :Lines<CR>
nnoremap <silent> <Leader>rg       :Rg <C-R><C-W><CR>
nnoremap <silent> <Leader>RG       :Rg <C-R><C-A><CR>
xnoremap <silent> <Leader>rg       y:Rg <C-R>"<CR>
nnoremap <silent> <Leader>`        :Marks<CR>
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


"Advanced keymap
"------------------------------------------------------------
"https://vi.stackexchange.com/questions/8451/is-it-possible-to-have-vim-show-the-list-of-available-marks-when-using-marks
"nnoremap ' :Marks<CR>

" jk | Escaping!
inoremap jk <Esc>
xnoremap jk <Esc>
cnoremap jk <C-c>

" qq to record, Q to replay
nnoremap Q @q

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
