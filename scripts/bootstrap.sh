#!/bin/bash
# One-time setup: create the venv and install the scraper's dependencies,
# including its headless Chromium. Only runs if venv doesn't exist yet.
# Everything lands under DATA_DIR (see env.sh), never inside this plugin
# folder - Quickshell watches this folder for live-reload, and writing
# hundreds of venv/pip/browser files into it triggers a reload storm.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DIR/scripts/env.sh"

python3 -m venv "$DATA_DIR/venv"
"$DATA_DIR/venv/bin/pip" install --quiet -r "$DIR/requirements.txt"
"$DATA_DIR/venv/bin/python" -m playwright install chromium
