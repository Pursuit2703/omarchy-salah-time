#!/bin/bash
# One-time setup: create the venv and install the scraper's dependencies,
# including its headless Chromium. Only runs if venv doesn't exist yet.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

python3 -m venv venv
./venv/bin/pip install --quiet -r requirements.txt
PLAYWRIGHT_BROWSERS_PATH="$DIR/islomuz_api/data/browsers" ./venv/bin/python -m playwright install chromium
