# Modern CLI Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the current baseline of shell and git CLI tools to the dotfiles, put Claude Code and Zed settings under chezmoi, and give Claude Code a status line that reads the same on every machine.

**Architecture:** Everything is additive to the existing chezmoi source tree at `~/.dotfiles`. The Brewfile grows; zsh gains two new files in its explicit source order, `tools.zsh` for third-party integrations and `plugins.zsh` last for autosuggestions and syntax highlighting; the hand-drawn prompt is replaced by a starship config that reproduces it; the gitconfig template gains delta and difftastic; `~/.claude/settings.json` and `~/.config/zed/settings.json` become managed files; a POSIX sh script in `~/.local/bin` renders the status line. The doctor and the render test suite grow to cover all of it.

**Tech Stack:** chezmoi, zsh, POSIX sh, Homebrew, git 2.56, jq (Apple's, at `/usr/bin/jq`), starship, atuin.

**Spec:** `docs/superpowers/specs/2026-10-04-modern-cli-tools-design.md`

## Global Constraints

- Platform: macOS on Apple Silicon. Homebrew prefix is `/opt/homebrew`.
- Interactive shell startup stays under 0.3 seconds. The doctor measures it; the suite's `zsh: starts with no Homebrew` test must keep passing, so every new shell integration is guarded on its command or file existing.
- `~/.local/bin` is first on PATH, before `/opt/homebrew/bin`.
- Work identifiers never appear in the repo, this plan, or tests. Tests use `work@example.com` and `example-org`.
- Tests never write to the real `$HOME`. They render into a temp directory with `--destination` and `--persistent-state` pointed at temp paths. Only Task 9 touches the live machine, and it stops to confirm first.
- Nothing under `~/.claude/skills/` enters the repo. Only `~/.claude/settings.json` is tracked under `~/.claude/`.
- nvm stays. `nvm.zsh`, `brew "nvm"`, `brew "node"`, and `brew "yarn"` are removed by the later mise changeset, not this one.
- Casks in scope are exactly `iterm2`, `zed`, and `font-jetbrains-mono-nerd-font`.
- Zsh and sh files are plain files unless they need chezmoi data; the doctor is the only template this plan edits.
- Commit after every task. Commit messages are one imperative sentence in the repo's existing style (`Add ...`, `Spec: ...`) and end with a blank line then `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Run the whole suite with `./test/render.sh` from the repo root; it needs chezmoi and git but nothing else installed. Every task ends with the suite fully green.

## Review Focus

1. **Startup with nothing installed.** A fresh machine opens a shell after `install.sh` and possibly before `brew bundle` finishes. `tools.zsh`, `plugins.zsh`, `prompt.zsh`, `env.zsh`, and `aliases.zsh` must not error when `/opt/homebrew` is absent. The existing `env -i` test pins this; Task 2 and Task 3 extend it.
2. **Source order.** `plugins.zsh` is last because syntax highlighting wraps every ZLE widget defined before it, and autosuggestions needs `compinit` done. `tools.zsh` comes before `prompt.zsh` so atuin's Ctrl-R binding lands after fzf's. Task 2 pins the exact order string.
3. **Status line outside a repo and without an upstream.** `git rev-parse` fails outside a repo; `@{upstream}` fails on a branch with no upstream. The script must print a sane line in both cases and never leak git's stderr. Task 6 tests all three states.
4. **settings.json is rewritten by Claude Code.** `chezmoi apply` would clobber an interactive permission change. The doctor warns on drift instead of failing, and the README names `chezmoi re-add` as the fix. Task 7 and Task 8.
5. **Casks already present.** iTerm2 and Zed are in `/Applications` from manual downloads. `brew bundle` refuses to install over them, so Task 9 adopts them by hand first.

---

### Task 1: Brewfile

**Files:**
- Modify: `Brewfile`
- Test: `test/render.sh` (the `# Task 7: Brewfile and scripts` block)

**Interfaces:**
- Produces: every binary later tasks guard on: `rg`, `fd`, `fzf`, `bat`, `eza`, `zoxide`, `atuin`, `starship`, `xh`, `delta`, `difft`, `lazygit`, `git-absorb`.

- [ ] **Step 1: Extend the Brewfile assertions**

In `test/render.sh`, replace the line

```sh
for pkg in coreutils gh git git-lfs go grc nvm vim; do check_grep "Brewfile: $pkg" "$P/Brewfile" "brew \"$pkg\""; done
```

with

```sh
for pkg in coreutils gh git git-lfs go grc nvm vim \
           node yarn cocoapods mobile-dev-inc/tap/maestro facebook/fb/idb-companion openjdk ruby spark \
           ripgrep fd fzf bat eza zoxide zsh-autosuggestions zsh-syntax-highlighting atuin starship xh \
           git-delta difftastic lazygit git-absorb; do
  check_grep "Brewfile: $pkg" "$P/Brewfile" "^brew \"$pkg\""
done
for t in mobile-dev-inc/tap facebook/fb; do check_grep "Brewfile: tap $t" "$P/Brewfile" "^tap \"$t\""; done
for c in iterm2 zed font-jetbrains-mono-nerd-font; do check_grep "Brewfile: cask $c" "$P/Brewfile" "^cask \"$c\""; done
check_eq "Brewfile: exactly three casks" "$(grep -c '^cask ' "$P/Brewfile")" "3"
check_nogrep "Brewfile: no mise yet" "$P/Brewfile" 'mise'
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: `FAIL Brewfile: node` and the other new packages, taps, and casks. Nothing else fails.

- [ ] **Step 3: Write the Brewfile**

Replace `Brewfile` with:

```ruby
tap "mobile-dev-inc/tap"
tap "facebook/fb"

# Already in use
brew "coreutils"
brew "gh"
brew "git"
brew "git-lfs"
brew "go"
brew "grc"
brew "nvm"
brew "vim"

# Installed by hand before 2026-10-04. The mise changeset removes node and yarn.
brew "node"
brew "yarn"
brew "cocoapods"
brew "mobile-dev-inc/tap/maestro"
brew "facebook/fb/idb-companion"
brew "openjdk"
brew "ruby"
brew "spark"

# Shell
brew "ripgrep"
brew "fd"
brew "fzf"
brew "bat"
brew "eza"
brew "zoxide"
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "atuin"
brew "starship"
brew "xh"

# Git
brew "git-delta"
brew "difftastic"
brew "lazygit"
brew "git-absorb"

# Apps. On a machine where these already exist in /Applications, run
# `brew install --cask --adopt iterm2 zed` once before the first apply.
cask "iterm2"
cask "zed"
cask "font-jetbrains-mono-nerd-font"
```

- [ ] **Step 4: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

- [ ] **Step 5: Commit**

```bash
git add Brewfile test/render.sh
git commit -m "Add the shell, git, and app tooling to the Brewfile

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Shell integrations, aliases, and atuin config

**Files:**
- Create: `dot_config/zsh/tools.zsh`, `dot_config/zsh/plugins.zsh`, `dot_config/atuin/config.toml`
- Modify: `dot_config/zsh/dot_zshrc`, `dot_config/zsh/env.zsh`, `dot_config/zsh/aliases.zsh`, `dot_config/zsh/git.zsh`
- Delete: `dot_local/bin/executable_headers`
- Test: `test/render.sh` (the `# Task 5: zsh` and `# Task 6: bin and vimrc` blocks)

**Interfaces:**
- Produces: the source order `path env options aliases git nvm tools prompt completion plugins`. Task 3 edits `prompt.zsh` in that slot and relies on `tools.zsh` having already run.

- [ ] **Step 1: Update the zsh assertions**

In `test/render.sh`, in the `# Task 5: zsh` block, change the file loop and the order assertion:

```sh
for f in .zshrc path.zsh env.zsh options.zsh aliases.zsh git.zsh nvm.zsh tools.zsh prompt.zsh completion.zsh plugins.zsh; do
  check_file "$P/.config/zsh/$f"
  if zsh -n "$P/.config/zsh/$f" 2>/dev/null; then pass "zsh -n $f"; else fail "zsh -n $f: syntax error"; fi
done
```

```sh
check_grep "zshrc: explicit order" "$P/.config/zsh/.zshrc" 'for f in path env options aliases git nvm tools prompt completion plugins; do'
```

Then append these lines at the end of the `# Task 5: zsh` block, after the `zsh: lazy stubs and autoloads defined` assertion:

```sh
# Task 2 (2026-10-04): tool integrations
check_grep "tools: fzf guarded" "$P/.config/zsh/tools.zsh" 'commands\[fzf\]'
check_grep "tools: fzf zsh integration" "$P/.config/zsh/tools.zsh" 'source <\(fzf --zsh\)'
check_grep "tools: fd drives fzf" "$P/.config/zsh/tools.zsh" "FZF_DEFAULT_COMMAND='fd "
check_grep "tools: zoxide guarded" "$P/.config/zsh/tools.zsh" 'commands\[zoxide\].*zoxide init zsh'
check_grep "tools: atuin after fzf, up arrow untouched" "$P/.config/zsh/tools.zsh" 'atuin init zsh --disable-up-arrow'
fz=$(grep -n 'fzf --zsh' "$P/.config/zsh/tools.zsh" | head -1 | cut -d: -f1)
at=$(grep -n 'atuin init' "$P/.config/zsh/tools.zsh" | head -1 | cut -d: -f1)
if [ -n "$fz" ] && [ -n "$at" ] && [ "$fz" -lt "$at" ]; then pass "tools: atuin binds after fzf"; else fail "tools: atuin must come after fzf"; fi
check_grep "plugins: autosuggestions from Homebrew" "$P/.config/zsh/plugins.zsh" '/opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh'
check_grep "plugins: syntax highlighting from Homebrew" "$P/.config/zsh/plugins.zsh" '/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
as=$(grep -n 'zsh-autosuggestions.zsh' "$P/.config/zsh/plugins.zsh" | head -1 | cut -d: -f1)
sh_=$(grep -n 'zsh-syntax-highlighting.zsh' "$P/.config/zsh/plugins.zsh" | head -1 | cut -d: -f1)
if [ -n "$as" ] && [ -n "$sh_" ] && [ "$as" -lt "$sh_" ]; then pass "plugins: highlighting last"; else fail "plugins: highlighting must be last"; fi
check_grep "env: bat as man pager" "$P/.config/zsh/env.zsh" "MANPAGER=.*bat -l man -p"
check_grep "aliases: eza ls" "$P/.config/zsh/aliases.zsh" "alias ls='eza -lF --git --icons'"
check_grep "aliases: eza l" "$P/.config/zsh/aliases.zsh" "alias l='eza -lah --git --icons'"
check_grep "aliases: eza ll" "$P/.config/zsh/aliases.zsh" "alias ll='eza -l --git --icons'"
check_grep "aliases: eza la" "$P/.config/zsh/aliases.zsh" "alias la='eza -a --icons'"
check_nogrep "aliases: gls gone" "$P/.config/zsh/aliases.zsh" 'gls'
check_grep "aliases: cat is bat" "$P/.config/zsh/aliases.zsh" "alias cat='bat'"
check_grep "aliases: lg" "$P/.config/zsh/aliases.zsh" "alias lg='lazygit'"
check_grep "aliases: headers via xh" "$P/.config/zsh/aliases.zsh" "alias headers='xh -h'"
check_grep "git aliases: dft" "$P/.config/zsh/git.zsh" "alias dft='git difftool'"
check_file "$P/.config/atuin/config.toml"
check_grep "atuin: sync off" "$P/.config/atuin/config.toml" '^auto_sync = false'
check_grep "atuin: no update check" "$P/.config/atuin/config.toml" '^update_check = false'
check_grep "atuin: directory filter on up arrow" "$P/.config/atuin/config.toml" '^filter_mode_shell_up_key_binding = "directory"'
out=$(env -i HOME="$h" TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -i -c 'whence -w ls cat lg headers 2>&1 | tr "\n" " "' 2>&1)
check_eq "zsh: no Homebrew -> no eza/bat/lazygit/xh aliases" "$out" "ls: command cat: command lg: none headers: none "
```

The last assertion reuses `$h`, the Homebrew-free fake home built earlier in the block. With nothing installed, `ls` and `cat` must be the plain commands and `lg` and `headers` must not exist, which proves every alias is guarded.

Note: the `# Task 5` block copies `$P/.config` into `$h` before running `env -i`. That copy happens above the new lines, so `tools.zsh` and `plugins.zsh` are present in `$h` when the no-Homebrew test runs.

In the `# Task 6: bin and vimrc` block, remove `headers` from the executable loop so it reads:

```sh
for s in git-all git-amend git-copy-branch-name git-credit git-delete-local-merged git-nuke git-promote git-rank-contributors git-review git-track git-undo git-unpushed git-unpushed-stat git-up git-wtf e todo macos-defaults; do
```

and add directly below it:

```sh
check_nofile "$P/.local/bin/headers"
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: failures for `tools.zsh`, `plugins.zsh`, the order string, the eza aliases, `cat`, `lg`, `headers`, `dft`, `MANPAGER`, the atuin config, and `should not exist .../headers`.

- [ ] **Step 3: Write `tools.zsh`**

Create `dot_config/zsh/tools.zsh`:

```zsh
# Third-party shell integrations. Each block is skipped when its tool is
# absent, so a shell opened before `brew bundle` finishes still starts clean.

if (( $+commands[fzf] )); then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
  source <(fzf --zsh)
fi

(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"

# atuin binds Ctrl-R after fzf did, so atuin wins; fzf keeps Ctrl-T and Alt-C.
# Up arrow stays plain history, so it never opens the search UI by surprise.
(( $+commands[atuin] )) && eval "$(atuin init zsh --disable-up-arrow)"
```

- [ ] **Step 4: Write `plugins.zsh`**

Create `dot_config/zsh/plugins.zsh`:

```zsh
# Sourced last. Syntax highlighting wraps every ZLE widget defined before it,
# and autosuggestions reads the completion system compinit set up.
[[ -f /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] &&
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] &&
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
```

- [ ] **Step 5: Update the source order**

In `dot_config/zsh/dot_zshrc`, change the loop line to:

```zsh
for f in path env options aliases git nvm tools prompt completion plugins; do
```

- [ ] **Step 6: Add the man pager to `env.zsh`**

Append to `dot_config/zsh/env.zsh`:

```zsh

# bat renders man pages when installed; col strips the overstrike bold.
if (( $+commands[bat] )); then
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
  export MANROFFOPT="-c"
fi
```

- [ ] **Step 7: Rewrite the aliases**

Replace `dot_config/zsh/aliases.zsh` with:

```zsh
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
```

- [ ] **Step 8: Add the difftastic alias**

Append to `dot_config/zsh/git.zsh`:

```zsh
alias dft='git difftool'
```

- [ ] **Step 9: Delete the headers script and write the atuin config**

```bash
git rm -q dot_local/bin/executable_headers
mkdir -p dot_config/atuin
```

Create `dot_config/atuin/config.toml`:

```toml
# Local history only. Sync is off on purpose: work commands stay on the
# work machine. fzf keeps Ctrl-T and Alt-C; atuin owns Ctrl-R.
auto_sync = false
update_check = false
search_mode = "fuzzy"
filter_mode = "global"
filter_mode_shell_up_key_binding = "directory"
style = "compact"
inline_height = 20
enter_accept = false
```

- [ ] **Step 10: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

If `zsh: starts with no Homebrew` fails, a guard is missing; `zsh -i -c exit` in the fake home will print the offending line.

- [ ] **Step 11: Commit**

```bash
git add dot_config/zsh dot_config/atuin test/render.sh
git commit -m "Add fzf, zoxide, atuin, bat, eza, xh, and zsh plugins to the shell

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: starship prompt

**Files:**
- Create: `dot_config/starship.toml`
- Modify: `dot_config/zsh/prompt.zsh`
- Test: `test/render.sh`

**Interfaces:**
- Consumes: the `prompt` slot in the source order from Task 2.
- Produces: the prompt `in <dir> on <branch> with unpushed` / `› ` drawn by starship, with the branch green when clean and red when dirty.

- [ ] **Step 1: Write the assertions**

Append to the `# Task 5: zsh` block in `test/render.sh`, after the Task 2 lines:

```sh
# Task 3 (2026-10-04): starship
check_file "$P/.config/starship.toml"
check_grep "starship: guarded init" "$P/.config/zsh/prompt.zsh" 'commands\[starship\].*starship init zsh'
check_nogrep "prompt: hand-drawn PROMPT gone" "$P/.config/zsh/prompt.zsh" 'export PROMPT='
check_nogrep "prompt: git helpers gone" "$P/.config/zsh/prompt.zsh" 'git_dirty|need_push|git_prompt_info'
check_grep "prompt: window title kept" "$P/.config/zsh/prompt.zsh" '^title\(\)'
check_grep "starship: clean branch green" "$P/.config/starship.toml" '^\[custom.branch_clean\]'
check_grep "starship: dirty branch red" "$P/.config/starship.toml" '^\[custom.branch_dirty\]'
check_grep "starship: unpushed marker" "$P/.config/starship.toml" 'with \[unpushed\]\(bold magenta\)'
check_grep "starship: prompt character" "$P/.config/starship.toml" 'success_symbol = "›"'
check_grep "starship: builtin git_branch off" "$P/.config/starship.toml" '^\[git_branch\]'
out=$(env -i HOME="$h" TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -i -c 'echo started' 2>&1)
check_eq "zsh: starts with no starship" "$out" "started"
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: `FAIL missing .../.config/starship.toml`, `FAIL starship: guarded init`, and the two `prompt:` negatives.

- [ ] **Step 3: Write `starship.toml`**

Create `dot_config/starship.toml`:

```toml
# Reproduces the prompt this repo drew by hand before starship:
#
#   in <dir> on <branch> with unpushed
#   ›
#
# dir is cyan. The branch is green when the tree is clean and red when dirty,
# which starship's git_branch cannot do, so two custom modules draw it.
# "with unpushed" appears in magenta when the branch is ahead of upstream.

add_newline = true
format = """
in $directory\
${custom.branch_clean}\
${custom.branch_dirty}\
$git_status\
$nodejs\
$golang\
$status
$character"""

[directory]
format = "[$path]($style) "
style = "bold cyan"
truncation_length = 1
truncate_to_repo = false

[git_branch]
disabled = true

[custom.branch_clean]
description = "git branch, green when the tree is clean"
when = 'git diff --quiet --ignore-submodules HEAD 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard | head -1)" ]'
command = 'git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --short HEAD'
shell = ["sh"]
require_repo = true
format = "on [$output]($style) "
style = "bold green"

[custom.branch_dirty]
description = "git branch, red when the tree is dirty"
when = '! git diff --quiet --ignore-submodules HEAD 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard | head -1)" ]'
command = 'git symbolic-ref --short -q HEAD 2>/dev/null || git rev-parse --short HEAD'
shell = ["sh"]
require_repo = true
format = "on [$output]($style) "
style = "bold red"

[git_status]
format = "$ahead_behind"
ahead = "with [unpushed](bold magenta) "
diverged = "with [unpushed](bold magenta) "
behind = ""

[nodejs]
format = "[$symbol($version )]($style)"
symbol = "node "

[golang]
format = "[$symbol($version )]($style)"
symbol = "go "

[status]
disabled = false
format = "[$status]($style) "
style = "bold red"

[character]
success_symbol = "›"
error_symbol = "›"
```

- [ ] **Step 4: Shrink `prompt.zsh`**

Replace `dot_config/zsh/prompt.zsh` with:

```zsh
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
```

starship registers itself through `precmd_functions`, so the plain `precmd` function above and starship's hook both run.

- [ ] **Step 5: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

- [ ] **Step 6: Commit**

```bash
git add dot_config/starship.toml dot_config/zsh/prompt.zsh test/render.sh
git commit -m "Draw the prompt with starship

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: delta and difftastic in gitconfig

**Files:**
- Modify: `dot_gitconfig.tmpl`
- Test: `test/render.sh` (the `# Task 3: git identity` block)

**Interfaces:**
- Produces: `git diff`, `git log -p`, and `git show` paged through delta; `git dft` and the shell alias `dft` from Task 2 open difftastic.

- [ ] **Step 1: Write the assertions**

Append to the `# Task 3: git identity` block in `test/render.sh`, after the `check_grep "gitconfig: allowedSignersFile" ...` line:

```sh
# Task 4 (2026-10-04): delta and difftastic
check_grep "gitconfig: delta pager" "$P/.gitconfig" '^[[:space:]]*pager = delta$'
check_grep "gitconfig: delta interactive filter" "$P/.gitconfig" 'diffFilter = delta --color-only'
check_grep "gitconfig: delta navigate" "$P/.gitconfig" '^[[:space:]]*navigate = true'
check_grep "gitconfig: zdiff3 conflicts" "$P/.gitconfig" 'conflictStyle = zdiff3'
check_grep "gitconfig: difftastic difftool" "$P/.gitconfig" '^\[difftool "difftastic"\]'
check_grep "gitconfig: difftastic cmd" "$P/.gitconfig" 'cmd = difft "\$LOCAL" "\$REMOTE"'
check_grep "gitconfig: dft alias" "$P/.gitconfig" 'dft = difftool --tool=difftastic'
check_eq "gitconfig: difftool prompt set once" "$(grep -c '^[[:space:]]*prompt = false' "$P/.gitconfig")" "1"
check_eq "git(personal): core.pager resolves" "$(gitp -C "$r/p" config core.pager)" "delta"
check_eq "git(work): core.pager resolves" "$(gitw -C "$r/work" config core.pager)" "delta"
```

The last two lines use `gitp`, `gitw`, and `$r` defined earlier in the block, so they must sit below the `gitp init -q "$r/p"` line. Place the whole Task 4 group at the end of the `# Task 3` block, just above `# Task 4: gh shim`.

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: nine `gitconfig:` and `git(...)` failures.

- [ ] **Step 3: Edit the gitconfig template**

In `dot_gitconfig.tmpl`, change the `[core]` section to:

```
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes -o AddKeysToAgent=yes -o IgnoreUnknown=UseKeychain -o UseKeychain=yes
    excludesfile = ~/.config/git/ignore
    editor = vim
    pager = delta
```

Insert after the `[rerere]` section:

```
[interactive]
    diffFilter = delta --color-only
[delta]
    navigate = true
    line-numbers = true
    side-by-side = false
[merge]
    conflictStyle = zdiff3
[diff]
    colorMoved = default
[difftool "difftastic"]
    cmd = difft "$LOCAL" "$REMOTE"
```

Add to the existing `[alias]` section:

```
    dft = difftool --tool=difftastic
```

Leave the existing `[difftool]` block with `prompt = false` where it is.

- [ ] **Step 4: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

- [ ] **Step 5: Commit**

```bash
git add dot_gitconfig.tmpl test/render.sh
git commit -m "Page git through delta and add difftastic as a difftool

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Claude Code and Zed settings under chezmoi

**Files:**
- Create: `dot_claude/settings.json`, `dot_config/zed/private_settings.json` (chezmoi picks the `private_` prefix from the live file's 0600 mode; keep whatever `chezmoi add` produces)
- Test: `test/render.sh`

**Interfaces:**
- Produces: `dot_claude/settings.json` as the source of truth for `~/.claude/settings.json`. Task 6 adds the `statusLine` key to this file.

- [ ] **Step 1: Write the assertions**

Append to `test/render.sh` just above `# Task 9: doctor`:

```sh
# Task 5 (2026-10-04): Claude Code and Zed settings
for t in personal work; do
  check_file "$tmp/$t/.claude/settings.json"
  if jq -e . "$tmp/$t/.claude/settings.json" >/dev/null 2>&1; then pass "claude settings($t): valid JSON"; else fail "claude settings($t): invalid JSON"; fi
  check_eq "claude settings($t): only settings.json under .claude" "$(find "$tmp/$t/.claude" -type f | sed "s|$tmp/$t/.claude/||" | sort | tr '\n' ' ')" "settings.json "
  check_file "$tmp/$t/.config/zed/settings.json"
  check_grep "zed settings($t): content present" "$tmp/$t/.config/zed/settings.json" '"base_keymap"'
done
check_eq "claude settings: no credentials key" "$(jq -r 'keys[]' "$P/.claude/settings.json" | grep -c -i -E 'token|credential|apiKey|secret')" "0"
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: `FAIL missing .../.claude/settings.json` and `.../.config/zed/settings.json` for both trees.

- [ ] **Step 3: Add the live files to the source tree**

```bash
chezmoi add ~/.claude/settings.json ~/.config/zed/settings.json
git status --short
```

Expected: `?? dot_claude/settings.json` and `?? dot_config/zed/private_settings.json` (or `settings.json` if the mode is 0644; either is fine).

- [ ] **Step 4: Review the copied settings for anything that must not be committed**

```bash
jq -r 'keys[]' dot_claude/settings.json
grep -n -i -E 'token|secret|password|api[_-]?key' dot_claude/settings.json dot_config/zed/*settings.json || echo "clean"
```

Expected: top-level keys are configuration (`model`, `enabledPlugins`, `extraKnownMarketplaces`, `modelSettings`, `theme`, `agentPushNotifEnabled`, `autoMode`) and the grep prints `clean`. If anything secret appears, stop and ask; do not commit it.

- [ ] **Step 5: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

- [ ] **Step 6: Commit**

```bash
git add dot_claude dot_config/zed test/render.sh
git commit -m "Manage Claude Code and Zed settings with chezmoi

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Claude Code status line

**Files:**
- Create: `dot_local/bin/executable_claude-statusline`
- Modify: `dot_claude/settings.json`
- Test: `test/render.sh`

**Interfaces:**
- Consumes: `dot_claude/settings.json` from Task 5.
- Produces: `~/.local/bin/claude-statusline`, which reads Claude Code's session JSON on stdin and prints one line: `<repo> on <branch>`, plus ` with unpushed` when ahead of upstream, or the directory basename outside a repo. Task 7's doctor runs it.

- [ ] **Step 1: Write the assertions**

Append to `test/render.sh` directly after the Task 5 block from the previous task:

```sh
# Task 6 (2026-10-04): Claude Code status line
sl="$P/.local/bin/claude-statusline"
check_file "$sl"
[ -x "$sl" ] && pass "statusline: executable" || fail "statusline: not executable"
sh -n "$sl" && pass "statusline: sh -n" || fail "statusline: syntax"
check_eq "claude settings: statusLine command" "$(jq -r '.statusLine.command' "$P/.claude/settings.json")" "~/.local/bin/claude-statusline"
check_eq "claude settings: statusLine type" "$(jq -r '.statusLine.type' "$P/.claude/settings.json")" "command"
strip_ansi() { sed "s/$(printf '\033')\[[0-9;]*m//g"; }
statusline() { # dir
  printf '{"workspace":{"current_dir":"%s","project_dir":"%s"},"cwd":"%s"}' "$1" "$1" "$1" | "$sl" 2>>"$tmp/sl.err" | strip_ansi
}
: > "$tmp/sl.err"
slr="$tmp/sl"; rm -rf "$slr"; mkdir -p "$slr"
git init -q --bare -b main "$slr/remote.git"
git clone -q "$slr/remote.git" "$slr/x" 2>/dev/null
slgit() { git -C "$slr/x" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
slgit symbolic-ref HEAD refs/heads/main   # independent of init.defaultBranch on this machine
slgit commit -q --allow-empty -m first
check_eq "statusline: no upstream yet -> repo on branch" "$(statusline "$slr/x")" "x on main"
slgit push -q -u origin main 2>/dev/null
check_eq "statusline: pushed -> repo on branch" "$(statusline "$slr/x")" "x on main"
slgit commit -q --allow-empty -m second
check_eq "statusline: ahead -> with unpushed" "$(statusline "$slr/x")" "x on main with unpushed"
mkdir -p "$slr/x/sub"
check_eq "statusline: subdirectory names the repo, not the dir" "$(statusline "$slr/x/sub")" "x on main with unpushed"
slgit checkout -q --detach
check_eq "statusline: detached -> short hash" "$(statusline "$slr/x")" "x on $(slgit rev-parse --short HEAD)"
mkdir -p "$slr/plain"
check_eq "statusline: outside a repo -> directory name" "$(statusline "$slr/plain")" "plain"
check_eq "statusline: no stderr noise across all calls" "$(wc -c < "$tmp/sl.err" | tr -d ' ')" "0"
check_eq "statusline: empty stdin -> cwd" "$(cd "$slr/plain" && printf '' | "$sl" 2>/dev/null | strip_ansi)" "plain"
dirty_out=$(touch "$slr/x/untracked" && printf '{"workspace":{"current_dir":"%s"}}' "$slr/x" | "$sl" 2>/dev/null)
case "$dirty_out" in *"$(printf '\033[1;31m')"*) pass "statusline: dirty tree colors branch red";; *) fail "statusline: dirty tree should color branch red";; esac
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: `FAIL missing .../claude-statusline`, `statusLine command: got 'null'`, and the `statusline:` output checks.

- [ ] **Step 3: Write the script**

Create `dot_local/bin/executable_claude-statusline`:

```sh
#!/bin/sh
# Claude Code status line: "<repo> on <branch> with unpushed", colored like the
# shell prompt. Claude Code pipes its session JSON on stdin; this reads the
# current directory from it and asks git the rest. Outside a repo it prints the
# directory name. Never prints to stderr, never exits non-zero.
set -u

dir=$(jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -n "$dir" ] && [ -d "$dir" ] || dir=$PWD

cyan='\033[1;36m'; green='\033[1;32m'; red='\033[1;31m'; magenta='\033[1;35m'; reset='\033[0m'

top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || {
  printf "${cyan}%s${reset}\n" "$(basename "$dir")"
  exit 0
}

branch=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null) ||
  branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)

if [ -z "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
  branch_color=$green
else
  branch_color=$red
fi

line=$(printf "${cyan}%s${reset} on ${branch_color}%s${reset}" "$(basename "$top")" "$branch")

ahead=$(git -C "$dir" rev-list --count '@{upstream}..HEAD' 2>/dev/null) || ahead=0
if [ "$ahead" -gt 0 ]; then
  line="$line with ${magenta}unpushed${reset}"
fi

printf '%b\n' "$line"
```

`printf '%b'` expands the `\033` sequences at the end, in one place. `rev-list` fails when the branch has no upstream, so `ahead` falls back to 0 and nothing is appended.

- [ ] **Step 4: Add the statusLine entry to the tracked settings**

```bash
tmpf=$(mktemp) && jq '. + {statusLine: {type: "command", command: "~/.local/bin/claude-statusline"}}' dot_claude/settings.json > "$tmpf" && mv "$tmpf" dot_claude/settings.json
jq -r '.statusLine' dot_claude/settings.json
```

Expected: the `statusLine` object printed back.

- [ ] **Step 5: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

- [ ] **Step 6: Commit**

```bash
git add dot_local/bin/executable_claude-statusline dot_claude/settings.json test/render.sh
git commit -m "Add a Claude Code status line showing repo, branch, and unpushed state

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: doctor checks

**Files:**
- Modify: `dot_local/bin/executable_dotfiles-doctor.tmpl`
- Test: `test/render.sh` (the `# Task 9: doctor` block)

**Interfaces:**
- Consumes: the Brewfile from Task 1, the managed config files from Tasks 2, 3, and 5, and the status line script from Task 6.

- [ ] **Step 1: Write the assertions**

Append to the `# Task 9: doctor` block in `test/render.sh`, before `finish`:

```sh
# Task 7 (2026-10-04): new doctor checks
d="$P/.local/bin/dotfiles-doctor"
check_fgrep "doctor: brew bundle check against the source Brewfile" "$d" "brew bundle check --file \"$SRC/Brewfile\" --no-upgrade"
check_grep "doctor: new tools on PATH" "$d" 'for t in rg fd fzf bat eza zoxide atuin starship xh delta difft lazygit git-absorb'
check_grep "doctor: chezmoi verify on managed config" "$d" 'chezmoi verify ~/.claude/settings.json ~/.config/zed/settings.json ~/.config/starship.toml ~/.config/atuin/config.toml'
check_grep "doctor: config drift is a warning" "$d" 'warn "managed config'
check_grep "doctor: statusLine wired" "$d" "jq -r '.statusLine.command // empty'"
check_grep "doctor: statusline runs" "$d" 'claude-statusline" 2>/dev/null'
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: six `doctor:` failures.

- [ ] **Step 3: Add the checks to the doctor template**

In `dot_local/bin/executable_dotfiles-doctor.tmpl`, insert the following block immediately before the line `echo "startup"`:

```sh
echo "brew"
if brew bundle check --file "{{ .chezmoi.sourceDir }}/Brewfile" --no-upgrade >"$tmp/bundle.out" 2>&1; then
  pass "Brewfile satisfied"
else
  fail "Brewfile not satisfied: $(grep -v -i 'satisfy' "$tmp/bundle.out" | tr '\n' ' ')"
fi
for t in rg fd fzf bat eza zoxide atuin starship xh delta difft lazygit git-absorb; do
  if command -v "$t" >/dev/null 2>&1; then pass "$t on PATH"; else fail "$t missing"; fi
done

echo "managed config"
if chezmoi verify ~/.claude/settings.json ~/.config/zed/settings.json ~/.config/starship.toml ~/.config/atuin/config.toml >/dev/null 2>&1; then
  pass "managed config matches source"
else
  warn "managed config drifted from source: chezmoi diff, then chezmoi re-add <file> or chezmoi apply"
fi

echo "claude status line"
check "settings.json statusLine command" "$(jq -r '.statusLine.command // empty' "$HOME/.claude/settings.json" 2>/dev/null)" "~/.local/bin/claude-statusline"
if [ -x "$HOME/.local/bin/claude-statusline" ]; then pass "claude-statusline executable"; else fail "claude-statusline missing or not executable"; fi
sl_out=$(printf '{"workspace":{"current_dir":"%s"}}' "$HOME/.dotfiles" | "$HOME/.local/bin/claude-statusline" 2>/dev/null)
case "$sl_out" in *dotfiles*" on "*) pass "claude-statusline prints repo and branch" ;; *) fail "claude-statusline output: '$sl_out'" ;; esac

```

Also update the header comment at the top of the template to mention the new areas:

```sh
# Verifies the live machine: git identity by remote, SSH keys, gh account,
# signing, PATH, Brewfile, managed config drift, the Claude Code status line,
# shell startup, and chezmoi freshness. Exit 1 on any failure.
```

- [ ] **Step 4: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`. The existing `doctor(personal): sh -n` and `doctor(work): sh -n` checks catch any shell syntax slip in the new block.

- [ ] **Step 5: Commit**

```bash
git add dot_local/bin/executable_dotfiles-doctor.tmpl test/render.sh
git commit -m "Doctor: check the Brewfile, managed config drift, and the status line

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: README and spec status

**Files:**
- Modify: `README.md`, `docs/superpowers/specs/2026-10-04-modern-cli-tools-design.md`
- Test: `test/render.sh` (the `# Task 8: install.sh and README` block)

- [ ] **Step 1: Write the assertions**

Append to the `# Task 8: install.sh and README` block in `test/render.sh`:

```sh
# Task 8 (2026-10-04): README covers the new tools
check_grep "README: cask adopt step" "$SRC/README.md" 'brew install --cask --adopt iterm2 zed'
check_grep "README: atuin import" "$SRC/README.md" 'atuin import auto'
check_grep "README: re-add after Claude edits settings" "$SRC/README.md" 'chezmoi re-add ~/.claude/settings.json'
check_grep "README: Nerd Font set by hand" "$SRC/README.md" 'JetBrains Mono Nerd Font'
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: four `README:` failures.

- [ ] **Step 3: Update the README**

In `README.md`, replace the `## Daily use` section with:

```markdown
## Daily use

- `chezmoi edit --apply ~/.zshrc`, or edit in `~/.dotfiles` and run `chezmoi apply`.
- `chezmoi re-add` after editing a managed file in place. Claude Code rewrites `~/.claude/settings.json` when you change permissions interactively, so run `chezmoi re-add ~/.claude/settings.json` afterwards or the next apply will undo it. `dotfiles-doctor` warns when the two differ.
- `dotfiles-doctor` checks identity, SSH, gh, signing, PATH, the Brewfile, managed config drift, the Claude Code status line, and startup time.
- `chezmoi upgrade` updates the chezmoi binary. Nothing else will.
- `./test/render.sh` renders both machine kinds into a temp dir and asserts on the result.

## Shell and git tools

The Brewfile installs fzf (Ctrl-T files, Alt-C directories), atuin (Ctrl-R history, local only, no sync), zoxide (`z dir`), bat (`cat` and man pages), eza (`ls`), ripgrep, fd, xh (`headers`), starship (the prompt), delta (git pager), difftastic (`git dft` or `dft`), lazygit (`lg`), and git-absorb. Each shell integration is skipped when its tool is absent, so a half-installed machine still gets a shell.

Casks: iTerm2, Zed, and JetBrains Mono Nerd Font. On a machine where iTerm2 or Zed is already in `/Applications`, run `brew install --cask --adopt iterm2 zed` once before `chezmoi apply`, because `brew bundle` will not install over an app it did not put there. Set iTerm2's font to JetBrains Mono Nerd Font by hand; iTerm2 preferences are not managed.

After the first apply on an existing machine, run `atuin import auto` once to load the old history file.

## Claude Code

`~/.claude/settings.json` is managed, and it points Claude Code's status line at `~/.local/bin/claude-statusline`, which shows the repo, the branch in green or red for clean or dirty, and `with unpushed` when ahead of upstream. Nothing else under `~/.claude` is managed; skills are an open question recorded in the spec.
```

- [ ] **Step 4: Mark the spec implemented**

In `docs/superpowers/specs/2026-10-04-modern-cli-tools-design.md`, change the `Status:` line to:

```
Status: implemented 2026-10-04 on the personal machine. Builds on `2026-10-01-chezmoi-dotfiles-design.md`, which still describes the repo's structure, identity scheme, and test harness. This document covers only what changes.
```

Also in `docs/superpowers/specs/2026-10-01-chezmoi-dotfiles-design.md`, in the `## Decisions already made` table, change the Node row to:

```
| Node | nvm, lazy-loaded, until the mise changeset described in `2026-10-04-modern-cli-tools-design.md`. |
```

and change the line `Casks are out of scope.` under Bootstrap to:

```
Casks were out of scope in this design; `2026-10-04-modern-cli-tools-design.md` adds three.
```

- [ ] **Step 5: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

- [ ] **Step 6: Commit**

```bash
git add README.md docs/superpowers/specs test/render.sh
git commit -m "Docs: describe the new tools, casks, and status line

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Rollout on this machine

This task changes the live machine: it installs around twenty formulae and three casks and rewrites the live shell config. **Stop and confirm with the user before Step 1.** Everything before this task was repo-only.

**Files:** none in the repo.

- [ ] **Step 1: Adopt the casks that already exist**

```bash
brew install --cask --adopt iterm2 zed
```

Expected: both report adopted or already installed. If brew says an app is not from a cask and refuses, stop and ask rather than deleting anything.

- [ ] **Step 2: Apply**

```bash
chezmoi apply -v
```

Expected: the homebrew run script fires because the Brewfile hash changed, `brew bundle` installs the new formulae and the font cask, then the new and changed files are written. This takes several minutes.

- [ ] **Step 3: Import history into atuin**

```bash
atuin import auto
```

Expected: a count of imported history lines.

- [ ] **Step 4: Open a new shell and verify by eye**

In a new terminal window:

```bash
cd ~/.dotfiles && git status
```

Expected: the prompt reads `in dotfiles on master` with the branch green and `›` on the next line. Ctrl-R opens atuin, Ctrl-T opens fzf, `ls` is eza output, `cat README.md` is highlighted, `git log -p -1` pages through delta.

- [ ] **Step 5: Run the doctor**

```bash
dotfiles-doctor
```

Expected: `all checks passed`, with startup still well under 0.3s. The `managed config` line may warn if Claude Code rewrote settings.json between apply and now; `chezmoi diff` shows what changed.

- [ ] **Step 6: Set the terminal font**

By hand, in iTerm2 preferences, set the profile font to JetBrains Mono Nerd Font so eza icons and any starship symbols render. Then open a Claude Code session in any repo and confirm the status line shows `<repo> on <branch>`.

- [ ] **Step 7: Nothing to commit**

The repo is unchanged by this task. If anything needed fixing to make the doctor pass, fix it in the repo, rerun `./test/render.sh`, and commit it with a message that names the fix.
