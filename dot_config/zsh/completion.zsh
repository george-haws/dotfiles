fpath=("$ZDOTDIR/functions" $fpath)
autoload -U "$ZDOTDIR"/functions/*(:t)

# Rebuild the completion dump once a day; otherwise trust the cache.
autoload -Uz compinit
_dump="$ZDOTDIR/.zcompdump"
if [[ ! -f "$_dump" || -n "$_dump"(#qN.mh+24) ]]; then
  compinit -d "$_dump"
else
  compinit -C -d "$_dump"
fi
unset _dump

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' insert-tab pending

# grc colorizes common tools.
[[ -f /opt/homebrew/etc/grc.zsh ]] && source /opt/homebrew/etc/grc.zsh
