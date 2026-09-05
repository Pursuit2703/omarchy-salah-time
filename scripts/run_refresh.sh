#!/bin/bash
# Entry point the widget calls. Bootstraps on first run (slow, one-time),
# then refreshes the schedule (cheap unless it's a new month).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DIR/scripts/env.sh"

if [ ! -x "$VENV_PY" ]; then
  "$DIR/scripts/bootstrap.sh"
fi

"$VENV_PY" "$DIR/scripts/refresh_schedule.py"
