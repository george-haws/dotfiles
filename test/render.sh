#!/bin/sh
# Renders the source tree for a personal and a work machine into a temp
# directory and asserts on the result. Never touches the real $HOME.
set -u
cd "$(dirname "$0")/.."
SRC=$(pwd)
. "$SRC/test/lib.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

render() { # fixture-name
  mkdir -p "$tmp/$1"
  chezmoi --config "$SRC/test/fixtures/$1.toml" \
          --source "$SRC" \
          --destination "$tmp/$1" \
          --persistent-state "$tmp/$1.boltdb" \
          --exclude scripts \
          apply || fail "chezmoi apply ($1) exited non-zero"
}
# Render a single script template with a fixture's data to stdout.
render_tmpl() { # fixture-name source-file
  chezmoi --config "$SRC/test/fixtures/$1.toml" --source "$SRC" \
          --persistent-state "$tmp/$1.boltdb" execute-template < "$SRC/$2"
}

render personal
render work
P="$tmp/personal"
W="$tmp/work"

# ---- assertions (tasks append below this line) ----

check_file "$P/.gitconfig"

# Task 2: ignore rules and config template
check_nofile "$P/README.md"
check_nofile "$P/install.sh"
check_nofile "$P/docs"
check_nofile "$P/test"
check_nofile "$P/LICENSE.md"
check_nofile "$P/.config/git/personal"
check_nofile "$P/.local/bin/gh"
cfg=$(chezmoi --config "$SRC/test/fixtures/empty.toml" --source "$SRC" --persistent-state "$tmp/cfg.boltdb" \
      execute-template --init --promptBool "Is this a work machine=true" \
      --promptString "Work git email=work@example.com" < "$SRC/.chezmoi.toml.tmpl")
check_eq "config: work=true renders" "$(printf '%s\n' "$cfg" | grep -c 'work = true')" "1"
check_eq "config: workEmail quoted" "$(printf '%s\n' "$cfg" | grep -c 'workEmail = "work@example.com"')" "1"
check_eq "config: sourceDir set" "$(printf '%s\n' "$cfg" | grep -c 'sourceDir = ".*/.dotfiles"')" "1"
cfg=$(chezmoi --config "$SRC/test/fixtures/empty.toml" --source "$SRC" --persistent-state "$tmp/cfg.boltdb" \
      execute-template --init --promptBool "Is this a work machine=false" < "$SRC/.chezmoi.toml.tmpl")
check_eq "config: work=false renders" "$(printf '%s\n' "$cfg" | grep -c 'work = false')" "1"
check_eq "config: workEmail empty on personal" "$(printf '%s\n' "$cfg" | grep -c 'workEmail = ""')" "1"

finish
