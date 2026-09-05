#!/bin/bash
# Add/remove reminders and toggle sound, looping until the user picks Back.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DIR/scripts/reminders_common.sh"
ensure_reminders_file

add_reminder() {
  local scope
  scope=$(omarchy-menu-select "Which prayer?" "All prayers" "Fajr" "Sunrise" "Dhuhr" "Asr" "Maghrib" "Isha") || return 0

  local scope_key
  case "$scope" in
    "All prayers") scope_key="all" ;;
    *) scope_key=$(echo "$scope" | tr '[:upper:]' '[:lower:]') ;;
  esac

  local minutes
  minutes=$(omarchy-menu-input "Minutes before $scope") || return 0
  if ! [[ "$minutes" =~ ^[0-9]+$ ]]; then
    omarchy-notification-send -u critical "Salah Time" "Enter a whole number of minutes."
    return 0
  fi

  local id="r$(date +%s%N)"
  jq --arg id "$id" --arg scope "$scope_key" --argjson minutes "$minutes" \
    '.reminders += [{id: $id, scope: $scope, offsetMinutes: $minutes}]' \
    "$REMINDERS_FILE" > "$REMINDERS_FILE.tmp" && mv "$REMINDERS_FILE.tmp" "$REMINDERS_FILE"

  omarchy-notification-send -u low "Salah Time" "Reminder added: $scope, $minutes min before"
}

remove_reminder() {
  local entries
  mapfile -t entries < <(list_reminders)
  if [ ${#entries[@]} -eq 0 ]; then
    omarchy-notification-send -u low "Salah Time" "No reminders to remove."
    return 0
  fi

  local labels=()
  local ids=()
  for entry in "${entries[@]}"; do
    ids+=("${entry%%$'\t'*}")
    labels+=("${entry#*$'\t'}")
  done

  local chosen
  chosen=$(omarchy-menu-select "Remove which reminder?" "${labels[@]}") || return 0

  for i in "${!labels[@]}"; do
    if [ "${labels[$i]}" = "$chosen" ]; then
      jq --arg id "${ids[$i]}" '.reminders |= map(select(.id != $id))' \
        "$REMINDERS_FILE" > "$REMINDERS_FILE.tmp" && mv "$REMINDERS_FILE.tmp" "$REMINDERS_FILE"
      omarchy-notification-send -u low "Salah Time" "Reminder removed."
      return 0
    fi
  done
}

toggle_sound() {
  local current
  current=$(jq -r '.soundEnabled' "$REMINDERS_FILE")
  local next="true"
  [ "$current" = "true" ] && next="false"
  jq --argjson v "$next" '.soundEnabled = $v' "$REMINDERS_FILE" > "$REMINDERS_FILE.tmp" && mv "$REMINDERS_FILE.tmp" "$REMINDERS_FILE"
  omarchy-notification-send -u low "Salah Time" "Reminder sound: $([ "$next" = "true" ] && echo On || echo Off)"
}

while true; do
  sound_state=$(jq -r 'if .soundEnabled then "On" else "Off" end' "$REMINDERS_FILE")
  choice=$(omarchy-menu-select "Manage Reminders" "Add reminder" "Remove reminder" "Toggle sound (currently: $sound_state)" "Back") || break
  case "$choice" in
    "Add reminder") add_reminder ;;
    "Remove reminder") remove_reminder ;;
    "Toggle sound"*) toggle_sound ;;
    "Back") break ;;
  esac
done
