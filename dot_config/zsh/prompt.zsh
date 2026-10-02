autoload colors && colors
# Prompt after @ehrenmurdick; window title after _why.

if (( $+commands[git] )); then
  git="$commands[git]"
else
  git="/usr/bin/git"
fi

git_prompt_info() {
  local ref
  ref=$($git symbolic-ref HEAD 2>/dev/null) || return
  echo "${ref#refs/heads/}"
}

git_dirty() {
  if ! $git status -s &>/dev/null; then
    echo ""
  elif [[ $($git status --porcelain) == "" ]]; then
    echo "on %{$fg_bold[green]%}$(git_prompt_info)%{$reset_color%}"
  else
    echo "on %{$fg_bold[red]%}$(git_prompt_info)%{$reset_color%}"
  fi
}

unpushed() {
  $git cherry -v @{upstream} 2>/dev/null
}

need_push() {
  if [[ $(unpushed) == "" ]]; then
    echo " "
  else
    echo " with %{$fg_bold[magenta]%}unpushed%{$reset_color%} "
  fi
}

directory_name() {
  echo "%{$fg_bold[cyan]%}%1/%\/%{$reset_color%}"
}

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

export PROMPT=$'\nin $(directory_name) $(git_dirty)$(need_push)\n› '

precmd() {
  title "zsh" "%m" "%55<...<%~"
  export RPROMPT=""
}
