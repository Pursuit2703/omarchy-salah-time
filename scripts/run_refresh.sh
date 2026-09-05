#!/bin/bash
# Entry point the widget calls. Bootstraps on first run (slow, one-time),
# then refreshes the schedule (cheap unless it's a new month).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -x "$DIR/venv/bin/python" ]; then
  "$DIR/scripts/bootstrap.sh"
fi

PLAYWRIGHT_BROWSERS_PATH="$DIR/islomuz_api/data/browsers" "$DIR/venv/bin/python" "$DIR/scripts/refresh_schedule.py"
