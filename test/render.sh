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
check_fgrep "config template: owners list" "$SRC/.chezmoi.toml.tmpl" 'personalOwners = ["george-haws", "george-elliott"]'
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
check_eq "work gitconfig: 4 hasconfig includes per owner (2 owners)" "$(grep -c 'includeIf "hasconfig:remote\.\*\.url:' "$W/.gitconfig")" "8"
check_grep "work gitconfig: https pattern, current owner" "$W/.gitconfig" 'hasconfig:remote.\*.url:https://github.com/george-haws/\*\*'
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
gitw init -q "$r/haws"; gitw -C "$r/haws" remote add origin https://github.com/george-haws/x.git
check_eq "git(work): current-owner remote -> personal email" "$(gitw -C "$r/haws" config user.email)" "geehaws@gmail.com"
gitw init -q "$r/userat"; gitw -C "$r/userat" remote add origin https://george-haws@github.com/george-haws/dotfiles.git
check_eq "git(work): user@ https remote -> personal email" "$(gitw -C "$r/userat" config user.email)" "geehaws@gmail.com"
check_eq "git(work): user@ https remote -> personal key" "$(gitw -C "$r/userat" config user.signingkey)" "~/.ssh/id_ed25519_personal.pub"
check_eq "git(work): user@ https push url rewritten to ssh" "$(gitw -C "$r/userat" remote get-url --push origin)" "git@github.com:george-haws/dotfiles.git"
gitw init -q "$r/userat-work"; gitw -C "$r/userat-work" remote add origin https://someone@github.com/example-org/x.git
check_eq "git(work): user@ https work remote stays work" "$(gitw -C "$r/userat-work" config user.email)" "work@example.com"
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
check_grep "gh shim: mentions both owners" "$W/.local/bin/gh" 'george-haws george-elliott'
stub="$tmp/stub-gh"; printf '#!/bin/sh\necho "GH_CONFIG_DIR=${GH_CONFIG_DIR:-unset} args=$*"\n' > "$stub"; chmod +x "$stub"
ghw() { DOTFILES_REAL_GH="$stub" HOME="$W" "$W/.local/bin/gh" "$@"; }
check_eq "gh shim: personal remote -> gh-personal" "$(cd "$r/https" && ghw pr list)" "GH_CONFIG_DIR=$W/.config/gh-personal args=pr list"
check_eq "gh shim: current-owner remote -> gh-personal" "$(cd "$r/haws" && ghw pr list)" "GH_CONFIG_DIR=$W/.config/gh-personal args=pr list"
check_eq "gh shim: uppercase owner remote -> gh-personal" "$(cd "$r/upper" && ghw pr list)" "GH_CONFIG_DIR=$W/.config/gh-personal args=pr list"
check_eq "gh shim: work remote -> default" "$(cd "$r/work" && ghw pr list)" "GH_CONFIG_DIR=unset args=pr list"
check_eq "gh shim: no remote -> default" "$(cd "$r/none" && ghw auth status)" "GH_CONFIG_DIR=unset args=auth status"
check_eq "gh shim: outside a repo -> default, no git noise" "$(cd "$tmp" && ghw auth status 2>&1)" "GH_CONFIG_DIR=unset args=auth status"
check_eq "gh shim: owner/ argument -> gh-personal" "$(cd "$tmp" && ghw repo clone george-elliott/thing)" "GH_CONFIG_DIR=$W/.config/gh-personal args=repo clone george-elliott/thing"
check_eq "gh shim: -R owner/repo -> gh-personal" "$(cd "$tmp" && ghw pr list -R George-Elliott/thing)" "GH_CONFIG_DIR=$W/.config/gh-personal args=pr list -R George-Elliott/thing"

# Task 5: zsh
check_fgrep "zshenv sets ZDOTDIR" "$P/.zshenv" 'export ZDOTDIR="$HOME/.config/zsh"'
for f in .zshrc path.zsh env.zsh options.zsh aliases.zsh git.zsh nvm.zsh tools.zsh prompt.zsh completion.zsh plugins.zsh; do
  check_file "$P/.config/zsh/$f"
  if zsh -n "$P/.config/zsh/$f" 2>/dev/null; then pass "zsh -n $f"; else fail "zsh -n $f: syntax error"; fi
done
for f in c _c extract gf _git-rm; do check_file "$P/.config/zsh/functions/$f"; done
check_nofile "$P/.config/zsh/functions/_brew"
check_grep "zshrc: explicit order" "$P/.config/zsh/.zshrc" 'for f in path env options aliases git nvm prompt completion tools plugins; do'
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
# The guards themselves, whatever this machine's Homebrew has: source the
# integration files in a shell whose PATH holds none of the tools.
out=$(env -i HOME="$h" TERM=xterm zsh -f -c 'path=(/usr/bin /bin /usr/sbin /sbin); for f in env aliases prompt tools; do source "$HOME/.config/zsh/$f.zsh"; done; print -r -- "$(whence -w ls cat lg headers z | tr "\n" " ")${+FZF_DEFAULT_COMMAND} ${+MANPAGER} ${+functions[prompt_starship_precmd]}"' 2>&1)
check_eq "zsh: guards skip every integration when no tool is on PATH" "$out" "ls: command cat: command lg: none headers: none z: none 0 0 0"
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

# Task 6: bin and vimrc
for s in git-all git-amend git-copy-branch-name git-credit git-delete-local-merged git-nuke git-promote git-rank-contributors git-review git-track git-undo git-unpushed git-unpushed-stat git-up git-wtf e todo macos-defaults; do
  if [ -x "$P/.local/bin/$s" ]; then pass "bin: $s executable"; else fail "bin: $s missing or not executable"; fi
done
check_nofile "$P/.local/bin/headers"
check_grep ".chezmoiremove: old headers script" "$SRC/.chezmoiremove" '^\.local/bin/headers$'
check_nofile "$P/.local/bin/dot"
check_nofile "$P/.local/bin/gitio"
check_grep "git-delete-local-merged keeps main" "$P/.local/bin/git-delete-local-merged" "main"
dl="$tmp/dl"; git init -q -b main "$dl"; git -C "$dl" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m root
git -C "$dl" branch merged-a; git -C "$dl" branch merged-b; git -C "$dl" checkout -q merged-a
out=$(cd "$dl" && PATH="$P/.local/bin:$PATH" GIT_CONFIG_GLOBAL=/dev/null git delete-local-merged 2>&1); rc=$?
check_eq "git-delete-local-merged: exit 0 while on a merged branch" "$rc" "0"
check_eq "git-delete-local-merged: deletes the other merged branch" "$(git -C "$dl" branch --format='%(refname:short)' | sort | tr '\n' ' ')" "main merged-a "
check_eq "git-delete-local-merged: no error output" "$(printf '%s' "$out" | grep -c 'error')" "0"
check_file "$P/.vimrc"

# Task 7: Brewfile and scripts
check_file "$P/Brewfile"
for pkg in coreutils gh git git-lfs go grc nvm uv vim \
           node yarn cocoapods mobile-dev-inc/tap/maestro facebook/fb/idb-companion openjdk ruby spark \
           ripgrep fd fzf bat eza zoxide zsh-autosuggestions zsh-syntax-highlighting atuin starship xh \
           git-delta difftastic lazygit git-absorb; do
  check_grep "Brewfile: $pkg" "$P/Brewfile" "^brew \"$pkg\""
done
for t in mobile-dev-inc/tap facebook/fb; do check_grep "Brewfile: tap $t" "$P/Brewfile" "^tap \"$t\""; done
for c in iterm2 zed font-jetbrains-mono-nerd-font; do check_grep "Brewfile: cask $c" "$P/Brewfile" "^cask \"$c\""; done
check_eq "Brewfile: exactly three casks" "$(grep -c '^cask ' "$P/Brewfile")" "3"
check_nogrep "Brewfile: no mise yet" "$P/Brewfile" '^brew "mise"'
check_nogrep "Brewfile: no chezmoi" "$P/Brewfile" 'chezmoi'
brew_sh=$(render_tmpl work run_onchange_before_00-homebrew.sh.tmpl)
check_eq "homebrew script: hash comment" "$(printf '%s\n' "$brew_sh" | grep -c '^# Brewfile hash: [0-9a-f]\{64\}$')" "1"
check_eq "homebrew script: bundles from sourceDir" "$(printf '%s\n' "$brew_sh" | grep -c "brew bundle --file \"$SRC/Brewfile\"")" "1"
check_eq "homebrew script: no lfs install" "$(printf '%s\n' "$brew_sh" | grep -c 'git lfs install')" "0"
printf '%s\n' "$brew_sh" > "$tmp/brew.sh"; if sh -n "$tmp/brew.sh"; then pass "homebrew script: sh -n"; else fail "homebrew script: syntax"; fi
if sh -n "$SRC/run_onchange_after_20-uv-tools.sh"; then pass "uv tools script: sh -n"; else fail "uv tools script: syntax"; fi
check_grep "uv tools script: Homebrew uv" "$SRC/run_onchange_after_20-uv-tools.sh" '^uv=/opt/homebrew/bin/uv$'
check_nogrep "uv tools script: no standalone installer" "$SRC/run_onchange_after_20-uv-tools.sh" 'astral.sh'
check_grep "uv tools script: graphifyy" "$SRC/run_onchange_after_20-uv-tools.sh" '^for tool in .*graphifyy'
check_grep "uv tools script: graphify claude skill" "$SRC/run_onchange_after_20-uv-tools.sh" 'graphify" install --platform claude'
keys_w=$(render_tmpl work run_once_before_10-ssh-keys.sh.tmpl)
keys_p=$(render_tmpl personal run_once_before_10-ssh-keys.sh.tmpl)
printf '%s\n' "$keys_w" > "$tmp/keys-w.sh"; printf '%s\n' "$keys_p" > "$tmp/keys-p.sh"
sh -n "$tmp/keys-w.sh" && pass "keys script(work): sh -n" || fail "keys script(work): syntax"
sh -n "$tmp/keys-p.sh" && pass "keys script(personal): sh -n" || fail "keys script(personal): syntax"
check_grep "keys(work): generates personal key" "$tmp/keys-w.sh" 'id_ed25519_personal'
check_nogrep "keys(personal): no personal key" "$tmp/keys-p.sh" 'id_ed25519_personal'
check_nogrep "keys(personal): no gh-personal reminder" "$tmp/keys-p.sh" 'gh-personal'
# Run the work script against a temp HOME with stubbed ssh-keygen/ssh-add.
kh="$tmp/keyhome"; mkdir -p "$kh/.ssh" "$tmp/stubbin"
cat > "$tmp/stubbin/ssh-keygen" <<'STUB'
#!/bin/sh
# -t ed25519 -C comment -f path  -> writes fake key pair
# -y -f path                     -> prints fake pub for that key
case "$1" in
  -y) printf 'ssh-ed25519 REGEN %s\n' "$(cat "$3")" ;;
  *) f=""; c=""; while [ $# -gt 0 ]; do case "$1" in -f) f=$2; shift;; -C) c=$2; shift;; esac; shift; done
     printf 'PRIV-%s\n' "$(basename "$f")" > "$f"; printf 'ssh-ed25519 FAKE %s\n' "$c" > "$f.pub" ;;
esac
STUB
printf '#!/bin/sh\nexit 0\n' > "$tmp/stubbin/ssh-add"
chmod +x "$tmp/stubbin/ssh-keygen" "$tmp/stubbin/ssh-add"
# Pre-existing default private key WITHOUT a .pub (review focus #5).
printf 'PRIV-id_ed25519\n' > "$kh/.ssh/id_ed25519"
out=$(HOME="$kh" PATH="$tmp/stubbin:$PATH" sh "$tmp/keys-w.sh" 2>&1); rc=$?
check_eq "keys(work): runs clean" "$rc" "0"
check_file "$kh/.ssh/id_ed25519.pub"
check_grep "keys(work): regenerated missing pub" "$kh/.ssh/id_ed25519.pub" 'REGEN'
check_file "$kh/.ssh/id_ed25519_personal"
check_file "$kh/.config/git/allowed_signers"
check_eq "allowed_signers: two lines" "$(wc -l < "$kh/.config/git/allowed_signers" | tr -d ' ')" "2"
check_grep "allowed_signers: work line" "$kh/.config/git/allowed_signers" '^work@example.com ssh-ed25519 REGEN'
check_grep "allowed_signers: personal line" "$kh/.config/git/allowed_signers" '^geehaws@gmail.com ssh-ed25519 FAKE geehaws@gmail.com'
check_eq "keys(work): prints new pubkey once" "$(printf '%s\n' "$out" | grep -c 'NEW KEY')" "1"
out2=$(HOME="$kh" PATH="$tmp/stubbin:$PATH" sh "$tmp/keys-w.sh" 2>&1)
check_eq "keys(work): idempotent, no new keys second run" "$(printf '%s\n' "$out2" | grep -c 'NEW KEY')" "0"

# Task 8: install.sh and README
if sh -n "$SRC/install.sh"; then pass "install.sh: sh -n"; else fail "install.sh: syntax"; fi
check_grep "install.sh: official installer to ~/.local/bin" "$SRC/install.sh" 'get.chezmoi.io'
check_fgrep "install.sh: init with explicit URL, no guessing" "$SRC/install.sh" 'init --source "$HOME/.dotfiles" --apply --guess-repo-url=false https://github.com/george-haws/dotfiles.git'
check_fgrep "README: one-liner uses sh -c" "$SRC/README.md" 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/george-haws/dotfiles/master/install.sh)"'
check_grep "README: chezmoi upgrade reminder" "$SRC/README.md" 'chezmoi upgrade'
check_grep "README: SSH clone rule for private personal repos" "$SRC/README.md" 'private personal'
check_nofile "$P/install.sh"
check_nofile "$P/README.md"

# Task 9: doctor
for t in personal work; do
  d="$tmp/$t/.local/bin/dotfiles-doctor"
  check_file "$d"
  [ -x "$d" ] && pass "doctor($t): executable" || fail "doctor($t): not executable"
  sh -n "$d" 2>/dev/null && pass "doctor($t): sh -n" || fail "doctor($t): syntax"
done
check_grep "doctor(work): checks work email" "$W/.local/bin/dotfiles-doctor" 'work@example.com'
check_nogrep "doctor(personal): no work email" "$P/.local/bin/dotfiles-doctor" 'work@example.com'
check_fgrep "doctor: https personal remote case" "$W/.local/bin/dotfiles-doctor" 'https://github.com/$owner/x.git'
check_grep "doctor: chezmoi version check" "$W/.local/bin/dotfiles-doctor" 'releases/latest'
check_grep "doctor: version check is a warning" "$W/.local/bin/dotfiles-doctor" 'warn "chezmoi'

finish
