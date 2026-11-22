#!/usr/bin/env bash
# ~/.config/pkg/scripts/after-intel-ultra-125h.sh
# Runs after every pkg sync, so everything here must be idempotent.
set -euo pipefail
echo "[pkg] after-intel-drivers — $(date '+%Y-%m-%d %H:%M')"

# ── power management services ────────────────────────────────────────────────
for unit in thermald intel_lpmd; do
  if ! systemctl list-unit-files "${unit}.service" --no-legend | grep -q .; then
    echo "[pkg] ${unit}: unit not found, skipping"
  elif systemctl is-enabled --quiet "$unit" && systemctl is-active --quiet "$unit"; then
    echo "[pkg] ${unit}: already enabled and running"
  else
    echo "[pkg] enabling ${unit}"
    sudo systemctl enable --now "$unit"
  fi
done

echo "[pkg] after-intel-ultra-125h done"
