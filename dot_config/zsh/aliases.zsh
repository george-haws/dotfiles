alias reload!='exec zsh'

# coreutils ls, when installed via Homebrew.
if (( $+commands[gls] )); then
  alias ls='gls -lF --color'
  alias l='gls -lAh --color'
  alias ll='gls -l --color'
  alias la='gls -A --color'
fi

alias pubkey='pbcopy < ~/.ssh/id_ed25519.pub && echo "=> Public key copied to pasteboard."'
