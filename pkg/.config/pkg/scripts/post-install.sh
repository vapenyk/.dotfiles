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

# ── GitHub ───────────────────────────────────────────────────────────────────
gh auth status &>/dev/null || gh auth login

# ── Agent skills ─────────────────────────────────────────────────────────────
npx skills add anthropics/skills

# ── MCP servers (written into ~/.codex, ~/.gemini, ... — never commit those) ─
npx -y add-mcp -g -n playwright @playwright/mcp@latest
npx -y add-mcp -g -n penpot \
  "https://design.penpot.app/mcp/stream?userToken=$(rbw get --field notes penpot-mcp-token | head -n1)"
npx -y add-mcp https://mcp.context7.com/mcp -g -n context7 \
  --header "CONTEXT7_API_KEY: $(rbw get --field notes context7-api-key | head -n1)"

# ── Ollama model ─────────────────────────────────────────────────────────────
systemctl is-active --quiet ollama || sudo systemctl start ollama
model="lfm3:1.7b"
ollama list | awk 'NR>1 {print $1}' | grep -qx "$model" || ollama pull "$model"

echo "post-install done"
