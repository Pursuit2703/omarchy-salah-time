# salah-time

An Omarchy bar widget showing the next prayer time and a live countdown,
sourced directly from [islom.uz](https://islom.uz/taqvim) — no manual data
entry, no hand-maintained schedule file.

## How it stays fresh without running a browser all the time

islom.uz doesn't expose a plain JSON API for the times table (it's a
JavaScript-rendered page), so getting real data means driving a real
headless browser for that part. To keep that cost as small as possible:

- **Once a month**, a full scrape grabs every city's schedule for the month
  in one pass (`islomuz_api.prefetch_all_monthly_fast`). This is the only
  step that launches a browser, and it only actually runs on the first
  check each month — every other day it's a no-op.
- **Reading "today's time for city X"** afterward is a pure local cache
  lookup — instant, no network, no browser. The bar widget re-checks this
  every 30 minutes (and once at startup) purely to catch day rollovers and
  the rare month-boundary crossing; on all but one day a month that check
  costs nothing more than a fast cache read.

The region/city list is separate and always cheap — islom.uz does expose a
plain JSON API for that (`new.islom.uz/api/v1/regions`).

## Setup

```bash
omarchy plugin add https://github.com/Pursuit2703/omarchy-salah-time.git --enable
```

First load bootstraps a Python virtualenv and downloads a headless Chromium
(~110MB, one-time). This happens automatically in the background — the
widget will just say "Salah" until it's done.

Click the widget for the day's panel: the next prayer with a live
countdown, progress since the previous prayer, and all six times.

Right-click (or the panel's Settings button) for settings, inside the same
panel:
- **City** - searchable live list from islom.uz
- **Remind me before** - one row per prayer (or all prayers) with a
  minutes-before stepper; step down to Off to drop it
- **Sound** - notification sound on/off and its volume

On a left or right bar the widget stacks into the bar's width: the next
prayer's letter inside a ring that fills from the previous prayer to the
next, then the time left (`4h` / `17m`).

`omarchy-shell pursuit2703.salah-time toggle` and
`omarchy-shell pursuit2703.salah-time.settings open` work for keybindings.

Comes with one default reminder: all prayers, 10 minutes before, sound on.
Set a per-prayer one on top - e.g. "All prayers, 10 min before" plus
"Fajr, 30 min before" for an extra early one.

## Credits

Vendors [`islomuz_api`](https://github.com/SpecialGuys/islomuz_api), a
Playwright-based scraper for islom.uz.
