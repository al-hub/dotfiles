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

## rg with fzf
```shell
#!/bin/bash
# https://github.com/junegunn/fzf

INITIAL_QUERY=$1
#RG_PREFIX="rg --column --line-number --no-heading --color=always --smart-case "
RG_PREFIX="rg -i --files-with-matches --color=always "
FZF_DEFAULT_COMMAND="$RG_PREFIX '$INITIAL_QUERY'" 

RG_POSTFIX="rg --colors 'match:bg:51,51,51' --ignore-case --pretty --context 10 "

FILE=$(fzf --bind "change:reload:$RG_PREFIX {q} || true"\
	--bind 'page-up:preview-up,page-down:preview-down'\
	--bind 'ctrl-u:preview-page-up,ctrl-d:preview-page-down'\
	--bind '?:toggle-preview,alt-w:toggle-preview-wrap'\
	--ansi --height=70% --disabled\
	--query "$INITIAL_QUERY"\
	--preview-window right:70%\
	--preview "bat --color=always {} | $RG_POSTFIX {q} ") && vim $FILE
```

## 어려운문제  
tmux상 vim split 을 mouse로 조정 (tmux와 vim이 mouse focus를 2중으로 가져가는 문제)  
vim airline의 buff tab을 mouse로 클릭하여 선택하기 (미구현 문제)  
urxtvt 에 mouse scroll로 fontsize 수정 ( .Xresources의 URxvt keysym 이해 및 .urxvt/ext/resize-font 구조 이해필요  
https://www.reddit.com/r/archlinux/comments/n7n1ah/urxvt_keysym_for_mouse_buttons_singleline/  
https://wiki.archlinux.org/title/Rxvt-unicode  
https://wiki.archlinux.org/title/Rxvt-unicode/Tips_and_tricks  




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
