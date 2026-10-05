alias reload!='exec zsh'

# eza, when installed via Homebrew. coreutils stays for the other GNU tools.
if (( $+commands[eza] )); then
  alias ls='eza -lF --git --icons'
  alias l='eza -lah --git --icons'
  alias ll='eza -l --git --icons'
  alias la='eza -a --icons'
fi

(( $+commands[bat] )) && alias cat='bat'
(( $+commands[lazygit] )) && alias lg='lazygit'
# Replaces the old headers script: response headers only.
(( $+commands[xh] )) && alias headers='xh -h'

alias pubkey='pbcopy < ~/.ssh/id_ed25519.pub && echo "=> Public key copied to pasteboard."'
