#!/usr/bin/env bash
# scripts/post-install.sh — the steps that need YOUR accounts/secrets.
# Run once by hand after `pkg sync`. Secrets come from Bitwarden (rbw)
# at run time, so nothing sensitive lands in the repo or in shell history.
#
# Bitwarden notes expected (key on the FIRST line of the note):
#   penpot-mcp-token, context7-api-key
set -euo pipefail

# gh and npx come from mise
mise up

# ── Bitwarden ────────────────────────────────────────────────────────────────
# (email comes from copy/.config/rbw/config.json)
rbw unlocked &>/dev/null || rbw unlock
rbw sync

# ── Git identity + SSH commit signing (needs rbw unlocked) ───────────────────
if [[ -z "$(git config --global user.name || true)" \
   || -z "$(git config --global user.email || true)" \
   || -z "$(git config --global user.signingkey || true)" \
   || "$(git config --global commit.gpgsign || true)" != "true" ]]; then
  "$(dirname "${BASH_SOURCE[0]}")/setup-git-config.sh"
  [[ "$(git config --global commit.gpgsign || true)" == "true" ]] \
    || { echo "git signing not configured, aborting"; exit 1; }
fi

# ── GitHub ───────────────────────────────────────────────────────────────────
gh auth status &>/dev/null || gh auth login

# ── Agent skills (only the ones that are missing) ────────────────────────────
skills_dir="$HOME/.agents/skills"
missing=()
for s in canvas-design frontend-design mcp-builder skill-creator theme-factory web-artifacts-builder; do
  [[ -d "$skills_dir/$s" ]] || missing+=(--skill "$s")
done
(( ${#missing[@]} == 0 )) || npx skills add anthropics/skills -g -y "${missing[@]}"
[[ -d "$skills_dir/find-skills" ]] || npx skills add vercel-labs/skills --skill find-skills -g -y

# ── MCP servers: each one is added once ──────────────────────────────────────
pi_state="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/post-install"
mkdir -p "$pi_state"
once() {  # once <id> <command...> — skips if <id> already succeeded
  local id=$1; shift
  if [[ -e "$pi_state/$id" ]]; then echo "skip: $id"; return 0; fi
  "$@" && touch "$pi_state/$id"
}

add_playwright() { npx -y add-mcp -g -n playwright @playwright/mcp@latest; }
add_penpot() {
  local t
  t=$(rbw get --field notes penpot-mcp-token | head -n1) || return 1
  [[ -n "$t" ]] || { echo "penpot-mcp-token is empty"; return 1; }
  npx -y add-mcp -g -n penpot "https://design.penpot.app/mcp/stream?userToken=$t"
}
add_context7() {
  local k
  k=$(rbw get --field notes context7-api-key | head -n1) || return 1
  [[ -n "$k" ]] || { echo "context7-api-key is empty"; return 1; }
  npx -y add-mcp https://mcp.context7.com/mcp -g -n context7 \
    --header "CONTEXT7_API_KEY: $k"
}

once mcp-playwright add_playwright
once mcp-penpot     add_penpot
once mcp-context7   add_context7

# ── Ollama model ─────────────────────────────────────────────────────────────
systemctl is-active --quiet ollama || sudo systemctl start ollama
model="lfm3:1.7b"
ollama list | awk 'NR>1 {print $1}' | grep -qx "$model" || ollama pull "$model"

state="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
mkdir -p "$state"
sha256sum "${BASH_SOURCE[0]}" | cut -d' ' -f1 > "$state/post-install.sha256"

echo "post-install done"
