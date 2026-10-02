# ~/.local/bin first so the gh shim and git-* scripts win over Homebrew.
typeset -U path
path=(
  "$HOME/.local/bin"
  /opt/homebrew/bin
  /opt/homebrew/sbin
  "$HOME/go/bin"
  $path
)
