#!/bin/bash
# Right-click entry point: a small menu over city selection and reminders.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

choice=$(omarchy-menu-select "Salah Time Settings" "Change City" "Manage Reminders") || exit 0

case "$choice" in
  "Change City") "$DIR/scripts/pick_city.sh" ;;
  "Manage Reminders") "$DIR/scripts/manage_reminders.sh" ;;
esac
