#!/bin/bash
# Atomically decides which live widget instance sends a given reminder.
# There's one bar-widget instance per connected monitor, all running the
# same reminder clock in lockstep, so without this every monitor fires its
# own notification for the same event. `mkdir` on a per-key directory is
# atomic on POSIX filesystems: whichever instance's mkdir succeeds "wins"
# and continues past the &&; every other instance's mkdir fails and it
# stops there, so exactly one notification (and one sound) goes out
# regardless of how many monitors are attached.
set -u
LOCK_ROOT="$HOME/.cache/omarchy-salah-time/notified"
KEY="$1" SUMMARY="$2" BODY="$3" PLAY_SOUND="$4" SOUND_FILE="$5"

mkdir -p "$LOCK_ROOT" 2>/dev/null
mkdir "$LOCK_ROOT/$KEY" 2>/dev/null || exit 0

omarchy-notification-send -u normal "$SUMMARY" "$BODY"
[ "$PLAY_SOUND" = "1" ] && paplay "$SOUND_FILE" &

# Trim claims older than 2 days so this directory doesn't grow forever.
find "$LOCK_ROOT" -maxdepth 1 -mindepth 1 -mtime +2 -exec rm -rf {} + 2>/dev/null
exit 0
