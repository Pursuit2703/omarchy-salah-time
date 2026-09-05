#!/usr/bin/env python3
"""Fetch the live city/region list from islom.uz and cache it for the picker."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from paths import REGIONS_FILE, ensure_dirs
from islomuz_api import get_regions


def main():
    ensure_dirs()
    regions = get_regions()
    names = sorted({r["name"] for r in regions if r.get("name")})

    with open(REGIONS_FILE, "w") as f:
        json.dump({"cities": names}, f, indent=2, ensure_ascii=False)

    print(f"Wrote {REGIONS_FILE} with {len(names)} cities")


if __name__ == "__main__":
    main()
