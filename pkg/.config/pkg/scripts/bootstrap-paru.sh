#!/usr/bin/env bash
# build paru from AUR (fallback when not in official repos)
set -euo pipefail
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git clone --depth=1 https://aur.archlinux.org/paru.git "$tmp"
cd "$tmp" && makepkg -si --noconfirm
