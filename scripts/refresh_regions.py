#!/usr/bin/env python3
"""Fetch the live city/region list from islom.uz and cache it for the picker."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from paths import REGIONS_FILE, ensure_dirs
from islomuz_api import get_regions, cyrillic_to_latin


def main():
    ensure_dirs()
    regions = get_regions()
    # get_regions() returns Cyrillic Uzbek names; islomuz_api's own lookups
    # accept either script, so show Latin in the picker without losing
    # compatibility with the rest of the pipeline.
    names = sorted({cyrillic_to_latin(r["name"]) for r in regions if r.get("name")})

    with open(REGIONS_FILE, "w") as f:
        json.dump({"cities": names}, f, indent=2, ensure_ascii=False)

    print(f"Wrote {REGIONS_FILE} with {len(names)} cities")


if __name__ == "__main__":
    main()
