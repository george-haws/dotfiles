# Third-party shell integrations. Each block is skipped when its tool is
# absent, so a shell opened before `brew bundle` finishes still starts clean.
# Sourced after completion.zsh: zoxide registers its completion only when
# compinit has already run.

if (( $+commands[fzf] )); then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
  # fzf's script saves the shell options and restores them afterwards, and
  # restoring `zle` fails with "can't change option: zle" when stdin is not a
  # terminal, as in `zsh -ic cmd` run from a script or an editor. Key bindings
  # do nothing there anyway, so load them only for a shell on a terminal.
  [[ -t 0 ]] && source <(fzf --zsh)
fi

(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"

# atuin binds Ctrl-R after fzf did, so atuin wins; fzf keeps Ctrl-T and Alt-C.
# Up arrow stays plain history, so it never opens the search UI by surprise.
(( $+commands[atuin] )) && eval "$(atuin init zsh --disable-up-arrow)"
