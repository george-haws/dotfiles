# Chezmoi Dotfiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a new `~/.dotfiles` repo on chezmoi, with fresh history, that gives a fresh Mac a working shell in one command and selects the GitHub identity (git author, SSH key, signing key, gh account) from each repo's remote URL.

**Architecture:** chezmoi renders a small set of templates from two per-machine answers (`work`, `workEmail`). `~/.gitconfig` carries the machine default identity; on work machines it appends `includeIf "hasconfig:remote.*.url:..."` entries that switch to a personal override for personal-owner remotes. A `gh` shim in `~/.local/bin` applies the same rule to the gh CLI. zsh is an explicit ordered source list under `ZDOTDIR=~/.config/zsh`. Scripts install Homebrew packages and generate per-machine SSH keys.

**Tech Stack:** chezmoi (Go templates), zsh, POSIX sh, git 2.39+, Homebrew, macOS keychain SSH agent.

**Spec:** `docs/superpowers/specs/2026-10-01-chezmoi-dotfiles-design.md`

## Global Constraints

- Platform: macOS on Apple Silicon. Homebrew prefix is `/opt/homebrew`. git is 2.39.5 (Apple) or newer.
- The new repo is built at `~/.dotfiles-next` while the legacy checkout stays live at `~/.dotfiles` as read-only reference; nothing in it is modified. Tests always pass `--source` explicitly, so the build location never matters to them.
- Work identifiers (the work email, company GitHub orgs, the login name in absolute paths) never appear in the repo, including in this plan and in tests. Tests use `work@example.com` and `example-org`.
- **Never `git push`, never create or rename a GitHub repo, never run `gh repo create`.** Those are the user's steps. When the plan reaches them, stop and ask.
- Never write to the real `$HOME` outside the new repo. Tests render into a temp directory with `--destination` and `--persistent-state` pointed at temp paths.
- Personal data is hardcoded in templates: `name = "George Haws"`, `personalEmail = "geehaws@gmail.com"`, `personalOwners = ["george-elliott"]`. The work email appears only in the local chezmoi config and in test fixtures as `work@example.com`.
- Private keys never enter the repo. `~/.ssh` is never managed by chezmoi.
- Every `sshCommand` is exactly: `ssh -i <key> -o IdentitiesOnly=yes -o AddKeysToAgent=yes -o IgnoreUnknown=UseKeychain -o UseKeychain=yes`.
- Git transport: fetch stays HTTPS; `url "git@github.com:".pushInsteadOf = https://github.com/`. `credential.helper = osxkeychain` stays.
- `~/.local/bin` is first on PATH, before `/opt/homebrew/bin`.
- The chezmoi binary in `~/.local/bin` is canonical; chezmoi is not in the Brewfile.
- Commit after every task. Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Zsh and sh files are plain files unless they need `.work`, `.workEmail`, `.personalEmail`, `.personalOwners`, or `.chezmoi.sourceDir`; those are `.tmpl`.

## Review Focus

1. **Owner casing in remote URLs.** GitHub owners are case-insensitive but `hasconfig` globs are case-sensitive, so `https://github.com/George-Elliott/x` resolves to work. The gh shim lowercases before matching (Task 4 tests this); git cannot, so the spec records it as a limit and Task 3's test pins the lowercase form only.
2. **A repo with two remotes, one personal.** `hasconfig` matches any remote, so a work repo with a personal fork remote resolves to personal. Task 3 adds a test that pins this behavior so it is known, not accidental.
3. **gh shim outside a git repo or with no `origin`.** `git remote get-url` fails; the shim must fall through to the work account silently, not print git's error. Task 4 tests this.
4. **Shell startup with no Homebrew installed.** On a fresh machine the shell is first opened after `install.sh` but possibly before `brew bundle` finishes. `path.zsh`, `nvm.zsh`, `completion.zsh` must not error when `/opt/homebrew` is absent. Task 5 tests this with `env -i`.
5. **A private key without its `.pub`.** `cat id_ed25519.pub` under `set -e` would abort the key script and all of apply. Task 7's script regenerates the pub from the private key with `ssh-keygen -y`, and the test runs the rendered script against a temp HOME with a stub `ssh-add`.

---

### Task 0: Create the new repo and seed it

**Files:**
- Create: `~/.dotfiles-next/.gitignore`, `~/.dotfiles-next/LICENSE.md`, `~/.dotfiles-next/docs/superpowers/specs/2026-10-01-chezmoi-dotfiles-design.md`, `~/.dotfiles-next/docs/superpowers/plans/2026-10-01-chezmoi-dotfiles.md`

**Interfaces:**
- Produces: `~/.dotfiles-next` as a git repo on branch `master`. The legacy checkout at `~/.dotfiles` stays untouched and live, so the current shell, credential helper, and signing keep working.

- [ ] **Step 1: Confirm the legacy repo is clean**

Run: `git -C ~/.dotfiles status --short`
Expected: only `?? HANDOFF.md` or nothing. If tracked files are modified, stop and ask.

- [ ] **Step 2: Create the new repo**

```bash
mkdir ~/.dotfiles-next && cd ~/.dotfiles-next && git init -q -b master
git config user.name "George Haws"
git config user.email geehaws@gmail.com
git config commit.gpgsign false
```
The repo-local identity keeps the interim commits personal and unsigned whatever the global config says. Once the new global config is in place, unset these three local settings and re-sign history with `git rebase --root --force-rebase`.

- [ ] **Step 3: Seed docs, license, gitignore**

```bash
mkdir -p docs/superpowers/specs docs/superpowers/plans
cp ~/.dotfiles/docs/superpowers/specs/2026-10-01-chezmoi-dotfiles-design.md docs/superpowers/specs/
cp ~/.dotfiles/docs/superpowers/plans/2026-10-01-chezmoi-dotfiles.md docs/superpowers/plans/
cp ~/.dotfiles/LICENSE.md LICENSE.md
printf '.DS_Store\n' > .gitignore
```

`LICENSE.md` keeps Zach Holman's MIT notice because the git scripts and prompt are his.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Seed repo with design spec, plan, and license

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 1: Test harness and chezmoi install

**Files:**
- Create: `test/render.sh`, `test/fixtures/personal.toml`, `test/fixtures/work.toml`, `test/fixtures/empty.toml`, `test/lib.sh`
- Install: `~/.local/bin/chezmoi`

**Interfaces:**
- Produces: `test/render.sh` renders the source tree into `$tmp/personal` and `$tmp/work` and runs assertion functions. `test/lib.sh` defines `pass`, `fail`, `check_eq desc actual expected`, `check_file path`, `check_nofile path`, `check_grep desc file ERE` (extended regex, so `$` is always an anchor), `check_nogrep desc file ERE`, `check_fgrep desc file literal` (fixed string, for patterns containing `$`), `check_mode desc path mode`, and `finish`. Later tasks append assertions to `test/render.sh` under the marked section.

- [ ] **Step 1: Install chezmoi into ~/.local/bin**

```bash
mkdir -p ~/.local/bin
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
~/.local/bin/chezmoi --version
```
Expected: prints `chezmoi version v2.7x.x` or newer.

- [ ] **Step 2: Write the fixtures**

`test/fixtures/personal.toml`:
```toml
[data]
    work = false
    workEmail = ""
    name = "George Haws"
    personalEmail = "geehaws@gmail.com"
    personalOwners = ["george-elliott"]
```

`test/fixtures/work.toml`:
```toml
[data]
    work = true
    workEmail = "work@example.com"
    name = "George Haws"
    personalEmail = "geehaws@gmail.com"
    personalOwners = ["george-elliott"]
```

`test/fixtures/empty.toml`, used when testing the config template itself so the real `~/.config/chezmoi/chezmoi.toml` is never read:
```toml
# intentionally empty
```

- [ ] **Step 3: Write the assertion library**

`test/lib.sh`:
```sh
# Sourced by test/render.sh. POSIX sh.
fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
check_eq() { # desc actual expected
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: got '$2', want '$3'"; fi
}
check_file() { if [ -f "$1" ]; then pass "exists $1"; else fail "missing $1"; fi; }
check_nofile() { if [ -e "$1" ]; then fail "should not exist $1"; else pass "absent $1"; fi; }
check_grep() { # desc file ERE-pattern
  if grep -Eq -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1: '$3' not in $2"; fi
}
check_nogrep() { # desc file ERE-pattern
  if grep -Eq -- "$3" "$2" 2>/dev/null; then fail "$1: '$3' found in $2"; else pass "$1"; fi
}
check_fgrep() { # desc file literal-string
  if grep -Fq -- "$3" "$2" 2>/dev/null; then pass "$1"; else fail "$1: '$3' not in $2"; fi
}
check_mode() { # desc path mode (e.g. 600)
  check_eq "$1" "$(stat -f %Lp "$2" 2>/dev/null)" "$3"
}
finish() {
  if [ "$fails" -eq 0 ]; then echo "all checks passed"; exit 0; fi
  echo "$fails check(s) failed"; exit 1
}
```

- [ ] **Step 4: Write the harness with its first assertion**

`test/render.sh`:
```sh
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

finish
```
```bash
chmod +x test/render.sh
```

- [ ] **Step 5: Run it to verify it fails**

Run: `./test/render.sh`
Expected: `FAIL missing .../personal/.gitconfig` and exit 1. chezmoi exits 0, and because no `.chezmoiignore` exists yet it copies `docs/`, `test/`, and `LICENSE.md` into the temp destination. That is expected until Task 2 and is not something to fix here.

- [ ] **Step 6: Commit**

```bash
git add test
git commit -m "Add render test harness with fixtures for personal and work machines

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: chezmoi config template and ignore rules

**Files:**
- Create: `.chezmoi.toml.tmpl`, `.chezmoiignore`, `dot_gitconfig.tmpl` (placeholder content only to satisfy the harness; Task 3 writes the real one)
- Modify: `test/render.sh` (append assertions)

**Interfaces:**
- Produces: template data keys `.work` (bool), `.workEmail`, `.name`, `.personalEmail`, `.personalOwners` (list). Ignore rules that hide repo-only files and work-only targets.

- [ ] **Step 1: Append failing assertions**

Append to `test/render.sh` after the assertions marker:
```sh
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `./test/render.sh`
Expected: the `config:` checks fail because `.chezmoi.toml.tmpl` does not exist (execute-template reads an empty file). `check_file .gitconfig` still fails.

- [ ] **Step 3: Write the config template**

`.chezmoi.toml.tmpl`:
```
{{- $work := promptBoolOnce . "work" "Is this a work machine" false -}}
{{- $workEmail := "" -}}
{{- if $work -}}
{{-   $workEmail = promptStringOnce . "workEmail" "Work git email" -}}
{{- end -}}
sourceDir = {{ joinPath .chezmoi.homeDir ".dotfiles" | quote }}

[data]
    work = {{ $work }}
    workEmail = {{ $workEmail | quote }}
    name = "George Haws"
    personalEmail = "geehaws@gmail.com"
    personalOwners = ["george-elliott"]
```

`--promptBool` and `--promptString` are keyed by the prompt text, which is why the test passes `"Is this a work machine=true"`.

- [ ] **Step 4: Write the ignore file**

`.chezmoiignore`:
```
README.md
LICENSE.md
install.sh
docs
test
{{ if not .work }}
.config/git/personal
.local/bin/gh
{{ end }}
```

- [ ] **Step 5: Add a minimal gitconfig so the harness has a file to find**

`dot_gitconfig.tmpl`:
```
[user]
    name = {{ .name }}
```

- [ ] **Step 6: Run to verify it passes**

Run: `./test/render.sh`
Expected: `all checks passed`.

- [ ] **Step 7: Commit**

```bash
git add .chezmoi.toml.tmpl .chezmoiignore dot_gitconfig.tmpl test/render.sh
git commit -m "Add chezmoi config template and ignore rules

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Git identity templates

**Files:**
- Modify: `dot_gitconfig.tmpl` (full content)
- Create: `private_dot_config/git/personal.tmpl`, `dot_config/git/ignore`
- Modify: `test/render.sh`

**Interfaces:**
- Consumes: data keys from Task 2.
- Produces: `~/.gitconfig`, `~/.config/git/personal` (work only, 0600), `~/.config/git/ignore`. The test runs real `git` against the rendered tree by setting `HOME` to the rendered root, so `~` in include paths resolves there.

- [ ] **Step 1: Append failing assertions**

```sh
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
if [ "$user_line" -lt "$inc_line" ]; then pass "work gitconfig: includes after [user]"; else fail "work gitconfig: includes before [user]"; fi
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `./test/render.sh`
Expected: many `FAIL` lines for Task 3; Task 2 checks still pass.

- [ ] **Step 3: Write the gitconfig template**

`dot_gitconfig.tmpl`:
```
[user]
    name = {{ .name }}
    email = {{ if .work }}{{ .workEmail }}{{ else }}{{ .personalEmail }}{{ end }}
    signingkey = ~/.ssh/id_ed25519.pub
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes -o AddKeysToAgent=yes -o IgnoreUnknown=UseKeychain -o UseKeychain=yes
    excludesfile = ~/.config/git/ignore
    editor = vim
[gpg]
    format = ssh
[gpg "ssh"]
    allowedSignersFile = ~/.config/git/allowed_signers
[commit]
    gpgsign = true
[credential]
    helper = osxkeychain
[url "git@github.com:"]
    pushInsteadOf = https://github.com/
[pull]
    rebase = true
[fetch]
    prune = true
[rerere]
    enabled = true
[init]
    defaultBranch = main
[push]
    default = simple
[alias]
    co = checkout
    promote = !git-promote
    wtf = !git-wtf
    rank-contributors = !git-rank-contributors
    count = !git shortlog -sn
[color]
    diff = auto
    status = auto
    branch = auto
    ui = true
[apply]
    whitespace = nowarn
[mergetool]
    keepBackup = false
[difftool]
    prompt = false
[help]
    autocorrect = 1
[filter "lfs"]
    process = git-lfs filter-process
    required = true
    clean = git-lfs clean -- %f
    smudge = git-lfs smudge -- %f
{{- if .work }}
{{- range .personalOwners }}

[includeIf "hasconfig:remote.*.url:https://github.com/{{ . }}/**"]
    path = ~/.config/git/personal
[includeIf "hasconfig:remote.*.url:git@github.com:{{ . }}/**"]
    path = ~/.config/git/personal
[includeIf "hasconfig:remote.*.url:ssh://git@github.com/{{ . }}/**"]
    path = ~/.config/git/personal
{{- end }}
{{- end }}
```

- [ ] **Step 4: Write the personal override and global ignore**

`private_dot_config/git/personal.tmpl`:
```
[user]
    name = {{ .name }}
    email = {{ .personalEmail }}
    signingkey = ~/.ssh/id_ed25519_personal.pub
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_personal -o IdentitiesOnly=yes -o AddKeysToAgent=yes -o IgnoreUnknown=UseKeychain -o UseKeychain=yes
```

`dot_config/git/ignore`:
```
.DS_Store
*~
*.swp

**/.claude/settings.local.json
CLAUDE.local.md
AGENTS.local.md
```

- [ ] **Step 5: Run to verify it passes**

Run: `./test/render.sh`
Expected: `all checks passed`. If `git(work): https personal remote` fails with the work email, check that `HOME="$W"` is in effect and the include path starts with `~/`.

- [ ] **Step 6: Commit**

```bash
git add dot_gitconfig.tmpl private_dot_config dot_config/git/ignore test/render.sh
git commit -m "Add git identity templates selected by remote owner

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: gh shim

**Files:**
- Create: `dot_local/bin/executable_gh.tmpl`
- Modify: `test/render.sh`

**Interfaces:**
- Consumes: `.personalOwners`.
- Produces: `~/.local/bin/gh` on work machines. Honors `DOTFILES_REAL_GH` (default `/opt/homebrew/bin/gh`) so tests can substitute a stub.

- [ ] **Step 1: Append failing assertions**

```sh
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `./test/render.sh`
Expected: `FAIL missing .../work/.local/bin/gh` and the `gh shim:` checks fail.

- [ ] **Step 3: Write the shim**

`dot_local/bin/executable_gh.tmpl`:
```sh
#!/bin/sh
# gh shim, rendered on work machines only. Picks the gh account by the repo's
# remote owner, or by an owner/repo argument. Default is the work account.
# Escape hatch: GH_CONFIG_DIR=~/.config/gh-personal gh ...
real_gh="${DOTFILES_REAL_GH:-/opt/homebrew/bin/gh}"
personal_dir="$HOME/.config/gh-personal"
owners="{{ join " " .personalOwners }}"

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

url=$(lower "$(git remote get-url origin 2>/dev/null || true)")
personal=0
for owner in $owners; do
  owner=$(lower "$owner")
  case "$url" in
    *github.com/"$owner"/*|*github.com:"$owner"/*) personal=1 ;;
  esac
  for arg in "$@"; do
    case "$(lower "$arg")" in
      "$owner"/*) personal=1 ;;
    esac
  done
done

if [ "$personal" = 1 ] && [ -z "${GH_CONFIG_DIR:-}" ]; then
  GH_CONFIG_DIR="$personal_dir" exec "$real_gh" "$@"
fi
exec "$real_gh" "$@"
```

- [ ] **Step 4: Run to verify it passes**

Run: `./test/render.sh`
Expected: `all checks passed`.

- [ ] **Step 5: Commit**

```bash
git add dot_local/bin/executable_gh.tmpl test/render.sh
git commit -m "Add gh shim that picks the account by remote owner

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: zsh

**Files:**
- Create: `dot_zshenv`, `dot_config/zsh/dot_zshrc`, `dot_config/zsh/path.zsh`, `dot_config/zsh/env.zsh`, `dot_config/zsh/options.zsh`, `dot_config/zsh/aliases.zsh`, `dot_config/zsh/git.zsh`, `dot_config/zsh/nvm.zsh`, `dot_config/zsh/prompt.zsh`, `dot_config/zsh/completion.zsh`, `dot_config/zsh/functions/{c,_c,extract,gf,_git-rm}`
- Modify: `test/render.sh`

**Interfaces:**
- Produces: a shell that starts with `ZDOTDIR=~/.config/zsh`. Nothing else depends on these files.

- [ ] **Step 1: Append failing assertions**

```sh
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `./test/render.sh`
Expected: `FAIL missing .../.zshenv` and the rest of the Task 5 block.

- [ ] **Step 3: Write .zshenv and .zshrc**

`dot_zshenv`:
```zsh
export ZDOTDIR="$HOME/.config/zsh"
```

`dot_config/zsh/dot_zshrc`:
```zsh
# Order matters. Each file is sourced by name; nothing is globbed.
for f in path env options aliases git nvm prompt completion; do
  source "$ZDOTDIR/$f.zsh"
done
unset f

# Secrets and machine-local settings stay out of the repo.
[[ -f ~/.localrc ]] && source ~/.localrc
```

- [ ] **Step 4: Write path.zsh, env.zsh, options.zsh**

`dot_config/zsh/path.zsh`:
```zsh
# ~/.local/bin first so the gh shim and git-* scripts win over Homebrew.
typeset -U path
path=(
  "$HOME/.local/bin"
  /opt/homebrew/bin
  /opt/homebrew/sbin
  "$HOME/go/bin"
  $path
)
```

`dot_config/zsh/env.zsh`:
```zsh
export EDITOR='vim'
export PROJECTS=~/src
export GOPATH="$HOME/go"
export LSCOLORS="exfxcxdxbxegedabagacad"
export CLICOLOR=true
```

`dot_config/zsh/options.zsh`:
```zsh
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

setopt NO_BG_NICE
setopt NO_HUP
setopt NO_LIST_BEEP
setopt LOCAL_OPTIONS
setopt LOCAL_TRAPS
setopt HIST_VERIFY
setopt EXTENDED_HISTORY
setopt PROMPT_SUBST
setopt CORRECT
setopt COMPLETE_IN_WORD
setopt IGNORE_EOF
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt COMPLETE_ALIASES
setopt EXTENDED_GLOB   # completion.zsh uses (#q...) glob qualifiers

bindkey '^[^[[D' backward-word
bindkey '^[^[[C' forward-word
bindkey '^[[5D' beginning-of-line
bindkey '^[[5C' end-of-line
bindkey '^[[3~' delete-char
bindkey '^?' backward-delete-char
```

- [ ] **Step 5: Write aliases.zsh and git.zsh**

`dot_config/zsh/aliases.zsh`:
```zsh
alias reload!='exec zsh'

# coreutils ls, when installed via Homebrew.
if (( $+commands[gls] )); then
  alias ls='gls -lF --color'
  alias l='gls -lAh --color'
  alias ll='gls -l --color'
  alias la='gls -A --color'
fi

alias pubkey='pbcopy < ~/.ssh/id_ed25519.pub && echo "=> Public key copied to pasteboard."'
```

`dot_config/zsh/git.zsh`:
```zsh
alias gl='git pull --prune'
alias glog="git log --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative"
alias gp='git push origin HEAD'
alias gd='git diff'
alias gc='git commit'
alias gca='git commit -a'
alias gcm='git commit -m'
alias gco='git checkout'
alias gcb='git copy-branch-name'
alias gb='git branch'
alias gs='git status -sb'
alias gif='git diff --cached'
alias gad='git add'
alias gst='git stash'
alias gsh='git show'
alias gr='git review'
```

- [ ] **Step 6: Write nvm.zsh**

`dot_config/zsh/nvm.zsh`:
```zsh
# Lazy nvm: sourcing nvm.sh costs ~0.85s, so defer it to the first use of
# any node tool. Each stub removes all stubs, loads nvm, then re-runs itself.
export NVM_DIR="$HOME/.nvm"
_nvm_cmds=(nvm node npm npx yarn pnpm corepack)

_nvm_load() {
  unfunction $_nvm_cmds 2>/dev/null
  mkdir -p "$NVM_DIR"
  [[ -s /opt/homebrew/opt/nvm/nvm.sh ]] && source /opt/homebrew/opt/nvm/nvm.sh
}

for _cmd in $_nvm_cmds; do
  eval "${_cmd}() { _nvm_load; ${_cmd} \"\$@\"; }"
done
unset _cmd
```

- [ ] **Step 7: Write prompt.zsh**

`dot_config/zsh/prompt.zsh`:
```zsh
autoload colors && colors
# Prompt after @ehrenmurdick; window title after _why.

if (( $+commands[git] )); then
  git="$commands[git]"
else
  git="/usr/bin/git"
fi

git_prompt_info() {
  local ref
  ref=$($git symbolic-ref HEAD 2>/dev/null) || return
  echo "${ref#refs/heads/}"
}

git_dirty() {
  if ! $git status -s &>/dev/null; then
    echo ""
  elif [[ $($git status --porcelain) == "" ]]; then
    echo "on %{$fg_bold[green]%}$(git_prompt_info)%{$reset_color%}"
  else
    echo "on %{$fg_bold[red]%}$(git_prompt_info)%{$reset_color%}"
  fi
}

unpushed() {
  $git cherry -v @{upstream} 2>/dev/null
}

need_push() {
  if [[ $(unpushed) == "" ]]; then
    echo " "
  else
    echo " with %{$fg_bold[magenta]%}unpushed%{$reset_color%} "
  fi
}

directory_name() {
  echo "%{$fg_bold[cyan]%}%1/%\/%{$reset_color%}"
}

# Sets the terminal window title.
title() {
  local a
  a=${(V)1//\%/\%\%}
  a=$(print -Pn "%40>...>$a" | tr -d "\n")
  case $TERM in
    screen)       print -Pn "\ek$a:$3\e\\" ;;
    xterm*|rxvt)  print -Pn "\e]2;$2\a" ;;
  esac
}

export PROMPT=$'\nin $(directory_name) $(git_dirty)$(need_push)\n› '

precmd() {
  title "zsh" "%m" "%55<...<%~"
  export RPROMPT=""
}
```

- [ ] **Step 8: Write completion.zsh and copy the functions**

`dot_config/zsh/completion.zsh`:
```zsh
fpath=("$ZDOTDIR/functions" $fpath)
autoload -U "$ZDOTDIR"/functions/*(:t)

# Rebuild the completion dump once a day; otherwise trust the cache.
autoload -Uz compinit
_dump="$ZDOTDIR/.zcompdump"
if [[ ! -f "$_dump" || -n "$_dump"(#qN.mh+24) ]]; then
  compinit -d "$_dump"
else
  compinit -C -d "$_dump"
fi
unset _dump

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' insert-tab pending

# grc colorizes common tools.
[[ -f /opt/homebrew/etc/grc.zsh ]] && source /opt/homebrew/etc/grc.zsh
```

```bash
mkdir -p dot_config/zsh/functions
for f in c _c extract gf _git-rm; do cp ~/.dotfiles/functions/$f dot_config/zsh/functions/$f; done
```

- [ ] **Step 9: Run to verify it passes**

Run: `./test/render.sh`
Expected: `all checks passed`. If `zsh: starts with no Homebrew` fails, run the `env -i ... zsh -i -c 'echo started'` line by hand and read the error; a common cause is `autoload -U .../functions/*(:t)` with no files, which the copies in Step 8 prevent.

- [ ] **Step 10: Commit**

```bash
git add dot_zshenv dot_config/zsh test/render.sh
git commit -m "Add zsh config with explicit load order and lazy nvm

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Scripts in ~/.local/bin and vimrc

**Files:**
- Create: `dot_local/bin/executable_git-*` (15 files), `dot_local/bin/executable_e`, `dot_local/bin/executable_headers`, `dot_local/bin/executable_todo`, `dot_local/bin/executable_macos-defaults`, `dot_vimrc`
- Modify: `test/render.sh`

- [ ] **Step 1: Append failing assertions**

```sh
# Task 6: bin and vimrc
for s in git-all git-amend git-copy-branch-name git-credit git-delete-local-merged git-nuke git-promote git-rank-contributors git-review git-track git-undo git-unpushed git-unpushed-stat git-up git-wtf e headers todo macos-defaults; do
  if [ -x "$P/.local/bin/$s" ]; then pass "bin: $s executable"; else fail "bin: $s missing or not executable"; fi
done
check_nofile "$P/.local/bin/dot"
check_nofile "$P/.local/bin/gitio"
check_grep "git-delete-local-merged keeps main" "$P/.local/bin/git-delete-local-merged" "main"
check_file "$P/.vimrc"
```

- [ ] **Step 2: Run to verify it fails**

Run: `./test/render.sh`
Expected: `FAIL bin: git-all missing` and the rest.

- [ ] **Step 3: Copy the scripts with chezmoi's executable_ prefix**

```bash
mkdir -p dot_local/bin
for s in git-all git-amend git-copy-branch-name git-credit git-delete-local-merged git-nuke git-promote git-rank-contributors git-review git-track git-undo git-unpushed git-unpushed-stat git-up git-wtf e headers todo; do
  cp ~/.dotfiles/bin/$s dot_local/bin/executable_$s
done
cp ~/.dotfiles/osx/set-defaults.sh dot_local/bin/executable_macos-defaults
cp ~/.dotfiles/vim/vimrc.symlink dot_vimrc
```

- [ ] **Step 4: Fix git-delete-local-merged to protect main**

Replace the last line of `dot_local/bin/executable_git-delete-local-merged` with:
```sh
git branch --format='%(refname:short)' --merged | grep -vxE 'master|main' | xargs git branch -d
```

- [ ] **Step 5: Run to verify it passes**

Run: `./test/render.sh`
Expected: `all checks passed`.

- [ ] **Step 6: Commit**

```bash
git add dot_local dot_vimrc test/render.sh
git commit -m "Add git subcommands, small scripts, macOS defaults, and vimrc

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Brewfile and bootstrap scripts

**Files:**
- Create: `Brewfile`, `run_onchange_before_00-homebrew.sh.tmpl`, `run_once_before_10-ssh-keys.sh.tmpl`
- Modify: `test/render.sh`

**Interfaces:**
- Produces: `~/Brewfile`. Scripts run before files are written. The key script writes `~/.config/git/allowed_signers`, which `~/.gitconfig` from Task 3 points at.

- [ ] **Step 1: Append failing assertions**

```sh
# Task 7: Brewfile and scripts
check_file "$P/Brewfile"
for pkg in coreutils gh git git-lfs go grc nvm vim; do check_grep "Brewfile: $pkg" "$P/Brewfile" "brew \"$pkg\""; done
check_nogrep "Brewfile: no chezmoi" "$P/Brewfile" 'chezmoi'
brew_sh=$(render_tmpl work run_onchange_before_00-homebrew.sh.tmpl)
check_eq "homebrew script: hash comment" "$(printf '%s\n' "$brew_sh" | grep -c '^# Brewfile hash: [0-9a-f]\{64\}$')" "1"
check_eq "homebrew script: bundles from sourceDir" "$(printf '%s\n' "$brew_sh" | grep -c "brew bundle --file \"$SRC/Brewfile\"")" "1"
check_eq "homebrew script: no lfs install" "$(printf '%s\n' "$brew_sh" | grep -c 'git lfs install')" "0"
printf '%s\n' "$brew_sh" > "$tmp/brew.sh"; if sh -n "$tmp/brew.sh"; then pass "homebrew script: sh -n"; else fail "homebrew script: syntax"; fi
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `./test/render.sh`
Expected: `FAIL missing .../Brewfile`, and `render_tmpl` fails on the missing script templates.

- [ ] **Step 3: Write the Brewfile and the Homebrew script**

`Brewfile`:
```ruby
brew "coreutils"
brew "gh"
brew "git"
brew "git-lfs"
brew "go"
brew "grc"
brew "nvm"
brew "vim"
```

`run_onchange_before_00-homebrew.sh.tmpl`:
```sh
#!/bin/sh
# Brewfile hash: {{ include "Brewfile" | sha256sum }}
# Runs before chezmoi writes any file, so the Brewfile is read from the source
# directory. The hash above makes chezmoi rerun this when the Brewfile changes.
set -eu

if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ]; then
  echo "Installing Homebrew. It will ask for your password for sudo."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

brew bundle --file "{{ .chezmoi.sourceDir }}/Brewfile"
```

- [ ] **Step 4: Write the SSH keys script**

`run_once_before_10-ssh-keys.sh.tmpl`:
```sh
#!/bin/sh
# Generates per-machine SSH keys, loads them into the keychain agent, and writes
# the allowed_signers file git uses to verify SSH signatures. Idempotent.
set -eu

default_email="{{ if .work }}{{ .workEmail }}{{ else }}{{ .personalEmail }}{{ end }}"
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

ensure_key() { # path comment
  if [ ! -f "$1" ]; then
    ssh-keygen -t ed25519 -C "$2" -f "$1"
    echo
    echo "NEW KEY $1.pub. Add it to GitHub twice: as an authentication key and as a signing key."
    cat "$1.pub"
    echo
  elif [ ! -f "$1.pub" ]; then
    ssh-keygen -y -f "$1" > "$1.pub"
  fi
}

ensure_key "$HOME/.ssh/id_ed25519" "$default_email"
{{- if .work }}
ensure_key "$HOME/.ssh/id_ed25519_personal" "{{ .personalEmail }}"
{{- end }}

for k in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519_personal"; do
  [ -f "$k" ] && ssh-add --apple-use-keychain "$k" >/dev/null 2>&1 || true
done

mkdir -p "$HOME/.config/git"
{
{{- if .work }}
  printf '%s %s\n' "{{ .workEmail }}" "$(cat "$HOME/.ssh/id_ed25519.pub")"
  printf '%s %s\n' "{{ .personalEmail }}" "$(cat "$HOME/.ssh/id_ed25519_personal.pub")"
{{- else }}
  printf '%s %s\n' "{{ .personalEmail }}" "$(cat "$HOME/.ssh/id_ed25519.pub")"
{{- end }}
} > "$HOME/.config/git/allowed_signers"
{{- if .work }}

echo "Reminder (once per work machine, from ~/.dotfiles):"
echo "  GH_CONFIG_DIR=\$HOME/.config/gh-personal gh auth login"
{{- end }}
```

- [ ] **Step 5: Run to verify it passes**

Run: `./test/render.sh`
Expected: `all checks passed`. If `homebrew script: hash comment` fails, confirm the `include` path is `"Brewfile"` relative to the source root.

- [ ] **Step 6: Commit**

```bash
git add Brewfile run_onchange_before_00-homebrew.sh.tmpl run_once_before_10-ssh-keys.sh.tmpl test/render.sh
git commit -m "Add Brewfile, Homebrew bootstrap, and SSH key generation scripts

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: install.sh and README

**Files:**
- Create: `install.sh`, `README.md`
- Modify: `test/render.sh`

- [ ] **Step 1: Append failing assertions**

```sh
# Task 8: install.sh and README
if sh -n "$SRC/install.sh"; then pass "install.sh: sh -n"; else fail "install.sh: syntax"; fi
check_grep "install.sh: official installer to ~/.local/bin" "$SRC/install.sh" 'get.chezmoi.io'
check_fgrep "install.sh: init with source" "$SRC/install.sh" 'init --source "$HOME/.dotfiles" --apply george-elliott'
check_fgrep "README: one-liner uses sh -c" "$SRC/README.md" 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/george-elliott/dotfiles/master/install.sh)"'
check_grep "README: chezmoi upgrade reminder" "$SRC/README.md" 'chezmoi upgrade'
check_grep "README: SSH clone rule for private personal repos" "$SRC/README.md" 'private personal'
check_nofile "$P/install.sh"
check_nofile "$P/README.md"
```

- [ ] **Step 2: Run to verify it fails**

Run: `./test/render.sh`
Expected: `install.sh` and `README` checks fail.

- [ ] **Step 3: Write install.sh**

`install.sh`:
```sh
#!/bin/sh
# Fresh-machine bootstrap. Run as:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/george-elliott/dotfiles/master/install.sh)"
# The sh -c "$(...)" form keeps stdin on the terminal so chezmoi can prompt.
set -eu

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Installing the Xcode Command Line Tools. Re-run this script when the installer finishes."
  xcode-select --install
  exit 1
fi

mkdir -p "$HOME/.local/bin"
if [ ! -x "$HOME/.local/bin/chezmoi" ]; then
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
fi

exec "$HOME/.local/bin/chezmoi" init --source "$HOME/.dotfiles" --apply george-elliott
```
```bash
chmod +x install.sh
```

- [ ] **Step 4: Write README.md**

`README.md`:
```markdown
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
```

- [ ] **Step 5: Run to verify it passes**

Run: `./test/render.sh`
Expected: `all checks passed`.

- [ ] **Step 6: Commit**

```bash
git add install.sh README.md test/render.sh
git commit -m "Add one-line installer and README

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: dotfiles-doctor

**Files:**
- Create: `dot_local/bin/executable_dotfiles-doctor.tmpl`
- Modify: `test/render.sh`

**Interfaces:**
- Consumes: `.work`, `.workEmail`, `.personalEmail`, `.personalOwners`.
- Produces: `~/.local/bin/dotfiles-doctor`, exit 0 when every check passes.

- [ ] **Step 1: Append failing assertions**

```sh
# Task 9: doctor
for t in personal work; do
  d="$tmp/$t/.local/bin/dotfiles-doctor"
  check_file "$d"
  [ -x "$d" ] && pass "doctor($t): executable" || fail "doctor($t): not executable"
  sh -n "$d" && pass "doctor($t): sh -n" || fail "doctor($t): syntax"
done
check_grep "doctor(work): checks work email" "$W/.local/bin/dotfiles-doctor" 'work@example.com'
check_nogrep "doctor(personal): no work email" "$P/.local/bin/dotfiles-doctor" 'work@example.com'
check_fgrep "doctor: https personal remote case" "$W/.local/bin/dotfiles-doctor" 'https://github.com/$owner/x.git'
check_grep "doctor: chezmoi version check" "$W/.local/bin/dotfiles-doctor" 'releases/latest'
check_grep "doctor: version check is a warning" "$W/.local/bin/dotfiles-doctor" 'warn "chezmoi'
```

- [ ] **Step 2: Run to verify it fails**

Run: `./test/render.sh`
Expected: `FAIL missing .../dotfiles-doctor`.

- [ ] **Step 3: Write the doctor**

`dot_local/bin/executable_dotfiles-doctor.tmpl`:
```sh
#!/bin/sh
# Verifies the live machine: git identity by remote, SSH keys, gh account,
# signing, PATH, shell startup, and chezmoi freshness. Exit 1 on any failure.
set -u

work={{ .work }}
personal_email="{{ .personalEmail }}"
work_email="{{ .workEmail }}"
owner="{{ index .personalOwners 0 }}"
fails=0
pass() { printf '  [ OK ] %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; fails=$((fails + 1)); }
check() { # desc actual expected
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi
}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
if [ "$work" = true ]; then default_email="$work_email"; else default_email="$personal_email"; fi

echo "git identity"
git init -q "$tmp/none"
check "no remote -> machine default" "$(git -C "$tmp/none" config user.email)" "$default_email"
git init -q "$tmp/https"; git -C "$tmp/https" remote add origin "https://github.com/$owner/x.git"
check "https personal remote -> personal email" "$(git -C "$tmp/https" config user.email)" "$personal_email"
check "https personal remote -> ssh push url" "$(git -C "$tmp/https" remote get-url --push origin)" "git@github.com:$owner/x.git"
check "https personal remote -> https fetch url" "$(git -C "$tmp/https" remote get-url origin)" "https://github.com/$owner/x.git"
check "~/.dotfiles -> personal email" "$(git -C "$HOME/.dotfiles" config user.email)" "$personal_email"
if [ "$work" = true ]; then
  check "https personal remote -> personal key" "$(git -C "$tmp/https" config user.signingkey)" "~/.ssh/id_ed25519_personal.pub"
  workrepo=""
  for d in "$HOME"/src/*/; do
    [ -d "$d/.git" ] || continue
    case "$(git -C "$d" remote get-url origin 2>/dev/null)" in *"/$owner/"*|*":$owner/"*) continue;; esac
    workrepo="$d"; break
  done
  if [ -n "$workrepo" ]; then
    check "$workrepo -> work email" "$(git -C "$workrepo" config user.email)" "$work_email"
    check "$workrepo -> default key" "$(git -C "$workrepo" config user.signingkey)" "~/.ssh/id_ed25519.pub"
  else
    pass "no work repo under ~/src to check (skipped)"
  fi
fi

echo "signing"
git -C "$tmp/https" commit -q --allow-empty -m doctor 2>"$tmp/sign.err" \
  && [ "$(git -C "$tmp/https" log -1 --format=%G?)" = "G" ] \
  && pass "empty commit on a personal remote verifies" \
  || fail "signed commit does not verify: $(cat "$tmp/sign.err" | tr '\n' ' ')"

echo "ssh"
ssh_user() { ssh -T -o BatchMode=yes -o IdentitiesOnly=yes -i "$1" git@github.com 2>&1 | sed -n 's/^Hi \([^!]*\)!.*/\1/p'; }
u=$(ssh_user "$HOME/.ssh/id_ed25519")
if [ "$work" = true ]; then
  [ -n "$u" ] && [ "$u" != "$owner" ] && pass "default key -> work account ($u)" || fail "default key -> '$u', want a work account"
  check "personal key -> $owner" "$(ssh_user "$HOME/.ssh/id_ed25519_personal")" "$owner"
else
  check "default key -> $owner" "$u" "$owner"
fi

echo "gh"
gh_user() { gh auth status 2>&1 | sed -n 's/.*account \([^ ]*\) .*/\1/p' | head -1; }
check "gh in ~/.dotfiles -> $owner" "$(cd "$HOME/.dotfiles" && gh_user)" "$owner"
if [ "$work" = true ] && [ -n "${workrepo:-}" ]; then
  g=$(cd "$workrepo" && gh_user)
  [ -n "$g" ] && [ "$g" != "$owner" ] && pass "gh in work repo -> work account ($g)" || fail "gh in work repo -> '$g'"
fi

echo "path"
check "git resolves to Homebrew" "$(command -v git)" "/opt/homebrew/bin/git"
case ":$PATH:" in *:./bin:*) fail "PATH contains ./bin" ;; *) pass "no ./bin in PATH" ;; esac
dups=$(printf '%s\n' "$PATH" | tr ':' '\n' | sort | uniq -d | tr '\n' ' ')
[ -z "$dups" ] && pass "no duplicate PATH entries" || fail "duplicate PATH entries: $dups"

echo "startup"
secs=$(zsh -c 'zmodload zsh/datetime; s=$EPOCHREALTIME; for i in 1 2 3 4 5; do zsh -i -c exit; done; printf "%.3f" $(( (EPOCHREALTIME - s) / 5 ))')
if awk "BEGIN{exit !($secs < 0.3)}"; then pass "interactive shell starts in ${secs}s"; else fail "interactive shell takes ${secs}s, want < 0.3"; fi

echo "chezmoi"
latest=$(curl -fsS --max-time 3 https://api.github.com/repos/twpayne/chezmoi/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
current=$(chezmoi --version 2>/dev/null | sed -n 's/.*version v\{0,1\}\([0-9][0-9.]*\).*/\1/p')
if [ -z "$latest" ]; then pass "version check skipped (offline)"
elif [ "$latest" = "$current" ]; then pass "chezmoi $current is current"
else warn "chezmoi $current installed, $latest available: run chezmoi upgrade"; fi

echo
[ "$fails" -eq 0 ] && echo "all checks passed" || { echo "$fails check(s) failed"; exit 1; }
```

- [ ] **Step 4: Run to verify it passes**

Run: `./test/render.sh`
Expected: `all checks passed`. The doctor itself only runs for real on a live machine.

- [ ] **Step 5: Commit**

```bash
git add dot_local/bin/executable_dotfiles-doctor.tmpl test/render.sh
git commit -m "Add dotfiles-doctor live verification script

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
