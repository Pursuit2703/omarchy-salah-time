# Shared paths for all runtime state that must live OUTSIDE the plugin
# folder. Quickshell watches the whole plugin directory for live-reload
# during development - writing a venv, a downloaded browser, or a scraper
# cache in there causes an infinite reload loop (every file write looks
# like a code change). Everything mutable goes here instead.
DATA_DIR="$HOME/.local/share/omarchy-salah-time"
export PLAYWRIGHT_BROWSERS_PATH="$DATA_DIR/browsers"
export ISLOMUZ_CACHE_DIR="$DATA_DIR/islomuz-cache"
VENV_PY="$DATA_DIR/venv/bin/python"

mkdir -p "$DATA_DIR"
