#!/usr/bin/env bash
# build paru from AUR (fallback when not in official repos)
set -euo pipefail
echo "[pkg] bootstrap-paru — $(date '+%Y-%m-%d %H:%M')"

# makepkg needs the toolchain from base-devel
if ! pacman -Q base-devel &>/dev/null; then
  echo "[pkg] installing base-devel"
  sudo pacman -S --noconfirm --needed base-devel
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git clone --depth=1 https://aur.archlinux.org/paru.git "$tmp"
cd "$tmp" && makepkg -si --noconfirm
