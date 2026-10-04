# Modern CLI Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the current baseline of shell and git CLI tools to the dotfiles, put Claude Code and Zed settings under chezmoi, and give Claude Code a status line that reads the same on every machine.

**Architecture:** Everything is additive to the existing chezmoi source tree at `~/.dotfiles`. The Brewfile grows. zsh gains two new files in its explicit source order: `tools.zsh` for third-party integrations, after `completion.zsh`, and `plugins.zsh` last for autosuggestions and syntax highlighting. The hand-drawn prompt is replaced by a starship config that reproduces it, and the gitconfig template gains delta and difftastic. `~/.claude/settings.json` and `~/.config/zed/settings.json` become templates that merge a shared file in the repo with a local file that never leaves the machine, and `dotfiles-capture` keeps changes the apps make in place. A POSIX sh script in `~/.local/bin` renders the status line. The doctor and the render test suite grow to cover all of it.

**Tech Stack:** chezmoi, zsh, POSIX sh, Homebrew, git 2.56, jq (Apple's, at `/usr/bin/jq`), starship, atuin.

**Spec:** `docs/superpowers/specs/2026-10-04-modern-cli-tools-design.md`

## Global Constraints

- Platform: macOS on Apple Silicon. Homebrew prefix is `/opt/homebrew`.
- Interactive shell startup stays under 0.3 seconds. The doctor measures it; the suite's `zsh: starts with no Homebrew` test must keep passing, so every new shell integration is guarded on its command or file existing.
- `~/.local/bin` is first on PATH, before `/opt/homebrew/bin`.
- Work identifiers never appear in the repo, this plan, or tests. Tests use `work@example.com` and `example-org`.
- Machine-specific Claude Code and Zed values live only in `~/.config/chezmoi/claude-settings.local.json` and `~/.config/chezmoi/zed-settings.local.json`, outside the source tree. Nothing in this plan copies them into the repo.
- Tests never write to the real `$HOME`. They render into a temp directory with `--destination` and `--persistent-state` pointed at temp paths, and with `HOME` pointed at a temp directory wherever a template reads from it. Only Task 10 changes the live machine, and it stops to confirm first. Task 5 reads the live settings files.
- Nothing under `~/.claude/skills/` enters the repo. Only `~/.claude/settings.json` is managed under `~/.claude/`.
- nvm stays. `nvm.zsh`, `brew "nvm"`, `brew "node"`, and `brew "yarn"` are removed by the later mise changeset, not this one.
- Casks in scope are exactly `iterm2`, `zed`, and `font-jetbrains-mono-nerd-font`.
- Zsh and sh files are plain files unless they need chezmoi data. The templates this plan creates or edits are the gitconfig, the doctor, and the two settings files.
- Commit after every task. Commit messages are one imperative sentence in the repo's existing style (`Add ...`, `Spec: ...`), then a blank line and the `Co-Authored-By` trailer your harness specifies for the model doing the work. The commit commands below leave the trailer out so that no model's name is hardcoded here; add yours.
- Run the whole suite with `./test/render.sh` from the repo root. It needs chezmoi, git, and the zsh and jq that macOS ships (`/usr/bin/jq` since macOS 15). Every task ends with the suite fully green.

## Review Focus

1. **Startup with nothing installed.** A fresh machine opens a shell after `install.sh` and possibly before `brew bundle` finishes. `tools.zsh`, `plugins.zsh`, `prompt.zsh`, `env.zsh`, and `aliases.zsh` must not error when the tools are absent. The existing `env -i` test pins this. `path.zsh` adds `/opt/homebrew/bin` even in that bare environment, so Task 2 proves the alias guards with stub tools rather than by assuming Homebrew is empty.
2. **Source order.** `path env options aliases git nvm prompt completion tools plugins`. `tools.zsh` comes after `completion.zsh` because zoxide registers its `z` completion only when compinit has already run. atuin's Ctrl-R wins because it comes after fzf inside `tools.zsh`. `plugins.zsh` is last because syntax highlighting wraps every ZLE widget defined before it. Task 2 pins the exact order string.
3. **Status line outside a repo, without an upstream, and beside Claude Code's own git.** `git rev-parse` fails outside a repo, and `@{upstream}` fails on a branch with no upstream. The script must print a sane line in both cases and never leak git's stderr. It also sets `GIT_OPTIONAL_LOCKS=0`, so its `git status` never holds `.git/index.lock` while Claude Code commits. Task 7 tests all three repo states.
4. **Work values never reach the public repo.** They live in local files outside the source tree. `chezmoi re-add` skips templates, and `dotfiles-capture --shared` refuses when chezmoi's `work` is true. Tasks 5 and 6.
5. **Capturing the right side.** chezmoi records a hash of what it last wrote. `dotfiles-capture` compares it with the live file and the rendered file, captures only what changed in place, and refuses to guess when both sides moved. Task 6 tests each case.
6. **The first apply on a machine that already has settings.** chezmoi overwrites a file it has never written without asking. A `run_once_before` script keeps `.pre-chezmoi` copies, and `dotfiles-capture --from` moves their values into the local file. Tasks 5, 6, and 10.
7. **Casks already present.** iTerm2 and Zed are in `/Applications` from manual downloads. `brew bundle` refuses to install over them, so Task 10 adopts them by hand first.

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
check_nogrep "Brewfile: no mise yet" "$P/Brewfile" '^brew "mise"'
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: `FAIL Brewfile: node` and the other new packages, taps, and casks, plus `Brewfile: exactly three casks`: 29 in all. Nothing else fails.

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
git commit -m "Add the shell, git, and app tooling to the Brewfile"
```

---

### Task 2: Shell integrations, aliases, and atuin config

**Files:**
- Create: `dot_config/zsh/tools.zsh`, `dot_config/zsh/plugins.zsh`, `dot_config/atuin/config.toml`
- Modify: `dot_config/zsh/dot_zshrc`, `dot_config/zsh/env.zsh`, `dot_config/zsh/aliases.zsh`, `dot_config/zsh/git.zsh`
- Delete: `dot_local/bin/executable_headers`
- Test: `test/render.sh` (the `# Task 5: zsh` and `# Task 6: bin and vimrc` blocks)

**Interfaces:**
- Produces: the source order `path env options aliases git nvm prompt completion tools plugins`. `tools.zsh` comes after `completion.zsh` because zoxide registers its `z` completion only when compinit has already run. Task 3 edits `prompt.zsh` in its slot.

- [ ] **Step 1: Update the zsh assertions**

In `test/render.sh`, in the `# Task 5: zsh` block, change the file loop and the order assertion:

```sh
for f in .zshrc path.zsh env.zsh options.zsh aliases.zsh git.zsh nvm.zsh tools.zsh prompt.zsh completion.zsh plugins.zsh; do
  check_file "$P/.config/zsh/$f"
  if zsh -n "$P/.config/zsh/$f" 2>/dev/null; then pass "zsh -n $f"; else fail "zsh -n $f: syntax error"; fi
done
```

```sh
check_grep "zshrc: explicit order" "$P/.config/zsh/.zshrc" 'for f in path env options aliases git nvm prompt completion tools plugins; do'
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
check_grep "git aliases: dft" "$P/.config/zsh/git.zsh" "alias dft='git dft'"
check_file "$P/.config/atuin/config.toml"
check_grep "atuin: sync off" "$P/.config/atuin/config.toml" '^auto_sync = false'
check_grep "atuin: no update check" "$P/.config/atuin/config.toml" '^update_check = false'
check_grep "atuin: directory filter on up arrow" "$P/.config/atuin/config.toml" '^filter_mode_shell_up_key_binding = "directory"'
# Each alias is guarded. With stub tools first on PATH the aliases appear. With
# the stubs gone they disappear, except for tools this machine's Homebrew really
# has, because path.zsh adds /opt/homebrew/bin whether or not it exists.
mkdir -p "$h/.local/bin"
for t in eza bat lazygit xh; do printf '#!/bin/sh\n' > "$h/.local/bin/$t"; chmod +x "$h/.local/bin/$t"; done
out=$(env -i HOME="$h" TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -i -c 'whence -w ls cat lg headers | tr "\n" " "' 2>&1)
check_eq "zsh: eza/bat/lazygit/xh aliases when the tools exist" "$out" "ls: alias cat: alias lg: alias headers: alias "
for t in eza bat lazygit xh; do rm -f "$h/.local/bin/$t"; done
want=""
for pair in ls:eza cat:bat lg:lazygit headers:xh; do
  a=${pair%%:*}; t=${pair#*:}
  if [ -x "/opt/homebrew/bin/$t" ]; then w=alias; elif [ "$a" = ls ] || [ "$a" = cat ]; then w=command; else w=none; fi
  want="$want$a: $w "
done
out=$(env -i HOME="$h" TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -i -c 'whence -w ls cat lg headers | tr "\n" " "' 2>&1)
check_eq "zsh: no eza/bat/lazygit/xh aliases when the tools are absent" "$out" "$want"
```

The last two assertions reuse `$h`, the Homebrew-free fake home built earlier in the block. `path.zsh` adds `/opt/homebrew/bin` even there, so a flat "no aliases" assertion would start failing once Task 10 installs the tools. Instead, stubs in `$h/.local/bin` prove each alias appears when its tool exists, and the second assertion expects an alias only for a tool this machine's Homebrew really has.

Note: the `# Task 5` block copies `$P/.config` into `$h` before running `env -i`. That copy happens above the new lines, so `tools.zsh` and `plugins.zsh` are present in `$h` when the no-Homebrew test runs.

In the `# Task 6: bin and vimrc` block, remove `headers` from the executable loop so it reads:

```sh
for s in git-all git-amend git-copy-branch-name git-credit git-delete-local-merged git-nuke git-promote git-rank-contributors git-review git-track git-undo git-unpushed git-unpushed-stat git-up git-wtf e todo macos-defaults; do
```

and add these after that loop's `done`:

```sh
check_nofile "$P/.local/bin/headers"
check_grep ".chezmoiremove: old headers script" "$SRC/.chezmoiremove" '^\.local/bin/headers$'
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: failures for `tools.zsh`, `plugins.zsh`, the order string, the eza aliases, `cat`, `lg`, `headers`, `dft`, `MANPAGER`, the atuin config, the stub-alias check, `should not exist .../headers`, and `.chezmoiremove`.

- [ ] **Step 3: Write `tools.zsh`**

Create `dot_config/zsh/tools.zsh`:

```zsh
# Third-party shell integrations. Each block is skipped when its tool is
# absent, so a shell opened before `brew bundle` finishes still starts clean.
# Sourced after completion.zsh: zoxide registers its completion only when
# compinit has already run.

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
for f in path env options aliases git nvm prompt completion tools plugins; do
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

Append to `dot_config/zsh/git.zsh`. It calls the `dft` git alias that Task 4 adds; plain `git difftool` would run git's default tool, not difftastic:

```zsh
alias dft='git dft'
```

- [ ] **Step 9: Delete the headers script, have chezmoi remove the installed copy, and write the atuin config**

```bash
git rm -q dot_local/bin/executable_headers
mkdir -p dot_config/atuin
```

chezmoi does not delete a file it stops managing, so `~/.local/bin/headers` would survive the apply. Create `.chezmoiremove`:

```
# chezmoi does not delete files it stops managing; these it removes on apply.
.local/bin/headers
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
git add dot_config/zsh dot_config/atuin .chezmoiremove test/render.sh
git commit -m "Add fzf, zoxide, atuin, bat, eza, xh, and zsh plugins to the shell"
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
```

The existing `zsh: starts with no Homebrew` test already covers a shell without starship.

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: nine failures: `FAIL missing .../.config/starship.toml`, the five `starship:` checks on that file, `starship: guarded init`, and the two `prompt:` negatives.

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
git commit -m "Draw the prompt with starship"
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
git commit -m "Page git through delta and add difftastic as a difftool"
```

---

### Task 5: Claude Code and Zed settings from a shared file and a local file

**Files:**
- Create: `.chezmoitemplates/claude-settings.json`, `.chezmoitemplates/zed-settings.json`, `dot_claude/settings.json.tmpl`, `dot_config/zed/private_settings.json.tmpl`, `run_once_before_20-settings-backup.sh`
- Test: `test/render.sh` (`render()` and a new block above `# Task 9: doctor`)

**Interfaces:**
- Produces: the shared files, which Task 6's `dotfiles-capture --shared` writes and Task 7 adds `statusLine` to. The local-file paths `~/.config/chezmoi/claude-settings.local.json` and `~/.config/chezmoi/zed-settings.local.json`, which the templates read and Task 6 writes. The `.pre-chezmoi` backups, which Task 6's `--from` and the README use.

Both apps rewrite these files in place. The work machine needs values a public repo must not hold: Claude Code's `autoMode.environment` is free text describing the machine. And chezmoi overwrites a file it has never written without asking. So each file is rendered from a shared file in the repo plus a local file in `~/.config/chezmoi`, next to `chezmoi.toml`, that is never committed. Maps merge key by key and the local file wins. Claude Code's four `permissions` lists are unioned instead, which is how Claude Code merges lists across its own settings files. Because both targets are templates, `chezmoi re-add` skips them, so that route from the work machine into the repo is closed.

- [ ] **Step 1: Give `render()` its own home**

The templates find the local file through `.chezmoi.homeDir`. Without this, the suite would read the real `~/.config/chezmoi`. In `test/render.sh`, change `render()` to:

```sh
render() { # fixture-name
  mkdir -p "$tmp/$1" "$tmp/$1-home"
  HOME="$tmp/$1-home" chezmoi --config "$SRC/test/fixtures/$1.toml" \
          --source "$SRC" \
          --destination "$tmp/$1" \
          --persistent-state "$tmp/$1.boltdb" \
          --exclude scripts \
          apply || fail "chezmoi apply ($1) exited non-zero"
}
```

- [ ] **Step 2: Write the assertions**

Append to `test/render.sh` just above `# Task 9: doctor`:

```sh
# Task 5 (2026-10-04): Claude Code and Zed settings
check_nofile "$P/.chezmoitemplates"
cshared="$SRC/.chezmoitemplates/claude-settings.json"
zshared="$SRC/.chezmoitemplates/zed-settings.json"
for t in personal work; do
  c="$tmp/$t/.claude/settings.json"; z="$tmp/$t/.config/zed/settings.json"
  check_file "$c"
  check_file "$z"
  check_eq "claude settings($t): the shared file when there is no local file" "$(jq -S . "$c" 2>&1)" "$(jq -S . "$cshared" 2>&1)"
  check_eq "zed settings($t): the shared file when there is no local file" "$(jq -S . "$z" 2>&1)" "$(jq -S . "$zshared" 2>&1)"
  check_mode "zed settings($t): 0600" "$z" "600"
  check_eq "claude settings($t): only settings.json under .claude" "$(find "$tmp/$t/.claude" -type f | sed "s|$tmp/$t/.claude/||" | sort | tr '\n' ' ')" "settings.json "
done
check_eq "claude shared: no machine description" "$(jq 'has("autoMode")' "$cshared")" "false"
check_eq "claude shared: no credential-like keys" "$(jq -r '[paths(scalars) | map(tostring) | join(".")] | .[]' "$cshared" | grep -c -i -E 'token|credential|apikey|secret|password')" "0"
# A local file in ~/.config/chezmoi is merged over the shared one.
oh="$tmp/overlay-home"; mkdir -p "$oh/.config/chezmoi"
printf '{"autoMode":{"environment":"LOCAL"},"theme":"local-theme","permissions":{"allow":["Bash(local:*)","Bash(local:*)"],"deny":["Read(.env)"]}}\n' > "$oh/.config/chezmoi/claude-settings.local.json"
printf '// Zed allows comments\n{"base_keymap": "local-keymap", "local_only": {"x": 1},}\n' > "$oh/.config/chezmoi/zed-settings.local.json"
overlay() { HOME="$oh" chezmoi --config "$SRC/test/fixtures/work.toml" --source "$SRC" --persistent-state "$tmp/overlay.boltdb" execute-template < "$SRC/$1"; }
oc=$(overlay dot_claude/settings.json.tmpl)
check_eq "claude overlay: local value wins" "$(printf '%s' "$oc" | jq -r .theme)" "local-theme"
check_eq "claude overlay: local-only key" "$(printf '%s' "$oc" | jq -r .autoMode.environment)" "LOCAL"
check_eq "claude overlay: shared keys kept" "$(printf '%s' "$oc" | jq -S 'del(.theme, .autoMode, .permissions)')" "$(jq -S 'del(.theme, .permissions)' "$cshared")"
check_eq "claude overlay: allow lists unioned, no duplicates" "$(printf '%s' "$oc" | jq -c .permissions.allow)" "$(jq -c '(.permissions.allow // []) + ["Bash(local:*)"]' "$cshared")"
check_eq "claude overlay: deny from the local file" "$(printf '%s' "$oc" | jq -c .permissions.deny)" '["Read(.env)"]'
oz=$(overlay dot_config/zed/private_settings.json.tmpl)
check_eq "zed overlay: local value wins, comments allowed" "$(printf '%s' "$oz" | jq -r .base_keymap)" "local-keymap"
check_eq "zed overlay: local-only key" "$(printf '%s' "$oz" | jq -c .local_only)" '{"x":1}'
check_eq "zed overlay: shared keys kept" "$(printf '%s' "$oz" | jq -S 'del(.base_keymap, .local_only)')" "$(jq -S 'del(.base_keymap)' "$zshared")"
# The first apply on a machine replaces these files, so a run_once script keeps the originals.
bk="$SRC/run_once_before_20-settings-backup.sh"
if sh -n "$bk"; then pass "backup script: sh -n"; else fail "backup script: syntax"; fi
bh="$tmp/backup-home"; mkdir -p "$bh/.claude"
echo '{"a":1}' > "$bh/.claude/settings.json"
HOME="$bh" sh "$bk" >/dev/null
check_eq "backup: existing claude settings copied" "$(cat "$bh/.claude/settings.json.pre-chezmoi" 2>&1)" '{"a":1}'
check_nofile "$bh/.config/zed/settings.json.pre-chezmoi"
echo '{"a":2}' > "$bh/.claude/settings.json"; HOME="$bh" sh "$bk" >/dev/null
check_eq "backup: an earlier backup is never overwritten" "$(cat "$bh/.claude/settings.json.pre-chezmoi")" '{"a":1}'
```

- [ ] **Step 3: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: 21 failures: the missing settings files in both trees, the overlay checks, and the backup script.

- [ ] **Step 4: Build the shared files from this machine's settings**

```bash
mkdir -p .chezmoitemplates
jq -S 'del(.autoMode)' ~/.claude/settings.json > .chezmoitemplates/claude-settings.json
F="$HOME/.config/zed/settings.json" chezmoi execute-template '{{ include (env "F") | fromJsonc | toJson }}' | jq -S . > .chezmoitemplates/zed-settings.json
```

`autoMode` stays out of the shared file because it describes this machine; Task 10 moves it into the local file. chezmoi parses Zed's comments and trailing commas, which jq cannot. The comments are dropped here, once, and Zed reads plain JSON fine.

- [ ] **Step 5: Review the shared files for anything that must not be committed**

```bash
jq -r 'keys[]' .chezmoitemplates/claude-settings.json | tr '\n' ' '; echo
jq -r 'keys[]' .chezmoitemplates/zed-settings.json | tr '\n' ' '; echo
grep -n -i -E 'token|secret|password|api[_-]?key' .chezmoitemplates/*.json || echo "clean"
```

Expected: Claude Code keys `agentPushNotifEnabled enabledPlugins extraKnownMarketplaces model modelSettings theme`, Zed keys `agent agent_servers base_keymap buffer_font_size session theme ui_font_size`, and `clean`. If a key or value looks like a credential, or names a work org, host, or repo, stop and ask; do not commit it.

- [ ] **Step 6: Write the templates**

Create `dot_claude/settings.json.tmpl`:

```
{{- /*
  Shared settings from .chezmoitemplates/claude-settings.json, overlaid with
  this machine's ~/.config/chezmoi/claude-settings.local.json, which is never
  committed. Permission lists are unioned, the way Claude Code merges lists
  across settings files; every other key in the local file wins outright.
  dotfiles-capture writes the local file; see its header.
*/ -}}
{{- $s := include ".chezmoitemplates/claude-settings.json" | fromJsonc -}}
{{- $localPath := joinPath .chezmoi.homeDir ".config/chezmoi/claude-settings.local.json" -}}
{{- if stat $localPath -}}
{{-   $l := include $localPath | fromJsonc -}}
{{-   $lists := dict -}}
{{-   range $k := list "allow" "ask" "deny" "additionalDirectories" -}}
{{-     $u := concat (dig "permissions" $k (list) $s) (dig "permissions" $k (list) $l) | uniq -}}
{{-     if $u -}}{{- $_ := set $lists $k $u -}}{{- end -}}
{{-   end -}}
{{-   $s = mergeOverwrite $s $l -}}
{{-   if $lists -}}{{- $_ := set $s "permissions" (mergeOverwrite (dig "permissions" dict $s) $lists) -}}{{- end -}}
{{- end -}}
{{ toPrettyJson "  " $s -}}
```

Create `dot_config/zed/private_settings.json.tmpl`. The `private_` prefix keeps the live file at 0600, as Zed created it:

```
{{- /*
  Shared settings from .chezmoitemplates/zed-settings.json, overlaid with this
  machine's ~/.config/chezmoi/zed-settings.local.json, which is never
  committed. Keys in the local file win. dotfiles-capture writes the local file.
*/ -}}
{{- $s := include ".chezmoitemplates/zed-settings.json" | fromJsonc -}}
{{- $localPath := joinPath .chezmoi.homeDir ".config/chezmoi/zed-settings.local.json" -}}
{{- if stat $localPath -}}
{{-   $s = mergeOverwrite $s (include $localPath | fromJsonc) -}}
{{- end -}}
{{ toPrettyJson "  " $s -}}
```

- [ ] **Step 7: Write the backup script**

Create `run_once_before_20-settings-backup.sh`:

```sh
#!/bin/sh
# Before chezmoi first writes the Claude Code and Zed settings on this machine,
# keep whatever is there. dotfiles-capture --from seeds the local files from
# these backups; see the README.
set -eu
for f in "$HOME/.claude/settings.json" "$HOME/.config/zed/settings.json"; do
  if [ -f "$f" ] && [ ! -e "$f.pre-chezmoi" ]; then
    cp -p "$f" "$f.pre-chezmoi"
    echo "Backed up $f to $f.pre-chezmoi"
  fi
done
```

- [ ] **Step 8: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

- [ ] **Step 9: Commit**

```bash
git add .chezmoitemplates dot_claude dot_config/zed run_once_before_20-settings-backup.sh test/render.sh
git commit -m "Render Claude Code and Zed settings from a shared file and a local one"
```

---

### Task 6: dotfiles-capture

**Files:**
- Create: `dot_local/bin/executable_dotfiles-capture`
- Test: `test/render.sh`

**Interfaces:**
- Consumes: the shared files, local-file paths, templates, and backup script from Task 5.
- Produces: `dotfiles-capture [--check] [--shared] [--from FILE] claude|zed [KEY...]`. Task 8's doctor runs `--check`; the README and Task 10 use the rest.

What it does:
- **Default:** copies every top-level key that differs from what chezmoi would write into the local file, or only the named KEYs.
- **`--shared`:** moves those keys into the shared file and out of the local one. Refused when chezmoi's `work` is true.
- **`--from FILE`:** reads the values from FILE instead of the live file, then applies the target.
- **`--check`:** changes nothing; lists the differing keys, says which side moved, and exits 1.
- **Which side moved:** chezmoi records a SHA-256 of what it last wrote. The script compares that with the live file and the rendered file. If only the repo side moved, it captures nothing and says to apply. If both moved, it refuses unless KEYs are named.
- **Afterwards:** when the rendered file matches the live file, it rewrites the live file in chezmoi's layout with `chezmoi apply --force` on that one target, so the doctor stays quiet. Keys removed in place are reported, never captured.

- [ ] **Step 1: Write the assertions**

Append to `test/render.sh` directly after the Task 5 block:

```sh
# Task 6 (2026-10-04): dotfiles-capture
cap="$P/.local/bin/dotfiles-capture"
check_file "$cap"
[ -x "$cap" ] && pass "capture: executable" || fail "capture: not executable"
sh -n "$cap" && pass "capture: sh -n" || fail "capture: syntax"
# A scratch copy of the source, because --shared writes to it, and a chezmoi
# wrapper that points every call at that copy and at a fake home.
cs="$tmp/capture-src"; mkdir -p "$cs"; (cd "$SRC" && tar --exclude .git -cf - .) | (cd "$cs" && tar -xf -)
cb="$tmp/capture-bin"; mkdir -p "$cb"
use_machine() { # fixture-name; sets $ch, the fake home
  ch="$tmp/capture-$1"; mkdir -p "$ch"
  printf '#!/bin/sh\nexec "%s" --config "%s" --source "%s" --destination "%s" --persistent-state "%s" "$@"\n' \
    "$(command -v chezmoi)" "$SRC/test/fixtures/$1.toml" "$cs" "$ch" "$tmp/capture-$1.boltdb" > "$cb/chezmoi"
  chmod +x "$cb/chezmoi"
}
capture() { HOME="$ch" PATH="$cb:$PATH" "$cap" "$@" 2>&1; }
cz() { HOME="$ch" PATH="$cb:$PATH" chezmoi "$@"; }
setjson() { jq "$2" "$1" > "$tmp/setjson" && cat "$tmp/setjson" > "$1"; }
cl() { jq -r "$1" "$ch/.config/chezmoi/claude-settings.local.json" 2>&1; }
zl() { jq -r "$1" "$ch/.config/chezmoi/zed-settings.local.json" 2>&1; }

use_machine work
mkdir -p "$ch/.claude"
printf '{"model":"work-model","autoMode":{"environment":"WORK"},"permissions":{"allow":["Bash(worktool:*)"]}}\n' > "$ch/.claude/settings.json"
capture claude >/dev/null; rc=$?
check_eq "capture: refused before chezmoi has written the file" "$rc" "1"
HOME="$ch" sh "$SRC/run_once_before_20-settings-backup.sh" >/dev/null
cz apply --force "$ch/.claude/settings.json"
capture --from "$ch/.claude/settings.json.pre-chezmoi" claude >/dev/null; rc=$?
check_eq "capture --from backup: exit 0" "$rc" "0"
check_eq "capture --from backup: work values seeded into the local file" "$(cl '.model + " " + .autoMode.environment')" "work-model WORK"
check_mode "capture: local file is 0600" "$ch/.config/chezmoi/claude-settings.local.json" "600"
capture --check claude >/dev/null; rc=$?
check_eq "capture --from backup: live file matches the repo afterwards" "$rc" "0"

setjson "$ch/.claude/settings.json" '.spinnerTipsEnabled = false'
out=$(capture --check claude); rc=$?
check_eq "capture --check: in-place change exits 1" "$rc" "1"
case "$out" in *"changed in place"*spinnerTipsEnabled*) pass "capture --check: names the side and the key";; *) fail "capture --check: got '$out'";; esac
before=$(cat "$cs/.chezmoitemplates/claude-settings.json")
capture --shared claude >/dev/null; rc=$?
check_eq "capture --shared: refused on a work machine" "$rc" "1"
check_eq "capture --shared: shared file untouched on a work machine" "$(cat "$cs/.chezmoitemplates/claude-settings.json")" "$before"
capture claude >/dev/null; rc=$?
check_eq "capture: exit 0" "$rc" "0"
check_eq "capture: in-place key lands in the local file" "$(cl .spinnerTipsEnabled)" "false"
capture --check claude >/dev/null; rc=$?
check_eq "capture: live file matches the repo afterwards" "$rc" "0"

setjson "$cs/.chezmoitemplates/claude-settings.json" '.effortLevel = "high"'
out=$(capture claude)
case "$out" in *"nothing changed in place"*) pass "capture: a repo-side change is not captured";; *) fail "capture: repo-side change: got '$out'";; esac
setjson "$ch/.claude/settings.json" '.theme = "in-place"'
capture claude >/dev/null; rc=$?
check_eq "capture: both sides changed and no KEY -> refused" "$rc" "1"
capture claude theme >/dev/null
check_eq "capture KEY: the named key is captured" "$(cl .theme)" "in-place"
check_eq "capture KEY: the repo-side key is not" "$(cl 'has("effortLevel")')" "false"
cz apply --force "$ch/.claude/settings.json"
setjson "$ch/.claude/settings.json" 'del(.theme)'
out=$(capture claude)
case "$out" in *"removed in place"*theme*) pass "capture: a key removed in place is reported";; *) fail "capture: removed key: got '$out'";; esac

use_machine personal
mkdir -p "$ch/.config/zed"
printf '// Zed settings\n{\n  "vim_mode": true, // trailing comma next\n}\n' > "$ch/.config/zed/settings.json"
capture --from "$ch/.config/zed/settings.json" zed >/dev/null; rc=$?
check_eq "capture zed --from the live file before the first apply: exit 0" "$rc" "0"
check_eq "capture zed: JSONC value seeded" "$(zl .vim_mode)" "true"
check_mode "capture zed: live file written 0600" "$ch/.config/zed/settings.json" "600"
setjson "$ch/.config/zed/settings.json" '.ui_font_size = 21'
capture zed >/dev/null
check_eq "capture zed: in-place key into the local file" "$(zl .ui_font_size)" "21"
setjson "$ch/.config/zed/settings.json" '.ui_font_size = 22'
capture --shared zed >/dev/null; rc=$?
check_eq "capture --shared on personal: exit 0" "$rc" "0"
check_eq "capture --shared: the key moves to the shared file" "$(jq -r .ui_font_size "$cs/.chezmoitemplates/zed-settings.json")" "22"
check_eq "capture --shared: and out of the local file" "$(zl 'has("ui_font_size")')" "false"
capture --check zed >/dev/null; rc=$?
check_eq "capture --shared: live file matches the repo afterwards" "$rc" "0"
```

The tests run the script against a copy of the source and a fake home. A wrapper named `chezmoi`, first on PATH, adds `--config`, `--source`, `--destination`, and `--persistent-state` to every call the script makes.

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: 27 failures, all `capture`, because the script does not exist yet.

- [ ] **Step 3: Write the script**

Create `dot_local/bin/executable_dotfiles-capture`:

```sh
#!/bin/sh
# Keeps settings that Claude Code or Zed changed in place. Each file is
# rendered from a shared file in the repo plus a local file in
# ~/.config/chezmoi that is never committed.
#
#   dotfiles-capture [--check] [--shared] [--from FILE] claude|zed [KEY...]
#
# Copies the top-level keys that differ from what chezmoi would write into the
# local file, so nothing reaches the repo. With KEYs, copies only those.
#   --shared  move the keys into the shared file instead. Refused on a work
#             machine, because the repo is public.
#   --from    read values from FILE instead of the live file, to seed the local
#             file from the .pre-chezmoi backup taken on the first apply.
#   --check   change nothing; list differing keys and exit 1 if there are any.
#
# chezmoi records a hash of what it last wrote. When the repo side has changed
# since then too, a difference could be either side's, so without KEYs the
# capture is refused rather than guessing.
set -eu

usage() { echo "usage: dotfiles-capture [--check] [--shared] [--from FILE] claude|zed [KEY...]" >&2; exit 2; }
check=false shared=false from=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=true ;;
    --shared) shared=true ;;
    --from) [ $# -ge 2 ] || usage; from=$2; shift ;;
    -*) usage ;;
    *) break ;;
  esac
  shift
done
[ $# -ge 1 ] || usage
case "$1" in
  claude) target="$HOME/.claude/settings.json" ;;
  zed) target="$HOME/.config/zed/settings.json" ;;
  *) usage ;;
esac
name=$1; shift
local_file="$HOME/.config/chezmoi/$name-settings.local.json"
shared_file="$(chezmoi source-path)/.chezmoitemplates/$name-settings.json"
src=${from:-$target}
[ -f "$src" ] || { echo "dotfiles-capture: $src does not exist" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Zed allows comments and trailing commas. chezmoi parses those; jq does not.
parse() { F="$1" chezmoi execute-template '{{ include (env "F") | fromJsonc | toJson }}' | jq -S .; }
render() { chezmoi cat "$target" > "$tmp/rendered.raw"; jq -S . "$tmp/rendered.raw" > "$tmp/rendered.json"; }
differing() { # top-level keys present in the source whose value differs from rendered
  jq -r -n --slurpfile l "$tmp/live.json" --slurpfile r "$tmp/rendered.json" \
    '$l[0] as $l | $r[0] as $r | $l | keys[] | select($l[.] != $r[.])'
}
removed() { # top-level keys rendered but absent from the source
  jq -r -n --slurpfile l "$tmp/live.json" --slurpfile r "$tmp/rendered.json" \
    '$l[0] as $l | $r[0] as $r | $r | keys[] | select(. as $k | $l | has($k) | not)'
}
words() { tr '\n' ' ' | sed 's/ $//'; }
sha() { shasum -a 256 "$1" | cut -c1-64; }

parse "$src" > "$tmp/live.json"
render
changed=$(differing)
gone=$(removed)
last=$(chezmoi state get --bucket=entryState --key="$target" | jq -r '.contentsSHA256 // empty')
live_moved=true repo_moved=true
if [ -n "$last" ]; then
  [ -f "$target" ] && [ "$(sha "$target")" = "$last" ] && live_moved=false
  [ "$(sha "$tmp/rendered.raw")" = "$last" ] && repo_moved=false
fi

if $check; then
  [ -z "$changed$gone" ] && exit 0
  if ! $live_moved; then hint="the repo changed: chezmoi apply $target"
  elif ! $repo_moved; then hint="changed in place: dotfiles-capture $name"
  else hint="both changed: dotfiles-capture $name KEY... for the keys changed in place"; fi
  echo "$name settings differ from the repo ($hint): $(printf '%s\n' "$changed" "$gone" | sed '/^$/d' | words)"
  exit 1
fi

if [ $# -gt 0 ]; then
  keys=$(printf '%s\n' "$@")
elif [ -n "$from" ]; then
  keys=$changed
elif [ -z "$last" ]; then
  echo "dotfiles-capture: chezmoi has not written $target yet. Keep its values with dotfiles-capture --from $target $name, or run chezmoi apply, which backs it up to $target.pre-chezmoi first." >&2
  exit 1
elif ! $live_moved; then
  echo "$name: nothing changed in place. Any difference comes from the repo: chezmoi apply $target"
  exit 0
elif $repo_moved; then
  echo "dotfiles-capture: both the live file and the repo changed since the last apply, so these could be either: $(echo "$changed" | words). Name the keys you changed in place: dotfiles-capture $name KEY..." >&2
  exit 1
else
  keys=$changed
fi
if [ -z "$keys" ]; then
  [ -n "$gone" ] && echo "$name: removed in place, delete by hand from $shared_file or $local_file: $(echo "$gone" | words)"
  echo "$name: nothing to capture"
  exit 0
fi

printf '%s\n' "$keys" | jq -R . | jq -s . > "$tmp/keys.json"
jq --slurpfile k "$tmp/keys.json" 'with_entries(select(.key | IN($k[0][])))' "$tmp/live.json" > "$tmp/delta.json"
if [ -f "$local_file" ]; then parse "$local_file" > "$tmp/local.json"; else echo '{}' > "$tmp/local.json"; fi

if $shared; then
  if [ "$(chezmoi execute-template '{{ .work }}')" = true ]; then
    echo "dotfiles-capture: --shared is refused on a work machine; the repo is public. Nothing captured." >&2
    exit 1
  fi
  jq -s '.[0] + .[1]' "$shared_file" "$tmp/delta.json" > "$tmp/shared.new"
  cat "$tmp/shared.new" > "$shared_file"
  # The shared file owns these keys now; a local copy would shadow them.
  if [ -f "$local_file" ]; then
    jq --slurpfile k "$tmp/keys.json" 'with_entries(select(.key | IN($k[0][]) | not))' "$tmp/local.json" > "$tmp/local.new"
    cat "$tmp/local.new" > "$local_file"
  fi
  dest="$shared_file (commit it in the repo)"
else
  mkdir -p "$(dirname "$local_file")"
  jq -S -s '.[0] + .[1]' "$tmp/local.json" "$tmp/delta.json" > "$tmp/local.new"
  (umask 077 && cat "$tmp/local.new" > "$local_file")
  dest=$local_file
fi
echo "$name: captured $(echo "$keys" | words) into $dest"
[ -z "$from" ] && [ -n "$gone" ] && echo "$name: removed in place, delete by hand from $shared_file or $local_file: $(echo "$gone" | words)"

render
if [ -n "$from" ]; then
  chezmoi apply "$target"
  exit 0
fi
still=$(differing)
if [ -z "$still$gone" ]; then
  # Same content as the live file, in chezmoi's layout, so the doctor stays quiet.
  chezmoi apply --force "$target"
else
  echo "$name: still differs from the repo: $(printf '%s\n' "$still" "$gone" | sed '/^$/d' | words). Review with chezmoi diff $target." >&2
  exit 1
fi
```

- [ ] **Step 4: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

- [ ] **Step 5: Commit**

```bash
git add dot_local/bin/executable_dotfiles-capture test/render.sh
git commit -m "Add dotfiles-capture to keep settings that Claude Code and Zed change in place"
```

---

### Task 7: Claude Code status line

**Files:**
- Create: `dot_local/bin/executable_claude-statusline`
- Modify: `.chezmoitemplates/claude-settings.json`
- Test: `test/render.sh`

**Interfaces:**
- Consumes: the shared Claude Code settings from Task 5.
- Produces: `~/.local/bin/claude-statusline`, which reads Claude Code's session JSON on stdin and prints one line: `<repo> on <branch>`, plus ` with unpushed` when ahead of upstream, or the directory basename outside a repo. Task 8's doctor runs it.

- [ ] **Step 1: Write the assertions**

Append to `test/render.sh` directly after the Task 6 block:

```sh
# Task 7 (2026-10-04): Claude Code status line
sl="$P/.local/bin/claude-statusline"
check_file "$sl"
[ -x "$sl" ] && pass "statusline: executable" || fail "statusline: not executable"
sh -n "$sl" && pass "statusline: sh -n" || fail "statusline: syntax"
check_grep "statusline: never takes git's index lock" "$sl" '^export GIT_OPTIONAL_LOCKS=0$'
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
Expected: 15 failures: the missing script, `statusLine command: got 'null'`, and the `statusline:` output checks.

- [ ] **Step 3: Write the script**

Create `dot_local/bin/executable_claude-statusline`:

```sh
#!/bin/sh
# Claude Code status line: "<repo> on <branch> with unpushed", colored like the
# shell prompt. Claude Code pipes its session JSON on stdin; this reads the
# current directory from it and asks git the rest. Outside a repo it prints the
# directory name. Never prints to stderr, never exits non-zero.
set -u
# Claude Code runs this while its own git commands run. Without this, git status
# can hold .git/index.lock just long enough to make one of them fail.
export GIT_OPTIONAL_LOCKS=0

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

`printf '%b'` expands the `\033` sequences that are still literal. `rev-list` fails when the branch has no upstream, so `ahead` falls back to 0 and nothing is appended. `GIT_OPTIONAL_LOCKS=0` stops `git status` from refreshing the index, which takes `.git/index.lock`; Claude Code runs this script while its own git commands run.

- [ ] **Step 4: Add the statusLine entry to the shared settings**

```bash
f=.chezmoitemplates/claude-settings.json; tmpf=$(mktemp)
jq -S '. + {statusLine: {type: "command", command: "~/.local/bin/claude-statusline"}}' "$f" > "$tmpf" && cat "$tmpf" > "$f" && rm "$tmpf"
jq -r '.statusLine' "$f"
```

Expected: the `statusLine` object printed back.

- [ ] **Step 5: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

- [ ] **Step 6: Commit**

```bash
git add dot_local/bin/executable_claude-statusline .chezmoitemplates/claude-settings.json test/render.sh
git commit -m "Add a Claude Code status line showing repo, branch, and unpushed state"
```

---

### Task 8: doctor checks

**Files:**
- Modify: `dot_local/bin/executable_dotfiles-doctor.tmpl`
- Test: `test/render.sh` (the `# Task 9: doctor` block)

**Interfaces:**
- Consumes: the Brewfile from Task 1, the starship and atuin config from Tasks 2 and 3, `dotfiles-capture` from Task 6, and the status line from Task 7.

- [ ] **Step 1: Write the assertions**

Append to the `# Task 9: doctor` block in `test/render.sh`, before `finish`:

```sh
# Task 8 (2026-10-04): new doctor checks
d="$P/.local/bin/dotfiles-doctor"
check_fgrep "doctor: brew bundle check lists what is missing" "$d" "brew bundle check --file \"$SRC/Brewfile\" --no-upgrade --verbose"
check_grep "doctor: new tools on PATH" "$d" 'for t in rg fd fzf bat eza zoxide atuin starship xh delta difft lazygit git-absorb'
check_grep "doctor: chezmoi verify on starship and atuin" "$d" 'chezmoi verify ~/.config/starship.toml ~/.config/atuin/config.toml'
check_grep "doctor: settings drift through dotfiles-capture" "$d" 'dotfiles-capture" --check "\$app"'
check_grep "doctor: settings drift is a warning" "$d" 'warn "\$out"'
check_grep "doctor: statusLine wired" "$d" "jq -r '.statusLine.command // empty'"
check_grep "doctor: statusline runs" "$d" 'claude-statusline" 2>/dev/null'
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: seven `doctor:` failures.

- [ ] **Step 3: Add the checks to the doctor template**

In `dot_local/bin/executable_dotfiles-doctor.tmpl`, insert the following block immediately before the line `echo "startup"`:

```sh
echo "brew"
if brew bundle check --file "{{ .chezmoi.sourceDir }}/Brewfile" --no-upgrade --verbose >"$tmp/bundle.out" 2>&1; then
  pass "Brewfile satisfied"
else
  fail "Brewfile not satisfied: $(sed -n 's/^→ //p' "$tmp/bundle.out" | tr '\n' ' ')"
fi
for t in rg fd fzf bat eza zoxide atuin starship xh delta difft lazygit git-absorb; do
  if command -v "$t" >/dev/null 2>&1; then pass "$t on PATH"; else fail "$t missing"; fi
done

echo "managed config"
if chezmoi verify ~/.config/starship.toml ~/.config/atuin/config.toml >/dev/null 2>&1; then
  pass "starship and atuin config match source"
else
  warn "starship or atuin config drifted: chezmoi diff, then chezmoi re-add <file> or chezmoi apply"
fi
for app in claude zed; do
  if out=$("$HOME/.local/bin/dotfiles-capture" --check "$app" 2>&1); then pass "$app settings match source"; else warn "$out"; fi
done

echo "claude status line"
check "settings.json statusLine command" "$(jq -r '.statusLine.command // empty' "$HOME/.claude/settings.json" 2>/dev/null)" "~/.local/bin/claude-statusline"
if [ -x "$HOME/.local/bin/claude-statusline" ]; then pass "claude-statusline executable"; else fail "claude-statusline missing or not executable"; fi
sl_out=$(printf '{"workspace":{"current_dir":"%s"}}' "$HOME/.dotfiles" | "$HOME/.local/bin/claude-statusline" 2>/dev/null)
case "$sl_out" in *dotfiles*" on "*) pass "claude-statusline prints repo and branch" ;; *) fail "claude-statusline output: '$sl_out'" ;; esac
```

`--verbose` makes `brew bundle check` list each missing formula on a line starting with `→`; without it, the output only says to rerun with `--verbose`. Drift in the two app settings files is a warning, because the apps change them on purpose; the message names the command to run.

Also update the header comment at the top of the template:

```sh
# Verifies the live machine: git identity by remote, SSH keys, gh account,
# signing, PATH, the Brewfile, config drift, the Claude Code status line,
# shell startup, and chezmoi freshness. Exit 1 on any failure.
```

- [ ] **Step 4: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`. The existing `doctor(personal): sh -n` and `doctor(work): sh -n` checks catch any shell syntax slip in the new block.

- [ ] **Step 5: Commit**

```bash
git add dot_local/bin/executable_dotfiles-doctor.tmpl test/render.sh
git commit -m "Doctor: check the Brewfile, config drift, and the status line"
```

---

### Task 9: README and the earlier spec

**Files:**
- Modify: `README.md`, `docs/superpowers/specs/2026-10-01-chezmoi-dotfiles-design.md`
- Test: `test/render.sh` (the `# Task 8: install.sh and README` block)

- [ ] **Step 1: Write the assertions**

Append to the `# Task 8: install.sh and README` block in `test/render.sh`, after its last line, `check_nofile "$P/README.md"`:

```sh
# Task 9 (2026-10-04): README covers the new tools
check_grep "README: cask adopt step" "$SRC/README.md" 'brew install --cask --adopt iterm2 zed'
check_grep "README: atuin import" "$SRC/README.md" 'atuin import auto'
check_grep "README: capture after an app edits its settings" "$SRC/README.md" 'dotfiles-capture claude'
check_fgrep "README: seed the local file from the backup" "$SRC/README.md" 'dotfiles-capture --from ~/.claude/settings.json.pre-chezmoi claude'
check_grep "README: Nerd Font set by hand" "$SRC/README.md" 'JetBrains Mono Nerd Font'
check_nogrep "README: re-add is not the route for app settings" "$SRC/README.md" 're-add ~/.claude'
```

- [ ] **Step 2: Run the suite to see the new assertions fail**

Run: `./test/render.sh | grep FAIL`
Expected: five `README:` failures. The `re-add` check already passes.

- [ ] **Step 3: Update the README**

In `README.md`, replace the `## Daily use` section, up to `## Design`, with:

````markdown
## Daily use

- `chezmoi edit --apply ~/.zshrc`, or edit in `~/.dotfiles` and run `chezmoi apply`.
- `chezmoi re-add` after editing a managed file in place. Claude Code and Zed settings work differently; see below.
- `dotfiles-doctor` checks identity, SSH, gh, signing, PATH, the Brewfile, config drift, the Claude Code status line, and startup time.
- `chezmoi upgrade` updates the chezmoi binary. Nothing else will.
- `./test/render.sh` renders both machine kinds into a temp dir and asserts on the result.

## Shell and git tools

The Brewfile installs fzf (Ctrl-T files, Alt-C directories), atuin (Ctrl-R history, local only, no sync), zoxide (`z dir`), bat (`cat` and man pages), eza (`ls`), ripgrep, fd, xh (`headers`), starship (the prompt), delta (git pager), difftastic (`git dft` or `dft`), lazygit (`lg`), and git-absorb. Each shell integration is skipped when its tool is absent, so a half-installed machine still gets a shell.

Casks: iTerm2, Zed, and JetBrains Mono Nerd Font. On a machine where iTerm2 or Zed is already in `/Applications`, run `brew install --cask --adopt iterm2 zed` once before `chezmoi apply`, because `brew bundle` will not install over an app it did not put there. Set iTerm2's font to JetBrains Mono Nerd Font by hand; iTerm2 preferences are not managed.

After the first apply on an existing machine, run `atuin import auto` once to load the old history file.

## Claude Code and Zed settings

`~/.claude/settings.json` and `~/.config/zed/settings.json` are each built from two files:

- A shared file in this repo: `.chezmoitemplates/claude-settings.json` or `.chezmoitemplates/zed-settings.json`.
- A local file that never leaves the machine: `~/.config/chezmoi/claude-settings.local.json` or `~/.config/chezmoi/zed-settings.local.json`. Its keys win over the shared file's, except that Claude Code permission lists are combined. Work-only values, and Claude Code's `autoMode` description of the machine, live here.

Both apps rewrite their settings file when you change something in them. Afterwards, run `dotfiles-capture claude` or `dotfiles-capture zed` to copy the changed keys into the local file; otherwise the next `chezmoi apply` offers to undo the change. `dotfiles-capture --shared claude` moves them into the shared file instead, for you to commit. It refuses on a work machine, because this repo is public. `chezmoi re-add` skips these two files. `dotfiles-doctor` warns when either has drifted and names the command to run.

The first apply on a machine that already has these settings replaces them, after copying each to `<file>.pre-chezmoi`. Move what that machine needs into its local files:

```
dotfiles-capture --from ~/.claude/settings.json.pre-chezmoi claude
dotfiles-capture --from ~/.config/zed/settings.json.pre-chezmoi zed
```

Then read the local files and delete anything that should come from the shared file instead.

Claude Code's status line is `~/.local/bin/claude-statusline`. It shows the repo, the branch in green or red for clean or dirty, and `with unpushed` when the branch is ahead of upstream. Nothing else under `~/.claude` is managed; skills are an open question recorded in the spec.
````

- [ ] **Step 4: Update the earlier spec**

In `docs/superpowers/specs/2026-10-01-chezmoi-dotfiles-design.md`, in the `## Decisions already made` table, change the Node row to:

```
| Node | nvm, lazy-loaded, until the mise changeset described in `2026-10-04-modern-cli-tools-design.md`. |
```

and change the line `Casks are out of scope.` under Bootstrap to:

```
Casks were out of scope in this design; `2026-10-04-modern-cli-tools-design.md` adds three.
```

The new spec's own status changes in Task 10, after the rollout.

- [ ] **Step 5: Run the suite**

Run: `./test/render.sh | tail -1`
Expected: `all checks passed`

- [ ] **Step 6: Commit**

```bash
git add README.md docs/superpowers/specs test/render.sh
git commit -m "Docs: describe the new tools, casks, settings capture, and status line"
```

---

### Task 10: Rollout on this machine

This task changes the live machine: it installs around twenty formulae and three casks, rewrites the live shell config, and replaces the Claude Code and Zed settings files. **Stop and confirm with the user before Step 1.** Everything before this task was repo-only, apart from Task 5 reading the live settings.

**Files:** `docs/superpowers/specs/2026-10-04-modern-cli-tools-design.md` in Step 11; nothing else in the repo.

- [ ] **Step 1: Adopt the casks that already exist**

```bash
brew install --cask --adopt iterm2 zed
```

Expected: both report adopted or already installed. If brew says an app is not from a cask and refuses, stop and ask rather than deleting anything.

- [ ] **Step 2: Seed the local settings files from the live ones**

`dotfiles-capture` is not in `~/.local/bin` until the apply, so run it from the source:

```bash
sh ~/.dotfiles/dot_local/bin/executable_dotfiles-capture --from ~/.claude/settings.json claude
sh ~/.dotfiles/dot_local/bin/executable_dotfiles-capture --from ~/.config/zed/settings.json zed
```

Expected: Claude Code reports `captured autoMode into ~/.config/chezmoi/claude-settings.local.json` and writes `~/.claude/settings.json` from the shared file plus that; Zed reports `nothing to capture`. Doing this before the apply means the running Claude Code session never sees its settings without `autoMode`. If the Claude Code line lists more keys than `autoMode`, those changed after Task 5. Show them to the user. Each stays local unless the user wants it shared, in which case move it from the local file to the shared file by hand and commit.

- [ ] **Step 3: Review what the apply will do**

```bash
chezmoi diff
```

Expected: new and changed files under `~/.config`, `~/.gitconfig`, and `~/.local/bin`; `~/.local/bin/headers` deleted; Zed's settings losing their comments; no diff for `~/.claude/settings.json`, which Step 2 wrote. Stop and ask if anything else appears.

- [ ] **Step 4: Apply**

```bash
chezmoi apply -v
```

Expected: the homebrew run script fires because the Brewfile hash changed, and `brew bundle` installs the new formulae and the font cask. The backup script copies both settings files to `.pre-chezmoi`. Then the files are written and `.chezmoiremove` deletes the old `headers` script. This takes several minutes.

- [ ] **Step 5: Confirm the old headers script is gone**

```bash
test ! -e ~/.local/bin/headers && echo removed
```

Expected: `removed`

- [ ] **Step 6: Import history into atuin**

```bash
atuin import auto
```

Expected: a count of imported history lines.

- [ ] **Step 7: Open a new shell and verify by eye**

In a new terminal window:

```bash
cd ~/.dotfiles && git status
```

Expected: the prompt reads `in .dotfiles on master` with the branch green and `›` on the next line. Ctrl-R opens atuin, Ctrl-T opens fzf, `ls` is eza output, `cat README.md` is highlighted, `git log -p -1` pages through delta, and `z dot<TAB>` completes.

- [ ] **Step 8: Run the doctor**

```bash
dotfiles-doctor
```

Expected: `all checks passed`, with startup still well under 0.3s. If a `claude settings differ` or `zed settings differ` warning appears, run the command it names.

- [ ] **Step 9: Set the terminal font**

By hand, in iTerm2 preferences, set the profile font to JetBrains Mono Nerd Font so eza icons and any starship symbols render. Then open a Claude Code session in any repo and confirm the status line shows `<repo> on <branch>`.

- [ ] **Step 10: Fix anything the rollout turned up**

If anything needed fixing to make the doctor pass, fix it in the repo, rerun `./test/render.sh`, and commit it with a message that names the fix.

- [ ] **Step 11: Mark the spec implemented**

In `docs/superpowers/specs/2026-10-04-modern-cli-tools-design.md`, change the `Status:` line to:

```
Status: implemented 2026-10-04 on the personal machine; the work machine follows "Rollout on the work machine". Builds on `2026-10-01-chezmoi-dotfiles-design.md`, which still describes the repo's structure, identity scheme, and test harness. This document covers only what changes.
```

```bash
git add docs/superpowers/specs/2026-10-04-modern-cli-tools-design.md
git commit -m "Spec: mark modern CLI tools implemented on the personal machine"
```
