#!/usr/bin/env bash
# runs before every pkg sync
set -euo pipefail
echo "[pkg] before-sync — $(date '+%Y-%m-%d %H:%M')"
# cd ~/dotfiles && git pull --ff-only
