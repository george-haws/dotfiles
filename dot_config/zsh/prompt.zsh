# The prompt is starship, configured in ~/.config/starship.toml to match the
# prompt this file used to draw. Window title after _why.

# Sets the terminal window title.
title() {
  local a
  a=${(V)1//\%/\%\%}
  a=$(print -Pn "%40>...>$a" | tr -d "\n")
  case $TERM in
    screen)       print -Pn "\ek$a:$3\e\\" ;;
    xterm*|rxvt)  print -Pn "\e]2;$2\a" ;;
  esac
}

precmd() {
  title "zsh" "%m" "%55<...<%~"
}

(( $+commands[starship] )) && eval "$(starship init zsh)"
