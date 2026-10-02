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

# Task 3: git identity
check_grep "personal gitconfig: personal email" "$P/.gitconfig" 'email = geehaws@gmail.com'
check_nogrep "personal gitconfig: no includeIf" "$P/.gitconfig" 'includeIf'
check_nogrep "personal gitconfig: no work email" "$P/.gitconfig" 'work@example.com'
check_eq "personal tree: work email nowhere" "$(grep -rl 'work@example.com' "$P" | wc -l | tr -d ' ')" "0"
check_grep "gitconfig: pushInsteadOf" "$P/.gitconfig" 'pushInsteadOf = https://github.com/'
check_nogrep "gitconfig: no plain insteadOf" "$P/.gitconfig" '^[[:space:]]*insteadOf'
check_grep "gitconfig: sshCommand flags" "$P/.gitconfig" 'sshCommand = ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes -o AddKeysToAgent=yes -o IgnoreUnknown=UseKeychain -o UseKeychain=yes'
check_grep "gitconfig: credential helper kept" "$P/.gitconfig" 'helper = osxkeychain'
check_grep "gitconfig: excludesfile" "$P/.gitconfig" 'excludesfile = ~/.config/git/ignore'
check_file "$P/.config/git/ignore"
check_grep "gitconfig: allowedSignersFile" "$P/.gitconfig" 'allowedSignersFile = ~/.config/git/allowed_signers'

check_grep "work gitconfig: work email" "$W/.gitconfig" 'email = work@example.com'
check_eq "work gitconfig: 3 hasconfig includes per owner" "$(grep -c 'includeIf "hasconfig:remote\.\*\.url:' "$W/.gitconfig")" "3"
check_grep "work gitconfig: https pattern" "$W/.gitconfig" 'hasconfig:remote.\*.url:https://github.com/george-elliott/\*\*'
check_grep "work gitconfig: scp pattern" "$W/.gitconfig" 'hasconfig:remote.\*.url:git@github.com:george-elliott/\*\*'
check_grep "work gitconfig: ssh pattern" "$W/.gitconfig" 'hasconfig:remote.\*.url:ssh://git@github.com/george-elliott/\*\*'
user_line=$(grep -n '^\[user\]' "$W/.gitconfig" | head -1 | cut -d: -f1)
inc_line=$(grep -n 'includeIf' "$W/.gitconfig" | head -1 | cut -d: -f1)
if [ -n "$user_line" ] && [ -n "$inc_line" ] && [ "$user_line" -lt "$inc_line" ]; then pass "work gitconfig: includes after [user]"; else fail "work gitconfig: includes before [user] or missing"; fi
check_file "$W/.config/git/personal"
check_mode "work personal include: 0600" "$W/.config/git/personal" "600"
check_grep "personal include: personal email" "$W/.config/git/personal" 'email = geehaws@gmail.com'
check_grep "personal include: personal key" "$W/.config/git/personal" 'id_ed25519_personal'
check_nogrep "personal include: no remote section" "$W/.config/git/personal" '^\[remote'

# Real git against the rendered work tree. HOME makes ~ in include paths resolve.
gitw() { HOME="$W" GIT_CONFIG_NOSYSTEM=1 git "$@"; }
r="$tmp/r"; rm -rf "$r"
gitw init -q "$r/none"
check_eq "git(work): no remote -> work email" "$(gitw -C "$r/none" config user.email)" "work@example.com"
gitw init -q "$r/https"; gitw -C "$r/https" remote add origin https://github.com/george-elliott/x.git
check_eq "git(work): https personal remote -> personal email" "$(gitw -C "$r/https" config user.email)" "geehaws@gmail.com"
check_eq "git(work): https personal remote -> personal key" "$(gitw -C "$r/https" config user.signingkey)" "~/.ssh/id_ed25519_personal.pub"
check_eq "git(work): push url rewritten to ssh" "$(gitw -C "$r/https" remote get-url --push origin)" "git@github.com:george-elliott/x.git"
check_eq "git(work): fetch url stays https" "$(gitw -C "$r/https" remote get-url origin)" "https://github.com/george-elliott/x.git"
gitw init -q "$r/scp"; gitw -C "$r/scp" remote add origin git@github.com:george-elliott/x.git
check_eq "git(work): scp personal remote -> personal email" "$(gitw -C "$r/scp" config user.email)" "geehaws@gmail.com"
gitw init -q "$r/work"; gitw -C "$r/work" remote add origin https://github.com/example-org/x.git
check_eq "git(work): work remote -> work email" "$(gitw -C "$r/work" config user.email)" "work@example.com"
gitw init -q "$r/two"; gitw -C "$r/two" remote add origin https://github.com/example-org/x.git
gitw -C "$r/two" remote add fork https://github.com/george-elliott/x.git
check_eq "git(work): any personal remote wins (documented limit)" "$(gitw -C "$r/two" config user.email)" "geehaws@gmail.com"
gitw init -q "$r/upper"; gitw -C "$r/upper" remote add origin https://github.com/George-Elliott/x.git
check_eq "git(work): uppercase owner is NOT matched (documented limit)" "$(gitw -C "$r/upper" config user.email)" "work@example.com"
gitp() { HOME="$P" GIT_CONFIG_NOSYSTEM=1 git "$@"; }
gitp init -q "$r/p"; gitp -C "$r/p" remote add origin https://github.com/example-org/x.git
check_eq "git(personal): any remote -> personal email" "$(gitp -C "$r/p" config user.email)" "geehaws@gmail.com"

finish
