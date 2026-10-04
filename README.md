# dotfiles

Managed with [chezmoi](https://chezmoi.io). The source lives at `~/.dotfiles`.

## Fresh machine

```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/george-haws/dotfiles/master/install.sh)"
```

chezmoi asks once whether this is a work machine and, if so, for the work email. It stores the answers in `~/.config/chezmoi/chezmoi.toml` and never commits them. The script installs the Command Line Tools and chezmoi; chezmoi then installs Homebrew, the Brewfile, and the dotfiles. If the Command Line Tools were missing, the script exits after launching their installer, so run it again when that finishes. It prints any new SSH public key. Add that key to GitHub twice, as an authentication key and as a signing key.

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
- `chezmoi re-add` after editing a managed file in place.
- `dotfiles-doctor` checks identity, SSH, gh, signing, PATH, and startup time.
- `chezmoi upgrade` updates the chezmoi binary. Nothing else will.
- `./test/render.sh` renders both machine kinds into a temp dir and asserts on the result.

## Design

`docs/superpowers/specs/2026-10-01-chezmoi-dotfiles-design.md` records the design and the decisions behind it.
