import os

CONFIG_DIR = os.path.expanduser("~/.config/omarchy-salah-time")
CACHE_DIR = os.path.expanduser("~/.cache/omarchy-salah-time")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
SCHEDULE_FILE = os.path.join(CACHE_DIR, "schedule.json")
REGIONS_FILE = os.path.join(CACHE_DIR, "regions.json")

DEFAULT_CITY = "Toshkent"


def ensure_dirs():
    os.makedirs(CONFIG_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
