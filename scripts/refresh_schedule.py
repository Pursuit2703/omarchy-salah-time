#!/usr/bin/env python3
"""Keep the local prayer-time cache fresh.

Two very different costs live in here on purpose:
- ensure_month_cache_fast(): heavy. Launches a real headless browser and
  scrapes every city's monthly table in one pass. Only actually does
  anything on the first call each month (islomuz_api caches by year-month) -
  a systemd timer calls this once a month, and once at boot as a safety net
  in case a boot lands after the 1st with no cache yet.
- write_today_schedule(): cheap. Reads the already-cached month for the
  configured city, no browser involved. Safe to call as often as you like -
  the bar widget's own timer calls this every minute so notifications and
  the countdown stay accurate without re-scraping anything.
"""
import json
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from paths import CONFIG_FILE, SCHEDULE_FILE, DEFAULT_CITY, ensure_dirs
from islomuz_api import get_today, prefetch_all_monthly_fast, _current_ym, _cache_path, _load_cache


def read_city() -> str:
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE) as f:
                return json.load(f).get("city", DEFAULT_CITY)
        except (json.JSONDecodeError, OSError):
            pass
    return DEFAULT_CITY


def ensure_month_cache_fast():
    ym = _current_ym()
    if _load_cache(_cache_path("gregorian", ym)):
        return False
    print(f"No cache for {ym} yet - running full prefetch (headless browser, ~1-2 min)...")
    prefetch_all_monthly_fast()
    return True


def write_today_schedule():
    city = read_city()
    day = get_today(city)
    if day is None:
        print(f"No data returned for city={city!r}", file=sys.stderr)
        return False

    payload = {
        "city": city,
        "fetched_at": datetime.now().astimezone().isoformat(),
        "date": day["date"],
        "weekday": day.get("weekday"),
        "times": day["times"],
    }

    with open(SCHEDULE_FILE, "w") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)

    print(f"Wrote {SCHEDULE_FILE} for {city} ({day['date']['iso']})")
    return True


def main():
    ensure_dirs()
    ensure_month_cache_fast()
    if not write_today_schedule():
        sys.exit(1)


if __name__ == "__main__":
    main()
