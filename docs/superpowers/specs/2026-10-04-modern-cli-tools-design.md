# Modern CLI tools, Claude Code config, and a shared status line

Date: 2026-10-04
Status: approved design, not yet implemented. Builds on `2026-10-01-chezmoi-dotfiles-design.md`, which still describes the repo's structure, identity scheme, and test harness. This document covers only what changes.

## Goal

Bring the shell up to the current baseline of developer CLI tooling, put the Claude Code and Zed configuration under chezmoi so both machines behave the same, and give Claude Code a status line that reads the same everywhere. Keep the repo's character: port only what is used, nothing globbed, interactive startup under 0.3 seconds.

Interactive startup today measures 0.024 seconds. Everything below is expected to add under 50 milliseconds in total.

## Decisions

Each line below was decided one at a time in the design conversation.

| Item | Decision |
|---|---|
| Brewfile drift | Add the seven formulae installed by hand but not in the Brewfile. The doctor runs `brew bundle check` so drift fails loudly. |
| ripgrep, fd | Add. `rg` is not installed today; the `rg` seen in Claude Code sessions is a shell-snapshot function. |
| fzf | Add, with the zsh integration. Keeps Ctrl-T and Alt-C; Ctrl-R goes to atuin. |
| bat | Add. `cat` is aliased to `bat`. `MANPAGER` uses bat for man pages. |
| eza | Add. Replaces the four `gls` aliases, with the git column and icons. coreutils stays for the other GNU tools. |
| zoxide | Add. The `c` function stays; `z` covers everything else. |
| zsh-autosuggestions, zsh-syntax-highlighting | Add both, sourced from Homebrew paths. No plugin manager. |
| delta, difftastic | Add both. delta is the git pager. difftastic is an opt-in difftool behind a `dft` alias. |
| mise | Adopt for every runtime, in its own changeset after this one. This changeset keeps nvm. |
| Claude Code and Zed config | Track under chezmoi. The doctor warns when the live files differ from the source. |
| atuin | Add, local only. Sync stays off. |
| starship | Adopt, configured to reproduce the current two-line prompt. |
| direnv | Skip. mise's `[env]` covers per-project variables once it lands. |
| lazygit | Add, with an `lg` alias, no config file. |
| git-absorb | Add. |
| jj | Not installed. Recorded under Future work. |
| Casks | Partial reversal of the earlier "out of scope": iTerm2, Zed, and JetBrains Mono Nerd Font only. |
| xh | Add. The `headers` script is deleted and `headers` becomes an alias for `xh -h`. |
| Claude Code status line | A chezmoi-managed script showing repo, branch, and unpushed state, referenced from the tracked `settings.json`. |

## Brewfile

The Brewfile becomes:

```
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

# Installed by hand before this change; the mise changeset removes node and yarn
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

# Apps
cask "iterm2"
cask "zed"
cask "font-jetbrains-mono-nerd-font"
```

Every formula and cask name above was checked against Homebrew on 2026-10-04.

On this machine iTerm2 and Zed are already in `/Applications` from manual downloads, so a plain `brew bundle` would refuse to install over them. `brew bundle` has no adopt option, so on an existing machine the two casks are adopted by hand once with `brew install --cask --adopt iterm2 zed` before `chezmoi apply`. After that, `brew bundle` sees them as installed. A fresh machine has no such problem. The README documents this step.

Both casks self-update. Homebrew's `auto_updates` flag means `brew upgrade` leaves them alone, so there is no fight between the two updaters.

## zsh

`.zshrc` sources files by name. The new order:

```
path env options aliases git nvm tools prompt completion plugins
```

| File | Change |
|---|---|
| `env.zsh` | Adds `MANPAGER="sh -c 'col -bx | bat -l man -p'"` and `MANROFFOPT="-c"`. |
| `aliases.zsh` | The `gls` block is replaced by an `eza` block guarded on `eza` existing: `ls='eza -lF --git --icons'`, `l='eza -lah --git --icons'`, `ll='eza -l --git --icons'`, `la='eza -a --icons'`. Adds `cat='bat'`, `lg='lazygit'`, `headers='xh -h'`. |
| `git.zsh` | Adds `dft='git difftool'`. |
| `tools.zsh` | New. Each block guarded on the command existing. `source <(fzf --zsh)` with `FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'` and the matching `FZF_CTRL_T_COMMAND`. `eval "$(zoxide init zsh)"`. `eval "$(atuin init zsh --disable-up-arrow)"`, which binds Ctrl-R after fzf did, so atuin wins. |
| `prompt.zsh` | Shrinks to the `title` function, the `precmd` that calls it, and `eval "$(starship init zsh)"`. The git helper functions and the `PROMPT` assignment go. |
| `plugins.zsh` | New, sourced last. Sources `/opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh` and then `/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh`, each guarded on the file existing. Syntax highlighting must be the last thing that touches ZLE widgets, which is why this file is last. |

`completion.zsh` and `compinit` stay where they are, before `plugins.zsh`, because autosuggestions reads completion state.

The `c` function and its `_c` completion are unchanged.

Startup target stays under 0.3 seconds, and the doctor keeps measuring it.

## git

Additions to `dot_gitconfig.tmpl`, outside the work-only block:

```
[core]
    pager = delta
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
[difftool]
    prompt = false
[alias]
    dft = difftool --tool=difftastic
```

`difftool.prompt = false` already exists and is kept, not duplicated. `side-by-side` is off by default because it needs a wide terminal; `delta --side-by-side` turns it on per invocation.

git-absorb needs no config. `git absorb --and-rebase` is the normal invocation.

## New managed files

| Target | Source | Notes |
|---|---|---|
| `~/.config/starship.toml` | `dot_config/starship.toml` | Reproduces the current prompt: blank line, `in <cyan dir> on <branch> with unpushed`, newline, `› `. Branch is bold green when clean, bold red when dirty. ` with unpushed` appears in bold magenta when ahead of upstream. Everything else off except `nodejs`, `golang`, and `status` for non-zero exits. |
| `~/.config/atuin/config.toml` | `dot_config/atuin/config.toml` | `auto_sync = false`, `update_check = false`, `search_mode = "fuzzy"`, `filter_mode = "global"`, `filter_mode_shell_up_key_binding = "directory"`, `style = "compact"`, `inline_height = 20`, `enter_accept = false`. |
| `~/.claude/settings.json` | `dot_claude/settings.json` | The existing file plus the `statusLine` entry. Plain file, not a template; nothing in it differs by machine. |
| `~/.config/zed/settings.json` | `dot_config/zed/settings.json` | Plain file. |
| `~/.local/bin/claude-statusline` | `dot_local/bin/executable_claude-statusline` | See the next section. |

Not tracked, on purpose: `~/.claude/CLAUDE.md` and `~/.claude/keybindings.json` do not exist today and are added if they ever do. Nothing under `~/.claude/skills/` is tracked; see Future work. Credentials, projects, sessions, history, shell snapshots, plugin caches, and telemetry under `~/.claude/` are machine-local or secret and never enter the repo.

chezmoi never removes files it does not manage, so adding `dot_claude/` to the source tree leaves everything else under `~/.claude/` alone.

`settings.json` is a file Claude Code rewrites when permissions change interactively. The workflow is `chezmoi re-add ~/.claude/settings.json` after such a change, as the README already describes for any managed file. The doctor warns when the two drift.

The `headers` script is deleted from `dot_local/bin/`.

## Claude Code status line

`~/.local/bin/claude-statusline` is a POSIX sh script. Claude Code runs it with session JSON on stdin and shows its first line of stdout in the status row. The settings entry:

```json
"statusLine": {
  "type": "command",
  "command": "~/.local/bin/claude-statusline"
}
```

The script reads `.workspace.current_dir` from stdin with `jq`, which macOS ships at `/usr/bin/jq`, then:

- If the directory is not inside a git work tree, prints the directory's basename.
- Otherwise prints `<repo> on <branch>` where repo is the basename of `git rev-parse --show-toplevel` and branch is `git symbolic-ref --short HEAD`, or the short commit hash when detached.
- Appends ` with unpushed` when `git rev-list --count @{upstream}..HEAD` is greater than zero. When no upstream exists, nothing is appended.

Colors match the shell prompt: cyan repo, green or red branch for clean or dirty, magenta for unpushed. Claude Code debounces status line runs at 300ms and cancels an in-flight run when a new one is due, so the script does no caching. `git status --porcelain` is the only call that can be slow, and it is the same call the shell prompt makes today.

No `refreshInterval`: the line updates on Claude Code's own events, and a subagent pushing in the background is rare enough not to warrant a timer.

## Verification

New `dotfiles-doctor` checks:

| Check | Expectation |
|---|---|
| Brewfile | `brew bundle check --file ~/.dotfiles/Brewfile --no-upgrade` exits 0. Fail otherwise, listing what is missing. |
| Managed config drift | `chezmoi verify ~/.claude/settings.json ~/.config/zed/settings.json ~/.config/starship.toml ~/.config/atuin/config.toml` exits 0. Warn, not fail, because interactive edits to these files are expected; the fix is `chezmoi re-add`. |
| Status line wired | `~/.claude/settings.json` has `.statusLine.command` equal to `~/.local/bin/claude-statusline`, and that file is executable. |
| Status line output | Piping `{"workspace":{"current_dir":"$HOME/.dotfiles"}}` to the script prints a line containing `dotfiles on `. |
| Tool presence | `command -v` succeeds for every new formula's binary. Fail otherwise. |
| Startup | Unchanged check, under 0.3 seconds. Now meaningful, since the shell loads eight more things. |

## Template tests

Additions to `test/render.sh`, for both the personal and work trees:

- `.config/zsh/tools.zsh`, `.config/zsh/plugins.zsh`, `.config/starship.toml`, `.config/atuin/config.toml`, `.config/zed/settings.json`, `.claude/settings.json`, and `.local/bin/claude-statusline` exist.
- `.local/bin/claude-statusline` is executable.
- `.local/bin/headers` does not exist.
- `.config/zsh/.zshrc` lists `plugins` last in its source order.
- `.gitconfig` contains `pager = delta` and a `[difftool "difftastic"]` section.
- `.config/atuin/config.toml` contains `auto_sync = false`.
- `.claude/settings.json` parses with `jq` and `.statusLine.command` is `~/.local/bin/claude-statusline`.
- `settings.json` is the only file rendered under `.claude/`.
- The status line script, run against a temp git repo with one unpushed commit over a stubbed upstream, prints `x on main with unpushed`; against the same repo after pushing, prints `x on main`; against a non-repo directory, prints the directory name.

As before, each assertion is written before the file it checks.

## Rollout on this machine

1. `brew install --cask --adopt iterm2 zed` once, by hand, because the apps already exist.
2. `chezmoi apply`. The homebrew run script fires because the Brewfile hash changed.
3. `atuin import auto` once to load the existing history file.
4. Open a new shell and set iTerm2's font to JetBrains Mono Nerd Font by hand. iTerm2 preferences are not managed.
5. `dotfiles-doctor`.

## Future work

Recorded here so the decisions are not lost. Each is its own changeset with its own spec.

**mise for every runtime.** Replace nvm with mise for Node, move Go from Homebrew to mise, and let mise manage Python alongside uv. Removes `nvm.zsh`, `nvm`, `node`, and `yarn` from this repo and the Brewfile, adds `~/.config/mise/config.toml` with pinned global versions, and adds `eval "$(mise activate zsh)"` to `tools.zsh`. mise's `[env]` section takes the role direnv would have had. Decided in this design; deferred so that tool additions and runtime migration are not debugged together.

**Claude Code skills.** `~/.claude/skills/` holds a mix today: two hand-written skills, two git clones of third-party skills, a folder Claude's cloud sync owns, and a symlink into another tool's skill store. Copying skill files into this repo was considered and rejected for now; how skills should be shared between machines is an open question, to be designed separately. Until then this repo tracks nothing under `~/.claude/skills/`.

**jj.** Jujutsu works inside existing git repos and has a better model for conflicts, undo, and the working copy. Not adopted because it keeps its own identity and signing config, so the remote-based personal-or-work scheme would have to be duplicated and kept in step, and because it is still marked experimental. Worth a fresh look once it stabilises and once there is a known pattern for mirroring `includeIf` behaviour in its config.
