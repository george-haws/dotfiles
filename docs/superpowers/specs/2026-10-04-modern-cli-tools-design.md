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
| Claude Code and Zed config | Track under chezmoi. Each file is rendered from a shared file in the repo and a local file per machine that is never committed. A `dotfiles-capture` script keeps changes the apps make in place, in the local file by default, and refuses to write the shared file on a work machine. The doctor warns on drift. |
| atuin | Add, local only. Sync stays off. |
| starship | Adopt, configured to reproduce the current two-line prompt. |
| direnv | Skip. mise's `[env]` covers per-project variables once it lands. |
| lazygit | Add, with an `lg` alias, no config file. |
| git-absorb | Add. |
| jj | Not installed. Recorded under Future work. |
| Casks | Partial reversal of the earlier "out of scope": iTerm2, Zed, and JetBrains Mono Nerd Font only. |
| xh | Add. The `headers` script is deleted, `.chezmoiremove` removes the installed copy, and `headers` becomes an alias for `xh -h`. |
| Claude Code status line | A chezmoi-managed script showing repo, branch, and unpushed state, referenced from the shared Claude Code settings. |

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
path env options aliases git nvm prompt completion tools plugins
```

| File | Change |
|---|---|
| `env.zsh` | Adds `MANPAGER="sh -c 'col -bx | bat -l man -p'"` and `MANROFFOPT="-c"`. |
| `aliases.zsh` | The `gls` block is replaced by an `eza` block guarded on `eza` existing: `ls='eza -lF --git --icons'`, `l='eza -lah --git --icons'`, `ll='eza -l --git --icons'`, `la='eza -a --icons'`. Adds `cat='bat'`, `lg='lazygit'`, `headers='xh -h'`. |
| `git.zsh` | Adds `dft='git dft'`, which runs the git alias for difftastic. |
| `tools.zsh` | New. Each block guarded on the command existing. `source <(fzf --zsh)` with `FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'` and the matching `FZF_CTRL_T_COMMAND`. `eval "$(zoxide init zsh)"`. `eval "$(atuin init zsh --disable-up-arrow)"`, which binds Ctrl-R after fzf did, so atuin wins. Sourced after `completion.zsh`, because zoxide registers its `z` completion only when compinit has already run. |
| `prompt.zsh` | Shrinks to the `title` function, the `precmd` that calls it, and `eval "$(starship init zsh)"`. The git helper functions and the `PROMPT` assignment go. |
| `plugins.zsh` | New, sourced last. Sources `/opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh` and then `/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh`, each guarded on the file existing. Syntax highlighting must be the last thing that touches ZLE widgets, which is why this file is last. |

`completion.zsh` and `compinit` now run before `tools.zsh` and `plugins.zsh`: zoxide registers its completion only if compinit has run, and autosuggestions reads completion state.

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
| `~/.claude/settings.json` | `dot_claude/settings.json.tmpl` | Renders `.chezmoitemplates/claude-settings.json` with the machine's local file merged over it. See "Settings the apps rewrite". |
| `~/.config/zed/settings.json` | `dot_config/zed/private_settings.json.tmpl` | The same, from `.chezmoitemplates/zed-settings.json`. Mode 0600, as Zed created it. |
| `~/.local/bin/dotfiles-capture` | `dot_local/bin/executable_dotfiles-capture` | See "Settings the apps rewrite". |
| `~/.local/bin/claude-statusline` | `dot_local/bin/executable_claude-statusline` | See "Claude Code status line". |

Not tracked, on purpose: `~/.claude/CLAUDE.md` and `~/.claude/keybindings.json` do not exist today and are added if they ever do. Nothing under `~/.claude/skills/` is tracked; see Future work. Credentials, projects, sessions, history, shell snapshots, plugin caches, and telemetry under `~/.claude/` are machine-local or secret and never enter the repo.

chezmoi never removes files it does not manage, so adding `dot_claude/` to the source tree leaves everything else under `~/.claude/` alone.

The `headers` script is deleted from `dot_local/bin/` and listed in `.chezmoiremove`, because chezmoi does not delete a file it stops managing.

## Settings the apps rewrite

Claude Code rewrites `~/.claude/settings.json` on `/model`, `/config`, and plugin installs, and Zed rewrites its settings file from its UI. Both machines use these files, and they need different values. Claude Code's `autoMode.environment` is free text describing the machine, and the work machine may carry work-only permissions, environment variables, or plugin marketplaces. This repo is public. So neither file is a plain managed file.

- **Shared values** live in `.chezmoitemplates/claude-settings.json` and `.chezmoitemplates/zed-settings.json`, plain committed JSON. `autoMode` is never in the shared Claude Code file.
- **Local values** live in `~/.config/chezmoi/claude-settings.local.json` and `~/.config/chezmoi/zed-settings.local.json`. They sit next to `chezmoi.toml`, outside the source tree, mode 0600, and are never committed.
- **The templates** render the shared file with the local file merged over it. Maps merge key by key and the local file wins. Claude Code's `permissions.allow`, `ask`, `deny`, and `additionalDirectories` are unioned instead, matching how Claude Code merges lists across its own settings files. The output is sorted two-space JSON. Zed's comments are dropped once, when its shared file is made.
- **`chezmoi re-add` skips templates**, so it cannot carry work values into the repo.
- **`dotfiles-capture [--check] [--shared] [--from FILE] claude|zed [KEY...]`** keeps changes made in place. It copies every top-level key that differs from the rendered file into the local file, or only the named KEYs. `--shared` moves them into the shared file and out of the local one, and it refuses when chezmoi's `work` is true.
- **Which side moved.** chezmoi records a SHA-256 of what it last wrote, and `dotfiles-capture` compares that with the live and rendered files. If only the repo side moved, it captures nothing and says to apply. If both moved, it refuses unless KEYs are named. After a capture that leaves the rendered file equal to the live one, it rewrites the live file in chezmoi's layout so the doctor stays quiet. `--check` lists the differing keys and the side that moved, for the doctor.
- **The first apply on a machine** overwrites a settings file chezmoi has never written, without asking. So `run_once_before_20-settings-backup.sh` first copies each existing file to `<file>.pre-chezmoi`, never overwriting an earlier backup. `dotfiles-capture --from <backup>` then moves that machine's values into its local file. Where the script can run before the first apply, `--from` the live file does the same without the round trip.

Two limits. A key removed in place is reported, not captured; delete it by hand from the shared or local file. A permission removed in place stays granted while the shared file grants it.

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

The script exports `GIT_OPTIONAL_LOCKS=0`. Claude Code runs it while its own git commands run, and `git status` otherwise refreshes the index under `.git/index.lock`, long enough to make one of those commands fail.

No `refreshInterval`: the line updates on Claude Code's own events, and a subagent pushing in the background is rare enough not to warrant a timer.

## Verification

New `dotfiles-doctor` checks:

| Check | Expectation |
|---|---|
| Brewfile | `brew bundle check --file ~/.dotfiles/Brewfile --no-upgrade --verbose` exits 0. Fail otherwise, listing what is missing; without `--verbose` the output names nothing. |
| Config drift | `chezmoi verify ~/.config/starship.toml ~/.config/atuin/config.toml` exits 0. Warn, not fail; the fix is `chezmoi re-add` or `chezmoi apply`. |
| Settings drift | `dotfiles-capture --check claude` and `dotfiles-capture --check zed` exit 0. Warn, not fail, because the apps change these files on purpose; the warning names the differing keys and the command to run. |
| Status line wired | `~/.claude/settings.json` has `.statusLine.command` equal to `~/.local/bin/claude-statusline`, and that file is executable. |
| Status line output | Piping `{"workspace":{"current_dir":"$HOME/.dotfiles"}}` to the script prints a line containing `dotfiles on `. |
| Tool presence | `command -v` succeeds for every new formula's binary. Fail otherwise. |
| Startup | Unchanged check, under 0.3 seconds. Now meaningful, since the shell loads eight more things. |

## Template tests

Additions to `test/render.sh`, for both the personal and work trees unless noted:

- `.config/zsh/tools.zsh`, `.config/zsh/plugins.zsh`, `.config/starship.toml`, `.config/atuin/config.toml`, `.config/zed/settings.json`, `.claude/settings.json`, `.local/bin/claude-statusline`, and `.local/bin/dotfiles-capture` exist. `.config/zed/settings.json` is mode 0600.
- `.local/bin/claude-statusline` and `.local/bin/dotfiles-capture` are executable.
- `.local/bin/headers` does not exist, and `.chezmoiremove` lists it.
- `.config/zsh/.zshrc` sources `tools` after `completion`, and `plugins` last.
- With stub eza, bat, lazygit, and xh first on PATH, `ls`, `cat`, `lg`, and `headers` are aliases. Without the stubs they are not, except for tools this machine's Homebrew really has.
- `.gitconfig` contains `pager = delta` and a `[difftool "difftastic"]` section; `.config/zsh/git.zsh` aliases `dft` to `git dft`.
- `.config/atuin/config.toml` contains `auto_sync = false`.
- With no local file, the rendered Claude Code and Zed settings equal their shared files. The shared Claude Code file has no `autoMode` and no credential-like keys, and its `.statusLine.command` is `~/.local/bin/claude-statusline`. `settings.json` is the only file rendered under `.claude/`.
- With a local file, local values win, Claude Code permission lists are unioned without duplicates, and a Zed local file may contain comments.
- The backup script copies an existing settings file once and never overwrites an earlier backup.
- `dotfiles-capture`, run against a scratch copy of the source and a fake home through a chezmoi wrapper:
  - refuses before chezmoi has written the file;
  - seeds the local file `--from` a backup;
  - captures an in-place change into the local file and leaves the live file matching;
  - refuses `--shared` on a work machine without touching the shared file;
  - captures nothing when only the repo changed;
  - when both sides changed, refuses without KEYs and captures only a named KEY;
  - reports a key removed in place;
  - on a personal machine, `--shared` moves a Zed key into the shared file and out of the local one, starting from a live file with comments.
- The status line script exports `GIT_OPTIONAL_LOCKS=0`. Run against a temp git repo with one unpushed commit over a stubbed upstream, it prints `x on main with unpushed`; after pushing, `x on main`; against a non-repo directory, the directory name.

As before, each assertion is written before the file it checks.

## Rollout on this machine

1. `brew install --cask --adopt iterm2 zed` once, by hand, because the apps already exist.
2. Seed the local settings files from the live ones with `dotfiles-capture --from`, run from the source tree because `~/.local/bin` does not have it yet. This moves `autoMode` into the local Claude Code file before the running session can notice it missing.
3. `chezmoi diff`, then `chezmoi apply`. The homebrew run script fires because the Brewfile hash changed, and `.chezmoiremove` deletes the old `headers` script.
4. `atuin import auto` once to load the existing history file.
5. Open a new shell and set iTerm2's font to JetBrains Mono Nerd Font by hand. iTerm2 preferences are not managed.
6. `dotfiles-doctor`.

## Rollout on the work machine

1. `brew install --cask --adopt iterm2 zed` if either app is already in `/Applications`.
2. Pull the repo and `chezmoi apply`. The backup script keeps the existing Claude Code and Zed settings as `.pre-chezmoi` before they are replaced.
3. `dotfiles-capture --from ~/.claude/settings.json.pre-chezmoi claude`, and the same for Zed. Read the local files and delete anything that should come from the shared files instead.
4. `atuin import auto`, the iTerm2 font, and `dotfiles-doctor`.

## Future work

Recorded here so the decisions are not lost. Each is its own changeset with its own spec.

**mise for every runtime.** Replace nvm with mise for Node, move Go from Homebrew to mise, and let mise manage Python alongside uv. Removes `nvm.zsh`, `nvm`, `node`, and `yarn` from this repo and the Brewfile, adds `~/.config/mise/config.toml` with pinned global versions, and adds `eval "$(mise activate zsh)"` to `tools.zsh`. mise's `[env]` section takes the role direnv would have had. Decided in this design; deferred so that tool additions and runtime migration are not debugged together.

**Claude Code skills.** `~/.claude/skills/` holds a mix today: two hand-written skills, two git clones of third-party skills, a folder Claude's cloud sync owns, and a symlink into another tool's skill store. Copying skill files into this repo was considered and rejected. The likely mechanism is a committed list of skill sources that a chezmoi run script installs with `npx skills add`, so the repo records which skills a machine should have and the installer fetches their contents, the same way the Brewfile names formulae without vendoring them. That needs its own design: the list format, whether the script runs on change or once, how it handles skills already present, and what the doctor checks. Until then this repo tracks nothing under `~/.claude/skills/`.

**jj.** Jujutsu works inside existing git repos and has a better model for conflicts, undo, and the working copy. Not adopted because it keeps its own identity and signing config, so the remote-based personal-or-work scheme would have to be duplicated and kept in step, and because it is still marked experimental. Worth a fresh look once it stabilises and once there is a known pattern for mirroring `includeIf` behaviour in its config.
