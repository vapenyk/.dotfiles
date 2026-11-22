#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
[[ $mode == region || $mode == full ]] || { echo "usage: $0 region|full" >&2; exit 2; }

pictures=$(xdg-user-dir PICTURES 2>/dev/null || true)
[[ -z $pictures || $pictures == "$HOME" ]] && pictures="$HOME/Pictures"
directory="$pictures/Screenshots"
mkdir -p -- "$directory"
filename="$directory/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png"

case $mode in
  region)
    geometry=$(slurp) || exit 0
    [[ -n $geometry ]] || exit 0

    grim -g "$geometry" - | satty --filename - --output-filename "$filename" \
      --copy-command 'wl-copy --type image/png' \
      --actions-on-enter save-to-file,save-to-clipboard,exit \
      --disable-notifications
    ;;
  full)
    grim "$filename"
    wl-copy --type image/png < "$filename"
    ;;
esac
