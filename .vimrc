set nu
set mouse=a
set hlsearch
set splitright
" Tab navigation like Firefox.
"nnoremap <C-S-tab> :tabprevious<CR>
"nnoremap <C-tab>   :echo tabnext<CR>
"nnoremap <C-t>     :tabnew<CR>
"inoremap <C-S-tab> <Esc>:tabprevious<CR>i
"inoremap <C-tab>   <Esc>:echo tabnext<CR>i
"inoremap <C-t>     <Esc>:tabnew<CR>
"map ^[[1;5I :echo tabnext<CR>

map <Esc>[27;5;9~ :tabnext<CR>
"map <Esc>[27;5;9~ :echo tabnex <CR>
"map <C-tab> :echo   :tabnext<CR>
map <S-tab> :echo S-tab<CR>

call plug#begin('~/.vim/plugged')
Plug 'valloric/python-indent'
Plug 'scrooloose/nerdtree'
Plug 'majutsushi/tagbar'
Plug 'vim-scripts/taglist.vim'
Plug 'wesleyche/srcexpl'
Plug 'vim-scripts/Mark'
Plug 'vim-scripts/Marks-Browser'
Plug 'scrooloose/syntastic'
Plug 'blueyed/vim-diminactive'
Plug 'w0ng/vim-hybrid'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'brafales/vim-desert256'
Plug 'ctrlpvim/ctrlp.vim'
Plug 'christoomey/vim-tmux-navigator'
Plug 'mileszs/ack.vim'
Plug 'yegappan/grep'
Plug 'vimwiki/vimwiki'
Plug 'vim-scripts/ZoomWin'
Plug 'tpope/vim-fugitive'
call plug#end()

"filetype plugin indent on

let g:indent_guides_auto_colors = 1
let g:indent_guides_enable_on_vim_startup = 1
"let g:indent_guides_start_level = 1
"let g:indent_guides_guide_size = 1
"set ts=2 sw=2 et
hi IndentGuidesOdd  ctermbg=black
hi IndentGuidesEven ctermbg=darkgrey

set cursorline
"set cursorcolumn

"tmux.conf set -g default-terminal "screen.xterm-256color
"https://stackoverflow.com/questions/41482516/colorscheme-for-vim-works-on-termite-and-not-on-urxvt
"set termguicolors
"set t_Co=256
set background=dark

colorscheme hybrid
"colorscheme desert256

"au VimEnter * colorscheme hybrid
"syntax on
"filetype plugin indent on 

"https://www.bugsnag.com/blog/tmux-and-vim
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

nmap <F5> :TlistToggle<CR>
nmap <F7> :NERDTreeToggle<CR>
nmap <F8> :SrcExplToggle<CR> 

nmap <F9> <F5><CR> <F7><CR> <F8><CR> 

nnoremap <F3> :Ack % <space>
nnoremap <F2> :Rgrep <CR>
nnoremap <F4> :vimgrep <C-R><C-W> **/*.c **/*.h <Bar> cw <CR><C-W><C-J>

nnoremap <C-w>z :ZoomWin <CR> 


"https://vim.fandom.com/wiki/Scroll_using_arrow_keys_like_in_a_web_browser
"J is dd delete, K is  help keyword
map <S-J> <C-E>
map <S-K> <C-Y>


"map <f4> :s#/\* \(.*\) \*/#\1<CR>:nohlsearch<CR>


nmap <F9> <F5><CR> <F7><CR> <F8><CR> 

"nmap <leader>l :set list!<CR>
"hi NoneText cterm=None ctermfg=darkgrey
"hi SpecialKey cterm=None ctermfg=darkgrey

"set tabstop=8
"set softtabstop=4
"set shiftwidth=4
"set textwidth=100
"set expandtab
"set smartindent cinwords=if,elif,else,for,while,try,except,finally,def,class
"set nocindent

fun! ShowFuncName()
    let lnum = line(".")
    let col = col(".")
    echohl ModeMsg
    echo getline(search("^[^ \t#/]\\{2}.*[^:]\s*$", 'bW'))
    echohl None
    call search("\\%" . lnum . "l" . "\\%" . col . "c")
endfun
"map f :call ShowFuncName() <CR>

set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

"https://rampart81.github.io/post/vim-clipboard-share/
set clipboard=unnamedplus

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 0 
let g:syntastic_check_on_wq = 0

let g:syntastic_cpp_compiler = 'g++'
let g:syntastic_cpp_compiler_options = "-std=c++11 -Wall -Wextra -Wpedantic"
let g:syntastic_c_compiler_options = "-std=c11 -Wall -Wextra -Wpedantic"

