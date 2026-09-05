#!/bin/bash
# Lets the user pick a city from the live islom.uz region list, saves the
# choice, and refreshes today's schedule for it immediately.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PLUGIN_DIR/scripts/env.sh"

CONFIG_DIR="$HOME/.config/omarchy-salah-time"
CACHE_DIR="$HOME/.cache/omarchy-salah-time"
CONFIG_FILE="$CONFIG_DIR/config.json"
REGIONS_FILE="$CACHE_DIR/regions.json"

mkdir -p "$CONFIG_DIR" "$CACHE_DIR"

if [ ! -x "$VENV_PY" ]; then
  "$PLUGIN_DIR/scripts/bootstrap.sh"
fi

if [ ! -f "$REGIONS_FILE" ]; then
  "$VENV_PY" "$PLUGIN_DIR/scripts/refresh_regions.py"
fi

mapfile -t cities < <("$VENV_PY" -c "import json; print('\n'.join(json.load(open('$REGIONS_FILE'))['cities']))")

if [ ${#cities[@]} -eq 0 ]; then
  omarchy-notification-send -u critical "Salah Time" "Could not load city list. Check your connection."
  exit 1
fi

selected=$(omarchy-menu-select "Choose your city" "${cities[@]}") || exit 0

jq -n --arg city "$selected" '{city: $city}' > "$CONFIG_FILE"

"$PLUGIN_DIR/scripts/run_refresh.sh"

omarchy-notification-send -u low "Salah Time" "City set to $selected"
