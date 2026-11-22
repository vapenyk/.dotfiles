#!/usr/bin/env bash
set -u

APP_ID=org.pkg.hub
SELF=$(readlink -f "$0")

# Prefer paru, then yay.
HELPER=
for h in paru yay; do
  command -v "$h" >/dev/null 2>&1 && { HELPER=$h; break; }
done

launch() {
  exec xdg-terminal-exec --app-id="$APP_ID" --title="Packages" "$SELF" --tui "$1"
}

menu() {
  local choice
  choice=$(printf '%s\n' \
    $'\uf487\u2003Package' \
    $'\uf303\u2003AUR' \
    $'\uf021\u2003Update' \
    $'\uf1f8\u2003Remove' |
    vicinae dmenu -f index -n 'Packages' -p 'Choose action' --no-section --no-footer -W 500 -H 300) || exit 0
  case $choice in
    0) launch install ;;
    1) launch aur ;;
    2) launch update ;;
    3) launch remove ;;
  esac
}

# Mark installed packages and skip duplicates.
mark() {
  awk -v inst="$(pacman -Qq | paste -sd' ')" '
    BEGIN { n = split(inst, a, " "); for (i = 1; i <= n; i++) I[a[i]] }
    !seen[$1]++ { print ($1 in I ? "\033[32m●\033[0m" : " "), $1 }'
}

# Highlight key AUR fields.
preview_aur() {
  "$HELPER" -Si "$1" 2>/dev/null | awk '
    /^(Out Of Date|Out-of-date|Out of Date)/ {
      v = $0; sub(/^[^:]*: */, "", v)
      if (v == "No" || v == "None" || v == "-") print "\033[1;32m" $0 "\033[0m"
      else print "\033[1;31m" $0 "  ⚠ marked out-of-date\033[0m"
      next
    }
    /^(Votes|Popularity|Maintainer|Last Modified)/ { print "\033[1;33m" $0 "\033[0m"; next }
    { print }'
}

# Check for pending config merges and kernel updates.
post_update() {
  echo ":: Post-update checks"

  local files
  if command -v pacdiff >/dev/null 2>&1; then
    files=$(pacdiff -o 2>/dev/null)
  else
    files=$(find /etc \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null)
  fi
  if [ -n "$files" ]; then
    echo "  ⚠ Config files need merging:"
    sed 's/^/      /' <<<"$files"
    if command -v pacdiff >/dev/null 2>&1; then
      echo "    Run: sudo pacdiff"
    else
      echo "    Install pacman-contrib to get pacdiff"
    fi
  else
    echo "  ✓ no .pacnew / .pacsave files"
  fi

  if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
    echo "  ⚠ Kernel was updated (running: $(uname -r)) — reboot recommended"
  else
    echo "  ✓ running kernel is still installed, no reboot needed"
  fi
}

update() {
  local total=1 step=1
  [ -n "$HELPER" ] && total=$((total + 1))
  command -v flatpak >/dev/null 2>&1 && total=$((total + 1))

  echo ":: [$step/$total] Official repositories (pacman -Syu)"
  if ! sudo pacman -Syu; then
    echo
    echo "pacman update failed or was cancelled."
    read -rp "Press Enter to close "
    return 1
  fi

  if [ -n "$HELPER" ]; then
    step=$((step + 1))
    echo
    echo ":: [$step/$total] AUR ($HELPER -Sua)"
    "$HELPER" -Sua
  else
    echo
    echo ":: AUR skipped: neither paru nor yay is installed"
  fi

  if command -v flatpak >/dev/null 2>&1; then
    step=$((step + 1))
    echo
    echo ":: [$step/$total] Flatpak (flatpak update)"
    flatpak update
  fi

  echo
  post_update

  echo
  read -rp "Done. Press Enter to close "
}

tui() {
  local mode=$1 list pkgs action choice

  if [ "$mode" = update ]; then
    update
    return
  fi

  local fzf_args=(
    --multi
    --preview-label='alt-p: toggle description, alt-j/k: scroll, tab: multi-select'
    --preview-label-pos='bottom'
    --preview-window 'down:65%:wrap'
    --bind 'alt-p:toggle-preview'
    --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up'
    --bind 'alt-k:preview-up,alt-j:preview-down'
    --color 'pointer:green,marker:green'
  )

  case $mode in
    install)
      pkgs=$(pacman -Slq | mark | fzf --ansi "${fzf_args[@]}" --preview 'pacman -Sii {-1}' | awk '{print $NF}')
      action=(sudo pacman -S --needed)
      ;;
    aur)
      if [ -z "$HELPER" ]; then
        echo "No AUR helper found: install paru or yay."
        read -rp "Press Enter to close "; exit 1
      fi
      # Exclude official packages from the AUR list.
      list=$(comm -23 <("$HELPER" -Slq | sort -u) <(pacman -Slq | sort -u))
      if [ -z "$list" ]; then
        echo "AUR list is empty: '$HELPER -Slq' returned no AUR packages."
        read -rp "Press Enter to close "; exit 1
      fi
      pkgs=$(mark <<<"$list" | fzf --ansi "${fzf_args[@]}" --preview "$SELF --preview-aur {-1}" | awk '{print $NF}')
      action=("$HELPER" -S --needed)
      ;;
    remove)
      pkgs=$(pacman -Qqe | fzf "${fzf_args[@]}" \
        --prompt 'explicit > ' \
        --header 'alt-a: all installed · alt-e: explicit only' \
        --bind 'alt-a:reload(pacman -Qq)+change-prompt(all > )' \
        --bind 'alt-e:reload(pacman -Qqe)+change-prompt(explicit > )' \
        --preview 'pacman -Qi {1}')
      action=()
      ;;
    *) echo "Unknown mode: $mode"; read -rp "Press Enter to close "; exit 1 ;;
  esac

  if [[ -n $pkgs ]]; then
    mapfile -t list <<<"$pkgs"

    if [ "$mode" = remove ]; then
      local rm_cmd=(sudo pacman)
      [ -n "$HELPER" ] && rm_cmd=("$HELPER")
      choice=$(printf '%s\n' \
        "With dependencies   (${rm_cmd[*]} -Rns)" \
        "Package only        (${rm_cmd[*]} -R)" \
        | fzf --no-multi --prompt 'remove > ' --header "Remove: ${list[*]}") || exit 0
      case $choice in
        "With dependencies"*) action=("${rm_cmd[@]}" -Rns) ;;
        "Package only"*)      action=("${rm_cmd[@]}" -R) ;;
        *) exit 0 ;;
      esac
    fi

    "${action[@]}" "${list[@]}"
    echo
    read -rp "Done. Press Enter to close "
  fi
}

case ${1:-menu} in
  menu)                       menu ;;
  install|aur|update|remove)  launch "$1" ;;
  --tui)                      tui "${2:-install}" ;;
  --preview-aur)              preview_aur "${2:-}" ;;
  *)                          echo "Usage: pkg-vicinae.sh [install|aur|update|remove]"; exit 1 ;;
esac
