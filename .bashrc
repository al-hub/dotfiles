#WSL bashrc

# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    #PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\W\[\033[00m\]\$ '
else
    #PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
    PS1='${debian_chroot:+($debian_chroot)}\W\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi


export DISPLAY=:0.0
#export LIBGL_ALWAYS_INDIRECT=1
export PULSE_SERVER=tcp:127.0.0.1
export XDG_RUNTIME_DIR=/run/user/1000  
#dpkg -l | grep gstreamer | grep 1.0
#sudo apt-get install gstreamer1.0-libav
#gst-launch-1.0 filesrc location=big_buck_bunny_720p_1mb.mp4 ! decodebin3 ! videoconvert ! ximagesink
#https://wiki.archlinux.org/index.php/Mpv
function yta() {
	    mpv --ytdl-format=bestaudio ytdl://ytsearch:"$*"
    }
xrdb ~/.Xresources


#https://superuser.com/questions/1043806/how-to-exit-the-ranger-file-explorer-back-to-command-prompt-but-keep-the-current
#other https://github.com/ranger/ranger/wiki/Integration-with-other-programs#changing-directories
alias ranger='ranger --choosedir=$HOME/.rangerdir; LASTDIR=`cat $HOME/.rangerdir`; cd "$LASTDIR"'


#vif 
#####################################################################################################
vif()
{
    local dst="$(command vifm --choose-dir - "$@")"
    if [ -z "$dst" ]; then
        echo 'Directory picking cancelled/failed'
        return 1
    fi
    cd "$dst"
}  
#####################################################################################################


#fzf #https://medium.com/harrythegreat/fzf%EB%A1%9C-%EC%BB%A4%EC%8A%A4%ED%84%B0%EB%A7%88%EC%9D%B4%EC%A7%95%ED%95%98%EA%B8%B0-cc9e8fee0fb
#####################################################################################################
#wget https://github.com/sharkdp/bat/releases/download/v0.18.3/bat_0.18.3_amd64.deb
#sudo dpkg -i bat_0.18.3_amd64.deb

#wget https://github.com/Peltoche/lsd/releases/download/0.20.1/lsd_0.20.1_amd64.deb
#sudo dpkg -i lsd_0.20.1_amd64.deb

#wget https://github.com/sharkdp/fd/releases/download/v8.3.0/fd_8.3.0_amd64.deb
#sudo dpkg -i fd_8.3.0_amd64.deb
function fif() {
  if [ ! "$#" -gt 0 ]; then echo "검색어를 입력해주세요."; return 1; fi
  file=$(rg --files-with-matches "$1" | fzf\
  --border\
  --height 80%\
  --extended\
  --ansi\
  --reverse\
  --cycle\
  --header 'Find in File'\
  --bind 'f1:execute(less -f {}),ctrl-y:execute-silent(echo {} | pbcopy)+abort'\
  --bind 'page-up:preview-up,page-down:preview-down'\
  --bind 'ctrl-u:preview-page-up,ctrl-d:preview-page-down'\
  --bind '?:toggle-preview,alt-w:toggle-preview-wrap'\
  --bind 'alt-v:execute(nvim {} >/dev/tty </dev/tty)'\
  --preview "bat --theme='OneHalfDark' --style=numbers --color=always {} | rg --colors 'match:bg:51,51,51' --ignore-case --pretty --context 10 '$1' ") && vim "$file"
}

function vifz() {
  local dir
  dir=$(fd --type d --hidden --follow --exclude .git 2>/dev/null | fzf\
  --header 'Search In Directory'\
  --border\
  --height 80%\
  --extended\
  --ansi\
  --reverse\
  --cycle\
  --header 'Search Directory'\
  --bind 'alt-p:preview-up,alt-n:preview-down'\
  --bind 'ctrl-u:half-page-up,ctrl-d:half-page-down'\
  --bind "alt-s:execute(lsd {})+abort"\
  --bind '?:toggle-preview,alt-w:toggle-preview-wrap'\
  --bind 'alt-v:execute($EDITOR {$FZF_PATH_LOC} >/dev/tty </dev/tty)'\
  --preview 'lsd --color=always --tree --depth=2  {} | head -200 2>/dev/null'\
  --preview-window=right:50%) && cd "$dir"
}
#####################################################################################################


#w3m
#####################################################################################################
#alias google="w3m https://www.google.com/search?q='$@'"
#alias namu="w3m https://namu.wiki/w/$1"
#alias dic="w3m dict.naver.com/search.nhn?dicQuery=$1"

function google(){
	#echo \"$@\"
	keyword=$@
	w3m https://www.google.com/search?q="$keyword"
}
function naver(){
	#echo \"$@\"
	keyword=$@
	w3m https://search.naver.com/search.naver?query="$keyword"
}
function namu() { 
	w3m https://namu.wiki/w/$1
}
function duck() { 
	keyword=$@
	w3m https://duckduckgo.com/?q="$keyword"
}
function dic() { 
	KEYWORD=$1
	ENDWORD="영어사전"
	SIZE=30
	SITE="dict.naver.com/search.nhn?dicQuery="
	w3m $SITE$KEYWORD | grep ^$KEYWORD.*play -A $SIZE | grep $ENDWORD -B $SIZE | grep -v $ENDWORD 
}
#####################################################################################################


# some more ls aliases
#####################################################################################################
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
#####################################################################################################
