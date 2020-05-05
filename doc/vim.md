---
### vim
---

## site
https://dhkoo.github.io/2019/09/22/vim/  
https://m.blog.naver.com/PostView.nhn?blogId=jayeonsaram&logNo=220648947768&proxyReferer=https:%2F%2Fwww.google.com%2F  
https://myeongjae.kim/blog/2017/07/18/vimlinux-9-synatstic-문법-체크-플러그인  

source insight  
https://bitdol.tistory.com/entry/소스-인사이트가-가지고-있는-검색-기능들


:tselect /<CR>  
https://stackoverflow.com/questions/26069032/viml-get-list-of-all-ctags  

vim+tmux
https://www.bugsnag.com/blog/tmux-and-vim  
https://github.com/christoomey/vim-tmux-navigator  
https://stfwlg.github.io/archivers/Utility-_vim_사용기_01  
https://agvim.wordpress.com/2015/12/31/tmux/  

## tip
:e ~/.vimrc  


## ~/.vimrc


```
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
call plug#end()
  
nmap <F5> :TlistToggle<CR>
nmap <F7> :NERDTreeToggle<CR>
nmap <F8> :SrcExplToggle<CR>
nmap <F9> <F5><CR> <F7><CR> <F8><CR>

```
  


## ELSE

열었을때, 이전으로 가기 https://idchowto.com/?p=29094 

마크 고찰...   
https://stackoverflow.com/questions/8958047/in-vim-is-there-a-way-to-save-bookmarks-between-sessions  
C-O, C-I

https://sinoroo.tistory.com/entry/VIM-단축키-및-설정

마크를 하지 않아도..  
자동으로 마킹되고 리스트를 보고 찾아 갈 수 있도록!!!  


vim으로 개발한다는 것 (+tmux)  
https://tech.songyunseop.com/post/2017/07/develop-with-vim/ 

vim 플러그인  
https://agvim.wordpress.com/2017/09/05/vim-plugins-100/ 


fuzzyfinder  
http://seorenn.blogspot.com/2011/02/vim-plugin-fuzzyfinder.html  
http://egloos.zum.com/kwon37xi/v/3882496  
https://kwonnam.pe.kr/wiki/vim/fuzzyfinder  

ctrp  
https://www.morenice.kr/207

vimcolor  
https://stackoverflow.com/questions/29167604/setting-vim-cursorline-colors


마크업문법 줄바꿈 개행  
https://bj25.tistory.com/14


## TODO

copy  from tmux pane  easy key  
https://rampart81.github.io/post/vim-clipboard-share/  

vimium  vivaldi


grep  
fzf  ack   
oh-my-zsh  
colorscheme define move  
w3m  tmux  
effecitive keymap   
tmux  easy spilit  

my dotfiles  
vimrc tmux.conf urxvt  

리눅스 터미널 생활  
https://black7375.tistory.com/15  


vim.grep ack  
https://damduc.tistory.com/402  


비정상적 사용 https://wiki.ubuntu-kr.org/index.php/Vim  
조영한 사용 https://gist.github.com/onmoving  
올드패션 http://mataeoh.egloos.com/v/7036315  


dev
https://developer.gnome.org
http://www.cplusplus.com
https://vim.fandom.com/wiki/Vim_Tips_Wiki
http://forum.falinux.com/zbxe/index.php?mid=C_LIB&category=520920
https://www.freedesktop.org/wiki/Software/dbus/
git-scm.com/book/ko/v2/


vimwiki [git연동해야함](https://johngrib.github.io/wiki/my-wiki/#실제로-어떻게-사용하나)  
