dotfiles
===

I hope to update my dotfiles.


## vim

I'm using [vim-plug][] to manage plugins.  

```
curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

.vimrc
call plug#begin('~/.vim/plugged')
Plug 'scrooloose/nerdtree', { 'on':  'NERDTreeToggle' }
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
call plug#end()


PlugInstall
PlugUpdate
PlugClean

```
[vim-plug]: https://github.com/junegunn/vim-plug


## urxvt

Learning

## tmux

Learning


short cut
default : c+b &, "

reload  
bind, : source-file ~/.tmux.conf  

## 어려운문제  
tmux상 vim split 을 mouse로 조정 (tmux와 vim이 mouse focus를 2중으로 가져가는 문제)  
vim airline의 buff tab을 mouse로 클릭하여 선택하기 (미구현 문제)  
urxtvt 에 mouse scroll로 fontsize 수정 ( .Xresources의 URxvt keysym 이해 및 .urxvt/ext/resize-font 구조 이해필요  
https://wiki.archlinux.org/title/Rxvt-unicode https://wiki.archlinux.org/title/Rxvt-unicode/Tips_and_tricks  


## ref
- [endeavor but worth](https://www.bugsnag.com/blog/tmux-and-vim)  
[terminal_life](https://black7375.tistory.com/15)  
https://tech.songyunseop.com/post/2017/07/develop-with-vim/  
https://gitlab.com/dwt1/dotfiles/-/tree/master  
https://jdhao.github.io/2018/09/30/tmux_settings_for_vim_users/  
https://github.com/junegunn/dotfiles  
https://github.com/atomantic/dotfiles  
https://velog.io/@wannte/dotfile을-편하게-관리하는-방법with-Bare-Git-repository  
https://github.com/jongmin92/dev-settings  
https://github.com/lesstif/dotfiles  
https://github.com/christoomey/dotfiles  
https://github.com/johngrib/dotfiles  
https://github.com/rr-/dotfiles/tree/master/cfg  

Thanks all!!
