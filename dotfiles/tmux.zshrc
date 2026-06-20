PROMPT='$ '
RPROMPT=''

if [ "${DOTFILES_TMUX_CLEAR_ON_START:-}" = 1 ]; then
    unset DOTFILES_TMUX_CLEAR_ON_START
    printf '\033[H\033[2J'
fi

HISTFILE="${HISTFILE:-$HOME/.cache/dotfiles/tmux.zsh_history}"
HISTSIZE=10000
SAVEHIST=10000
setopt append_history
setopt inc_append_history

autoload -Uz compinit
compinit -u
