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

# Task 4: gh shim
check_file "$W/.local/bin/gh"
if [ -x "$W/.local/bin/gh" ]; then pass "gh shim executable"; else fail "gh shim not executable"; fi
check_grep "gh shim: mentions owner" "$W/.local/bin/gh" 'george-elliott'
stub="$tmp/stub-gh"; printf '#!/bin/sh\necho "GH_CONFIG_DIR=${GH_CONFIG_DIR:-unset} args=$*"\n' > "$stub"; chmod +x "$stub"
ghw() { DOTFILES_REAL_GH="$stub" HOME="$W" "$W/.local/bin/gh" "$@"; }
check_eq "gh shim: personal remote -> gh-personal" "$(cd "$r/https" && ghw pr list)" "GH_CONFIG_DIR=$W/.config/gh-personal args=pr list"
check_eq "gh shim: uppercase owner remote -> gh-personal" "$(cd "$r/upper" && ghw pr list)" "GH_CONFIG_DIR=$W/.config/gh-personal args=pr list"
check_eq "gh shim: work remote -> default" "$(cd "$r/work" && ghw pr list)" "GH_CONFIG_DIR=unset args=pr list"
check_eq "gh shim: no remote -> default" "$(cd "$r/none" && ghw auth status)" "GH_CONFIG_DIR=unset args=auth status"
check_eq "gh shim: outside a repo -> default, no git noise" "$(cd "$tmp" && ghw auth status 2>&1)" "GH_CONFIG_DIR=unset args=auth status"
check_eq "gh shim: owner/ argument -> gh-personal" "$(cd "$tmp" && ghw repo clone george-elliott/thing)" "GH_CONFIG_DIR=$W/.config/gh-personal args=repo clone george-elliott/thing"
check_eq "gh shim: -R owner/repo -> gh-personal" "$(cd "$tmp" && ghw pr list -R George-Elliott/thing)" "GH_CONFIG_DIR=$W/.config/gh-personal args=pr list -R George-Elliott/thing"

# Task 5: zsh
check_fgrep "zshenv sets ZDOTDIR" "$P/.zshenv" 'export ZDOTDIR="$HOME/.config/zsh"'
for f in .zshrc path.zsh env.zsh options.zsh aliases.zsh git.zsh nvm.zsh prompt.zsh completion.zsh; do
  check_file "$P/.config/zsh/$f"
  if zsh -n "$P/.config/zsh/$f" 2>/dev/null; then pass "zsh -n $f"; else fail "zsh -n $f: syntax error"; fi
done
for f in c _c extract gf _git-rm; do check_file "$P/.config/zsh/functions/$f"; done
check_nofile "$P/.config/zsh/functions/_brew"
check_grep "zshrc: explicit order" "$P/.config/zsh/.zshrc" 'for f in path env options aliases git nvm prompt completion'
check_grep "zshrc: localrc last" "$P/.config/zsh/.zshrc" 'source ~/.localrc'
check_nogrep "aliases: no gulp/ws/mstart/chc" "$P/.config/zsh/aliases.zsh" 'gulp|WebStorm|memcached|cache_classes'
check_grep "aliases: pubkey uses ed25519" "$P/.config/zsh/aliases.zsh" 'id_ed25519.pub'
check_nogrep "git aliases: no hub" "$P/.config/zsh/git.zsh" 'hub'
check_eq "git aliases: gb defined once" "$(grep -c "^alias gb=" "$P/.config/zsh/git.zsh")" "1"
check_grep "completion: ZDOTDIR dump" "$P/.config/zsh/completion.zsh" 'ZDOTDIR/.zcompdump'
check_nogrep "nvm: no eager source" "$P/.config/zsh/nvm.zsh" '^source'
# The shell must start clean with no Homebrew and nothing in PATH but system dirs.
h="$tmp/zh"; mkdir -p "$h"; cp -R "$P/.config" "$h/"; cp "$P/.zshenv" "$h/"
out=$(env -i HOME="$h" TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -i -c 'echo started' 2>&1)
check_eq "zsh: starts with no Homebrew" "$out" "started"
out=$(env -i HOME="$h" TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -i -c 'print -l $path | head -3 | tr "\n" " "' 2>&1)
check_eq "zsh: path order" "$out" "$h/.local/bin /opt/homebrew/bin /opt/homebrew/sbin "
out=$(env -i HOME="$h" TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -i -c 'whence -w node yarn corepack extract c | tr "\n" " "' 2>&1)
check_eq "zsh: lazy stubs and autoloads defined" "$out" "node: function yarn: function corepack: function extract: function c: function "

# Task 6: bin and vimrc
for s in git-all git-amend git-copy-branch-name git-credit git-delete-local-merged git-nuke git-promote git-rank-contributors git-review git-track git-undo git-unpushed git-unpushed-stat git-up git-wtf e headers todo macos-defaults; do
  if [ -x "$P/.local/bin/$s" ]; then pass "bin: $s executable"; else fail "bin: $s missing or not executable"; fi
done
check_nofile "$P/.local/bin/dot"
check_nofile "$P/.local/bin/gitio"
check_grep "git-delete-local-merged keeps main" "$P/.local/bin/git-delete-local-merged" "main"
check_file "$P/.vimrc"

finish
