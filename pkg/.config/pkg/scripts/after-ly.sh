#!/usr/bin/env bash
set -euo pipefail
echo "[pkg] after-ly — $(date '+%Y-%m-%d %H:%M')"

sudo systemctl enable ly@tty2.service

echo "[pkg] after-ly done — reboot to see the greeter"
