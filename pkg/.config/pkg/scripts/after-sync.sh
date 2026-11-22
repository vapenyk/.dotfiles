#!/usr/bin/env bash
# ~/.config/pkg/scripts/after-sync.sh
# Runs after every pkg sync, so everything here must be idempotent.
set -euo pipefail
echo "[pkg] after-sync — $(date '+%Y-%m-%d %H:%M')"

# ── dotfiles: lay out main/pkg/copy/system (needs packages installed first) ──
# pkg itself is linked by `dots apply pkg`, so that first run stays manual.
dots="$HOME/.dotfiles/dots/dots.py"
if [[ -x "$dots" ]]; then
  "$dots" apply all || echo "[pkg] dots apply: some files need a decision, run it by hand"
else
  echo "[pkg] $dots not found, skipping dots apply"
fi

# ── system services (island needs these; ollama for local LLM) ───────────────
for unit in NetworkManager bluetooth upower power-profiles-daemon ollama; do
  if ! systemctl list-unit-files "${unit}.service" --no-legend | grep -q .; then
    echo "[pkg] ${unit}: unit not found, skipping"
  elif systemctl is-enabled --quiet "$unit" && systemctl is-active --quiet "$unit"; then
    echo "[pkg] ${unit}: already enabled and running"
  else
    echo "[pkg] enabling ${unit}"
    sudo systemctl enable --now "$unit"
  fi
done

# ── mshell (Quickshell config, lives in git, not packaged) ───────────────────
# mshell_dir="$HOME/.config/quickshell/mshell"
# if [[ -d "$mshell_dir/.git" ]]; then
#   git -C "$mshell_dir" pull --ff-only \
#     || echo "[pkg] mshell: pull failed (local changes?), leaving as is"
# else
#   echo "[pkg] cloning mshell"
#   mkdir -p "$(dirname "$mshell_dir")"
#   git clone https://github.com/vapenyk/mshell.git "$mshell_dir"
# fi

# ── mise tools from ~/.config/mise/config.toml (installs only what is missing)
if command -v mise &>/dev/null; then
  mise install
fi

# ── Superwhisper (not packaged, official install script) ─────────────────────
# if command -v superwhisper &>/dev/null; then
#   echo "[pkg] superwhisper already installed, skipping"
# else
#   echo "[pkg] installing superwhisper..."
#   curl -fsSL https://tux.superwhisper.com/install.sh | sh
# fi

# ── reminder: post-install not done yet, or the script changed since ─────────
post="$HOME/.dotfiles/scripts/post-install.sh"
marker="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/post-install.sha256"
if [[ -f "$post" && "$(sha256sum "$post" | cut -d' ' -f1)" != "$(cat "$marker" 2>/dev/null)" ]]; then
  echo "[pkg] next: reboot, log into the session, then run $post (rbw, gh, agents, ollama model)"
fi

echo "[pkg] after-sync done"
