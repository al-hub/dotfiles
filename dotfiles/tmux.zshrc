# Abbreviated Current Directory in Prompt (~/path $ )
PROMPT='%F{39}%~%f $ '
RPROMPT=''

HISTFILE="${HISTFILE:-$HOME/.cache/dotfiles/tmux.zsh_history}"
HISTSIZE=10000
SAVEHIST=10000
setopt append_history
setopt inc_append_history

autoload -Uz compinit
compinit -u
