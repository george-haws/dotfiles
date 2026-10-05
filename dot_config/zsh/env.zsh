export EDITOR='vim'
export PROJECTS=~/src
export GOPATH="$HOME/go"
export LSCOLORS="exfxcxdxbxegedabagacad"
export CLICOLOR=true

# bat renders man pages when installed; col strips the overstrike bold.
if (( $+commands[bat] )); then
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
  export MANROFFOPT="-c"
fi
