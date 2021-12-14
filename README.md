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
[examples](https://github.com/junegunn/fzf/wiki/Examples)
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

## zsh & oh-my-zsh

```
■ install: 
sudo apt-get update
sudo apt-get insatll zsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
Do you want to change your default shell to zsh? [Y/n] Y
upgrade_oh_my_zsh

■ uninstall: 
sudo chmod 777 ~/.oh-my-zsh/tools/uninstall.sh
~/.oh-my-zsh/tools/uninstall.sh

■ plugin
# zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

$ vim ~/.zshrc
ZSH_THEME="bureau" 
plugins=( 
 	git
    	zsh-autosuggestions
    	zsh-syntax-highlighting
)
source ~/.rc.custom 
 
$ source ~/.zshrc

■ run
zsh
```

## vifm  
vifmrc
```
fileviewer *.[ch],*.[ch]pp,*.[ch]xx env -uCOLORTERM bat --color always --wrap never --pager never %c -p  
fileviewer *.java,*py,*.txt,*.sh,*.bat,*.md,*.xml,Makefile,*.mk,*.gradle env -uCOLORTERM bat --color always --wrap never --pager never %c -p  
fileviewer *.bmp,*.jpg,*.jpeg,*.png,*.gif,*.xpm
         \ imgt %px %py %pw %ph %c
         \ %pc
         \ imgc %px %py %pw %ph

"https://wiki.vifm.info/index.php/Comparing_files
command! cmpinternal compare-cmd %a %S
command! cmp : if expand('%%c') == expand('%%f')
           \ |     echo expand('Comparing %%"c and %%"C:t ...')
           \ |     cmpinternal %c %C
           \ | else
           \ |     echo expand('Comparing files: %%"f ...')
           \ |     cmpinternal %f
           \ | endif

"http://q2a.vifm.info/633/is-it-possible-to-use-f-f-in-a-not-relative-way
command! diff : if paneisat('right') && paneisat('bottom')
            \ |     execute '!vim -d %%C %%c'
            \ | else
            \ |     execute '!vim -d %%c %%C'
            \ | endif
	    
nnoremap <C-w>q :q!<cr>

" https://wiki.vifm.info/index.php/How_to_integrate_fzf_for_fuzzy_finding
command! FZFfind : set noquickview
                \ | let $FZF_PICK = term('find | fzf --height 10 2>/dev/tty')
                \ | if $FZF_PICK != ''
                \ |     execute '!vim' $FZF_PICK
                \ | endif

command! FZFfindFOLDER : set noquickview
                \ | let $FZF_PICK = term('find | fzf --height 10 2>/dev/tty')
                \ | if $FZF_PICK != ''
                \ |     let $FZF_PATH = term('dirname $FZF_PICK') 
                \ |     execute 'cd' $FZF_PATH
                \ | endif

" variation that automatically enters directories
command! FZFlocate : set noquickview
                \ | let $FZF_PICK = term('find | fzf-tmux --height 10 2>/dev/tty')
                \ | if $FZF_PICK != ''
                \ |     execute 'goto' fnameescape($FZF_PICK)
                \ | endif

nnoremap <c-g> :FZFfindFOLDER<cr>
nnoremap <c-f> :FZFfind<cr>


nnoremap <PageDown>  <C-w>w5j<C-w>w
nnoremap <PageUp>    <C-w>w5k<C-w>w

noremap <C-_> :!sh ~/.fzf/bin/fif-vifm.sh <cr>
```

~/.config/vifm/scripts/compare-cmd  
```
#!/bin/bash

if [ $# != 2 ] ; then
    echo 'Expected exactly two arguments'
    exit 1
fi

if [ -f "$1" -a -f "$2" ]; then
    args=
elif [ -d "$1" -a -d "$2" ]; then
    args='-r'
else
    if [ -f "$1" ]; then
        type_of_1='file'
    else
        type_of_1='directory'
    fi
    if [ -f "$2" ]; then
        type_of_2='file'
    else
        type_of_2='directory'
    fi
    echo "Arguments are of different type ($type_of_1/$type_of_2)"
    exit 1
fi

if diff $args "$1" "$2" > /dev/null 2>&1; then
    echo 'Equal'
else
    echo 'Not equal'
fi
```

~/.config/vifm/scripts/imgc  
```
#!/bin/bash

W3MIMGDISPLAY="/usr/lib/w3m/w3mimgdisplay"
FONTH=15 # Size of one terminal row
FONTW=7 # Size of one terminal column

pane_left=$(tmux display-message -p '#{pane_left}')
pane_top=$(tmux display-message -p '#{pane_top}')

X=$1
Y=$2
X=$((X + pane_left))
Y=$((Y + pane_top))
COLUMNS=$3
LINES=$4

x=$((FONTW * X))
y=$((FONTH * Y))

erase="6;$x;$y;$(( FONTW*COLUMNS ));$(( FONTH*LINES ))\n3;"
echo -e "$erase" | $W3MIMGDISPLAY
```

~/.config/vifm/scripts/imgt  
```
#!/bin/bash
W3MIMGDISPLAY="/usr/lib/w3m/w3mimgdisplay"
FONTH=15 # Size of one terminal row
FONTW=7 # Size of one terminal column

pane_left=$(tmux display-message -p '#{pane_left}')
pane_top=$(tmux display-message -p '#{pane_top}')

X=$(($1 + pane_left))
Y=$(($2 + pane_top))
#X=$((X + pane_left))
#Y=$((Y + pane_top))

COLUMNS=$3
LINES=$4
FILENAME=$5

read width height <<< `echo "5;$FILENAME" | $W3MIMGDISPLAY`
if [ -z "$width" -o -z "$height" ]; then
    echo 'Error: Failed to obtain image size.'
    exit 1
fi

x=$((FONTW * X))
y=$((FONTH * Y))

max_width=$((FONTW * COLUMNS))
max_height=$((FONTH * LINES))

if [ "$width" -gt "$max_width" ]; then
    height=$((height * max_width / width))
    width=$max_width
fi
if [ "$height" -gt "$max_height" ]; then
    width=$((width * max_height / height))
    height=$max_height
fi

w3m_command="0;1;$x;$y;$width;$height;;;;;$FILENAME\n4;\n3;"

echo -e "$w3m_command" | $W3MIMGDISPLAY
```
## w3m  
keymap
```
#navigation similar to vimium
#--------------------------------------------------------------------------------------------------------
keymap j UP
keymap k DOWN
keymap f LIST_MENU
keymap J NEXT_TAB
keymap K PREV_TAB
keymap ? HELP
keymap H BACK
keymap t TAB_LINK
keymap x COMMAND "EXTERN 'echo %s >> ~/.w3m/tmp-restore'; CLOSE_TAB"
keymap X COMMAND "EXTERN 'FILE=~/.w3m/tmp-restore; tail -n 1 $FILE > ~/.w3m/tmp; sed -i \"$ d\" $FILE'; TAB_GOTO ~/.w3m/tmp; MARK_URL;NEXT_LINK;GOTO_LINK"
keymap yy EXTERN 'echo %s | xclip -in -selection clipboar'
keymap yx EXTERN_LINK 'printf %s | xclip -i -selection clipboard'
keymap L SHELL "$EDITOR ~/.w3m/tmp-restore"
#--------------------------------------------------------------------------------------------------------


#split windows with tmux as vim
#--------------------------------------------------------------------------------------------------------
keymap o EXTERN_LINK
keymap C-ws COMMAND "SET_OPTION extbrowser='tmux split-window -v w3m %s'; EXTERN" 
keymap C-w_ COMMAND "SET_OPTION extbrowser='tmux split-window -v w3m %s'; EXTERN_LINK" 
keymap C-wv COMMAND "SET_OPTION extbrowser='tmux split-window -h w3m %s'; EXTERN"
keymap C-w| COMMAND "SET_OPTION extbrowser='tmux split-window -h w3m %s'; EXTERN_LINK"
keymap C-wq COMMAND "EXTERN 'FILE=~/.w3m/tmp-restore; echo %s >> $FILE; echo \"$(uniq $FILE | sed \"/^http/!d\")\" > $FILE'; EXIT"
keymap q COMMAND "EXTERN 'FILE=~/.w3m/tmp-restore; echo %s >> $FILE; echo \"$(uniq $FILE | sed \"/^http/!d\")\" > $FILE'; EXIT"
keymap vi COMMAND "EXTERN 'FILE=~/.w3m/tmp-vim; echo %s > $FILE; vim $FILE'"
keymap vv VIEW
keymap O OPTIONS
#--------------------------------------------------------------------------------------------------------


#image toggle
#--------------------------------------------------------------------------------------------------------
keymap i COMMAND "SET_OPTION display_image=toggle; RELOAD"
#--------------------------------------------------------------------------------------------------------


#java script issue
#--------------------------------------------------------------------------------------------------------
keymap pp COMMAND "VIEW; MARK_URL; NEXT_LINK; GOTO_LINK;"
#keymap pp COMMAND "EXTERN 'var=`echo $W3M_URL | sed \"s/blog/m.blog/g\" | sed \"s/http:/https:/g\"`;w3m $var'; EXIT;"
#--------------------------------------------------------------------------------------------------------


#script example
#https://github.com/gotbletu
#https://vitalyparnas.com/tools/
#keymap po COMMAND "READ_SHELL 'readable $W3M_URL -p html-title,html-content > /tmp/readable.html' ; LOAD /tmp/readable.html; DELETE_PREVBUF"
#keymap po COMMAND "READ_SHELL 'var=`echo $W3M_URL | sed \"s/blog/m.blog/g\"`;w3m $var'; "
#keymap po EXTERN "url=%s; w3m $url"
#keymap po SHELL 'w3m $W3M_URL'
#keymap po COMMAND "SHELL 'var=`echo $W3M_URL | sed \"s/blog/m.blog/g\"`;w3m $var'; EXIT;"
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
