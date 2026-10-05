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
  mkdir -p "$tmp/$1" "$tmp/$1-home"
  HOME="$tmp/$1-home" chezmoi --config "$SRC/test/fixtures/$1.toml" \
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
check_eq "starship: branch modules never time out" "$(grep -c '^ignore_timeout = true$' "$P/.config/starship.toml")" "2"
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
# Task 9 (2026-10-04): README covers the new tools
check_grep "README: cask adopt step" "$SRC/README.md" 'brew install --cask --adopt iterm2 zed'
check_grep "README: atuin import" "$SRC/README.md" 'atuin import auto'
check_grep "README: capture after an app edits its settings" "$SRC/README.md" 'dotfiles-capture claude'
check_fgrep "README: seed the local file from the backup" "$SRC/README.md" 'dotfiles-capture --from ~/.claude/settings.json.pre-chezmoi claude'
check_grep "README: Nerd Font set by hand" "$SRC/README.md" 'JetBrains Mono Nerd Font'
check_nogrep "README: re-add is not the route for app settings" "$SRC/README.md" 're-add ~/.claude'
check_fgrep "README: skills question points at the modern CLI tools spec" "$SRC/README.md" 'Future work in `docs/superpowers/specs/2026-10-04-modern-cli-tools-design.md`'

# Task 5 (2026-10-04): Claude Code and Zed settings
check_nofile "$P/.shared"
# chezmoi parses every file in .chezmoitemplates as a template, so a shared
# value holding {{ would break every apply. .shared is read raw.
rs="$tmp/regress-src"; mkdir -p "$rs" "$tmp/regress" "$tmp/regress-home"
cp -R "$SRC"/* "$SRC"/.chezmoi* "$SRC/.shared" "$rs/"
rule="Bash(docker inspect --format '{{json .Config}}':*)"
jq --arg r "$rule" '.permissions.allow = [$r]' "$SRC/.shared/claude-settings.json" > "$rs/.shared/claude-settings.json"
regress() { HOME="$tmp/regress-home" chezmoi --config "$SRC/test/fixtures/work.toml" --source "$rs" --destination "$tmp/regress" --persistent-state "$tmp/regress.boltdb" "$@"; }
if regress managed >/dev/null; then pass "shared: a value holding {{ does not break chezmoi"; else fail "shared: chezmoi managed fails on a value holding {{"; fi
check_eq "shared: a value holding {{ renders intact" "$(regress cat "$tmp/regress/.claude/settings.json" | jq -r '.permissions.allow[0]')" "$rule"
cshared="$SRC/.shared/claude-settings.json"
zshared="$SRC/.shared/zed-settings.json"
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

# Task 6 (2026-10-04): dotfiles-capture
cap="$P/.local/bin/dotfiles-capture"
check_file "$cap"
[ -x "$cap" ] && pass "capture: executable" || fail "capture: not executable"
sh -n "$cap" && pass "capture: sh -n" || fail "capture: syntax"
# A scratch copy of the source, because --shared writes to it. Its shared files
# belong to these tests, so editing the real ones never breaks them. A chezmoi
# wrapper points every call the script makes at that copy and at a fake home.
cs="$tmp/capture-src"; mkdir -p "$cs"; (cd "$SRC" && tar --exclude .git -cf - .) | (cd "$cs" && tar -xf -)
csh="$cs/.shared/claude-settings.json"
echo '{"enabledPlugins":{"a@m":true,"b@m":true},"model":"shared-model","permissions":{"allow":["Bash(ls:*)","Bash(rm:*)"]},"theme":"dark"}' > "$csh"
echo '{"base_keymap":"VSCode","ui_font_size":16}' > "$cs/.shared/zed-settings.json"
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
cl() { jq -c -r "$1" "$ch/.config/chezmoi/claude-settings.local.json" 2>&1; }
zl() { jq -c -r "$1" "$ch/.config/chezmoi/zed-settings.local.json" 2>&1; }

use_machine work
mkdir -p "$ch/.claude"
printf '{"model":"work-model","autoMode":{"environment":"WORK"},"permissions":{"allow":["Bash(worktool:*)"]}}\n' > "$ch/.claude/settings.json"
capture claude >/dev/null; rc=$?
check_eq "capture: refused before chezmoi has written the file" "$rc" "1"
HOME="$ch" sh "$SRC/run_once_before_20-settings-backup.sh" >/dev/null
cz apply --force "$ch/.claude/settings.json"
(cd "$ch/.claude" && capture --from settings.json.pre-chezmoi claude) >/dev/null; rc=$?
check_eq "capture --from a relative backup path: exit 0" "$rc" "0"
check_eq "capture --from backup: work values seeded into the local file" "$(cl '.model + " " + .autoMode.environment')" "work-model WORK"
check_eq "capture --from backup: only the permissions the shared file lacks" "$(cl .permissions.allow)" '["Bash(worktool:*)"]'
check_mode "capture: local file is 0600" "$ch/.config/chezmoi/claude-settings.local.json" "600"
capture --check claude >/dev/null; rc=$?
check_eq "capture --from backup: live file matches the repo afterwards" "$rc" "0"

setjson "$ch/.claude/settings.json" '.testFlag = false'
out=$(capture --check claude); rc=$?
check_eq "capture --check: in-place change exits 1" "$rc" "1"
case "$out" in *"changed in place"*testFlag*) pass "capture --check: names the side and the key";; *) fail "capture --check: got '$out'";; esac
before=$(cat "$csh")
capture --shared claude >/dev/null; rc=$?
check_eq "capture --shared: refused on a work machine" "$rc" "1"
check_eq "capture --shared: shared file untouched on a work machine" "$(cat "$csh")" "$before"
capture claude >/dev/null; rc=$?
check_eq "capture: exit 0" "$rc" "0"
check_eq "capture: in-place key lands in the local file" "$(cl .testFlag)" "false"
capture --check claude >/dev/null; rc=$?
check_eq "capture: live file matches the repo afterwards" "$rc" "0"

# Only what differs from the shared file goes into the local file, so the
# shared file's later changes still arrive, including a permission it drops.
setjson "$ch/.claude/settings.json" '.permissions.allow += ["Bash(git:*)"] | .enabledPlugins["b@m"] = false'
capture claude >/dev/null
check_eq "capture: a permission list keeps only the rules the shared file lacks" "$(cl .permissions.allow)" '["Bash(worktool:*)","Bash(git:*)"]'
check_eq "capture: a map keeps only its differing entries" "$(cl .enabledPlugins)" '{"b@m":false}'
setjson "$csh" '.permissions.allow -= ["Bash(rm:*)"]'
check_eq "capture: a permission the shared file drops is no longer granted" "$(cz cat "$ch/.claude/settings.json" | jq -c .permissions.allow)" '["Bash(ls:*)","Bash(worktool:*)","Bash(git:*)"]'
cz apply --force "$ch/.claude/settings.json"

# An app rewrites the file with the same values in another layout.
jq -c . "$ch/.claude/settings.json" > "$tmp/compact" && cat "$tmp/compact" > "$ch/.claude/settings.json"
capture claude >/dev/null; rc=$?
check_eq "capture: a layout-only rewrite exits 0" "$rc" "0"
cz verify "$ch/.claude/settings.json" >/dev/null 2>&1; rc=$?
check_eq "capture: a layout-only rewrite gets chezmoi's layout back" "$rc" "0"

setjson "$csh" '.repoKey = "repo"'
out=$(capture claude)
case "$out" in *"nothing changed in place"*) pass "capture: a repo-side change is not captured";; *) fail "capture: repo-side change: got '$out'";; esac
setjson "$ch/.claude/settings.json" '.theme = "in-place"'
capture claude >/dev/null; rc=$?
check_eq "capture: both sides changed and no KEY -> refused" "$rc" "1"
out=$(capture claude theme)
check_eq "capture KEY: the named key is captured" "$(cl .theme)" "in-place"
check_eq "capture KEY: the repo-side key is not" "$(cl 'has("repoKey")')" "false"
case "$out" in
  *"removed in place"*) fail "capture KEY: a key the repo added is called removed in place";;
  *"added in the repo or deleted in place"*repoKey*) pass "capture KEY: a key the repo added may be the repo's";;
  *) fail "capture KEY: got '$out'";;
esac
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
check_eq "capture --shared: the key moves to the shared file" "$(jq -r .ui_font_size "$cs/.shared/zed-settings.json")" "22"
check_eq "capture --shared: and out of the local file" "$(zl 'has("ui_font_size")')" "false"
capture --check zed >/dev/null; rc=$?
check_eq "capture --shared: live file matches the repo afterwards" "$rc" "0"

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
# Task 8 (2026-10-04): new doctor checks
d="$P/.local/bin/dotfiles-doctor"
check_fgrep "doctor: brew bundle check lists what is missing" "$d" "brew bundle check --file \"$SRC/Brewfile\" --no-upgrade --verbose"
check_fgrep "doctor: brew bundle check never auto-updates Homebrew" "$d" 'HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check'
check_grep "doctor: new tools on PATH" "$d" 'for t in rg fd fzf bat eza zoxide atuin starship xh delta difft lazygit git-absorb'
check_grep "doctor: chezmoi verify on starship and atuin" "$d" 'chezmoi verify ~/.config/starship.toml ~/.config/atuin/config.toml'
check_grep "doctor: settings drift through dotfiles-capture" "$d" 'dotfiles-capture" --check "\$app"'
check_grep "doctor: settings drift is a warning" "$d" 'warn "\$out"'
check_grep "doctor: statusLine wired" "$d" "jq -r '.statusLine.command // empty'"
check_grep "doctor: statusline runs" "$d" 'claude-statusline" 2>/dev/null'

finish
