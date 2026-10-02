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
