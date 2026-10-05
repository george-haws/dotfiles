# dotfiles

Managed with [chezmoi](https://chezmoi.io). The source lives at `~/.dotfiles`.

## Fresh machine

```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/george-haws/dotfiles/master/install.sh)"
```

chezmoi asks once whether this is a work machine and, if so, for the work email. It stores the answers in `~/.config/chezmoi/chezmoi.toml` and never commits them. The script installs the Command Line Tools and chezmoi; chezmoi then installs Homebrew, the Brewfile, and the dotfiles, and then the uv tools listed in `run_onchange_after_20-uv-tools.sh`. If the Command Line Tools were missing, the script exits after launching their installer, so run it again when that finishes. It prints any new SSH public key. Add that key to GitHub twice, as an authentication key and as a signing key.

By hand, the same thing is three commands:

```
xcode-select --install
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
~/.local/bin/chezmoi init --source ~/.dotfiles --apply --guess-repo-url=false https://github.com/george-haws/dotfiles.git
```

## How identity works

Git, SSH, signing, and `gh` pick the GitHub account from the repo's remote URL, never from the directory.

- Personal machine: personal everywhere.
- Work machine: work by default. Repos whose remote is under a personal owner (see `personalOwners` in `.chezmoi.toml.tmpl`) use the personal email, the personal key, and the `gh` login in `~/.config/gh-personal`.

Fetches stay HTTPS; pushes to `github.com` go over SSH. Clone **private personal** repos on the work machine by their SSH URL, because an HTTPS fetch would use the work token.

Two limits. Owner matching is case-sensitive for git, so clone with the owner spelled as GitHub spells it. A repo with any remote under a personal owner resolves to personal, even if its origin is a work repo.

On a work machine, log `gh` into the personal account once, from inside this repo:

```
GH_CONFIG_DIR=~/.config/gh-personal gh auth login
```

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

- A shared file in this repo: `.shared/claude-settings.json` or `.shared/zed-settings.json`.
- A local file that never leaves the machine: `~/.config/chezmoi/claude-settings.local.json` or `~/.config/chezmoi/zed-settings.local.json`. Its keys win over the shared file's, except that Claude Code permission lists are combined. Work-only values, and Claude Code's `autoMode` description of the machine, live here.

Both apps rewrite their settings file when you change something in them. Afterwards, run `dotfiles-capture claude` or `dotfiles-capture zed` to copy the changed keys into the local file; otherwise the next `chezmoi apply` offers to undo the change. `dotfiles-capture --shared claude` moves them into the shared file instead, for you to commit. It refuses on a work machine, because this repo is public. `chezmoi re-add` skips these two files. `dotfiles-doctor` warns when either has drifted and names the command to run.

The first apply on a machine that already has these settings replaces them, after copying each to `<file>.pre-chezmoi`. Move what that machine needs into its local files:

```
dotfiles-capture --from ~/.claude/settings.json.pre-chezmoi claude
dotfiles-capture --from ~/.config/zed/settings.json.pre-chezmoi zed
```

Then read the local files and delete anything that should come from the shared file instead.

Claude Code's status line is `~/.local/bin/claude-statusline`. It shows the repo, the branch in green or red for clean or dirty, and `with unpushed` when the branch is ahead of upstream. Nothing else under `~/.claude` is managed; skills are an open question recorded in the spec.

## Design

`docs/superpowers/specs/2026-10-01-chezmoi-dotfiles-design.md` records the design and the decisions behind it.

## License

MIT, see `LICENSE.md`. The git-* helper scripts in `.local/bin` are adapted from [Zach Holman's dotfiles](https://github.com/holman/dotfiles) and keep his copyright notice.
