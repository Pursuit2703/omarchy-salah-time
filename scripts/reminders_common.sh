# Shared helpers for reading/writing reminders.json. Sourced, not run directly.
REMINDERS_FILE="$HOME/.config/omarchy-salah-time/reminders.json"

ensure_reminders_file() {
  mkdir -p "$(dirname "$REMINDERS_FILE")"
  if [ ! -f "$REMINDERS_FILE" ]; then
    jq -n '{soundEnabled: true, reminders: [{id: "default", scope: "all", offsetMinutes: 10}]}' > "$REMINDERS_FILE"
  fi
}

# Prints one line per reminder: "<id>\t<display text>"
list_reminders() {
  jq -r '.reminders[] | .scope as $s | [.id, (if $s == "all" then "All prayers" else ($s[0:1]|ascii_upcase) + $s[1:] end) + " - " + (.offsetMinutes|tostring) + " min before"] | @tsv' "$REMINDERS_FILE"
}
