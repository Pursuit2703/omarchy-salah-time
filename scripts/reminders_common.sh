# Shared helpers for reading/writing reminders.json. Sourced, not run directly.
REMINDERS_FILE="$HOME/.config/omarchy-salah-time/reminders.json"

ensure_reminders_file() {
  mkdir -p "$(dirname "$REMINDERS_FILE")"
  if [ ! -f "$REMINDERS_FILE" ]; then
    jq -n '{soundEnabled: true, reminders: [{id: "default", scope: "all", offsetMinutes: 10}]}' > "$REMINDERS_FILE"
  fi
}

# Writes tmp_file's content into REMINDERS_FILE in place (truncate + write),
# not via rename. The widget's FileView watches the file by path/inode, and
# a rename-based replace (the usual "jq ... > tmp && mv tmp file" pattern)
# swaps the inode out from under that watch, so live-reload silently stops
# working after the very first edit.
commit_reminders() {
  cat "$1" > "$REMINDERS_FILE"
  rm -f "$1"
}

# Prints one line per reminder: "<id>\t<display text>"
list_reminders() {
  jq -r '.reminders[] | .scope as $s | [.id, (if $s == "all" then "All prayers" else ($s[0:1]|ascii_upcase) + $s[1:] end) + " - " + (.offsetMinutes|tostring) + " min before"] | @tsv' "$REMINDERS_FILE"
}
