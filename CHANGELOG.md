# Changelog

All notable changes to this project are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Earlier
history is in `git log`.

## [Unreleased]

### Added

- Click the widget for a panel: next prayer with a live countdown, progress
  since the previous prayer, and the day's six times.
- Settings inside the panel (right-click, or the panel's Settings button):
  searchable city list, a minutes-before stepper per prayer, sound on/off and
  volume. Replaces the `omarchy-menu-select` menus.
- Left/right bar layout: the next prayer's letter inside a ring that fills
  from the previous prayer, then the time left one unit per line.
- IPC: `omarchy-shell pursuit2703.salah-time toggle` and
  `omarchy-shell pursuit2703.salah-time.settings open`.

### Removed

- Hover tooltip; the click panel shows the same information.
