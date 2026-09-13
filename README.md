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

Right-click the widget for **Salah Time Settings**:
- **Change City** - live list from islom.uz
- **Manage Reminders** - add/remove reminders (each is a prayer-or-all +
  minutes-before), and toggle the notification sound

Comes with one default reminder: all prayers, 10 minutes before, sound on.
Add as many more as you like - e.g. "All prayers, 15 min before" plus
"Fajr, 30 min before" for an extra early one.

## Credits

Vendors [`islomuz_api`](https://github.com/SpecialGuys/islomuz_api), a
Playwright-based scraper for islom.uz.
