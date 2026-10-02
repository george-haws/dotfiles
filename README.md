# dotfiles

Managed with [chezmoi](https://chezmoi.io). Source lives at `~/.dotfiles`.

## Fresh machine

```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/george-elliott/dotfiles/master/install.sh)"
```

You are asked once whether this is a work machine and, if so, for the work email. Answers are stored in `~/.config/chezmoi/chezmoi.toml` and never committed. The script installs Command Line Tools and chezmoi, then chezmoi installs Homebrew, the Brewfile, and the dotfiles. It prints any new SSH public key; add it to GitHub as both an authentication key and a signing key.

By hand, the same thing is three steps: `xcode-select --install`, `sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin`, then `~/.local/bin/chezmoi init --source ~/.dotfiles --apply george-elliott`.

## How identity works

Git, SSH, signing, and `gh` pick the GitHub account from the repo's remote URL, never from the directory.

- Personal machine: personal everywhere.
- Work machine: work by default. Repos whose remote is under a personal owner (see `personalOwners` in `.chezmoi.toml.tmpl`) use the personal email, personal key, and the `gh` login in `~/.config/gh-personal`.

Fetches stay HTTPS; pushes to `github.com` go over SSH. Clone **private personal** repos on the work machine by their SSH URL, because an HTTPS fetch would use the work token.

One-time on a work machine, from inside `~/.dotfiles`: `GH_CONFIG_DIR=~/.config/gh-personal gh auth login`.

## Daily use

- `chezmoi edit --apply ~/.zshrc` or edit in `~/.dotfiles` and run `chezmoi apply`.
- `chezmoi re-add` after editing a managed file in place.
- `dotfiles-doctor` checks identity, SSH, gh, signing, PATH, and startup time.
- `chezmoi upgrade` updates the chezmoi binary; nothing else will.
- `./test/render.sh` renders both machine kinds into a temp dir and asserts on the result.

## Layout

See `docs/superpowers/specs/2026-10-01-chezmoi-dotfiles-design.md` for the design.
