[[ $- != *i* ]] && return

# HISTORY
HISTFILE="$HOME/.bash_history"
HISTSIZE=50000
HISTFILESIZE=50000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a; history -n${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# OPTIONS
shopt -s cdspell dirspell extglob globstar autocd checkjobs

# KEY BINDINGS
bind '"\e[1;5C": forward-word'
bind '"\e[1;5D": backward-word'
bind '"\C-h": backward-kill-word'
bind '"\e[3;5~": kill-word'
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'

# ALIASES
alias yay='paru'
alias ls='ls --color=auto'
alias ll='ls -lh'
alias la='ls -lAh'
alias lt='ls -lRh'
alias l='ls -CF'

# FUNCTIONS
mkcd() { mkdir -p "$1" && cd "$1"; }

# TOOLS
command -v mise     >/dev/null && eval "$(mise activate bash)"
command -v fzf      >/dev/null && eval "$(fzf --bash)"
command -v starship >/dev/null && eval "$(starship init bash)"
