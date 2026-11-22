#!/usr/bin/env bash
# ~/.config/pkg/scripts/after-sync.sh
# Runs after every pkg sync, so everything here must be idempotent.
set -euo pipefail
echo "[pkg] after-sync — $(date '+%Y-%m-%d %H:%M')"

# ── system services (island needs these) ─────────────────────────────────────
for unit in NetworkManager bluetooth upower power-profiles-daemon; do
  if ! systemctl list-unit-files "${unit}.service" --no-legend | grep -q .; then
    echo "[pkg] ${unit}: unit not found, skipping"
  elif systemctl is-enabled --quiet "$unit" && systemctl is-active --quiet "$unit"; then
    echo "[pkg] ${unit}: already enabled and running"
  else
    echo "[pkg] enabling ${unit}"
    sudo systemctl enable --now "$unit"
  fi
done

# ── Superwhisper (not packaged, official install script) ─────────────────────
# if command -v superwhisper &>/dev/null; then
#   echo "[pkg] superwhisper already installed, skipping"
# else
#   echo "[pkg] installing superwhisper..."
#   curl -fsSL https://tux.superwhisper.com/install.sh | sh
# fi

echo "[pkg] after-sync done"
