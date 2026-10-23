# Salah

<img src="Design/Previews/app-icon.png" alt="" width="96" align="right">

A calm macOS menu-bar app for the five daily prayers, with desktop widgets and adhan alerts.

[![CI](https://github.com/salah-kit/Salah/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/salah-kit/Salah/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/salah-kit/Salah?sort=semver)](https://github.com/salah-kit/Salah/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## What it is

Salah lives in your menu bar. It shows how long until the next prayer, opens a dropdown
with the day's schedule, brings the same schedule to desktop and Notification Center
widgets, and sounds the adhan when a prayer begins. Its window, with Today and the
settings, gives it a Dock icon while it's open.

| Menu bar | Arabic, right to left | Widgets |
| :---: | :---: | :---: |
| <img src="SalahTests/Baselines/menu/idle-dropdown-en-dark.png" alt="The menu-bar dropdown: the Hijri date, Makkah, and the day's six prayers with Asr expanded as the next prayer, in dark mode" width="240"> | <img src="SalahTests/Baselines/menu/idle-dropdown-ar-light.png" alt="The same dropdown in Arabic, laid out right to left with Arabic digits, in light mode" width="240"> | <img src="SalahTests/Baselines/widget/idle-small-en-light.png" alt="The small widget: the next prayer and its countdown" width="120"><br><img src="SalahTests/Baselines/widget/idle-medium-en-dark.png" alt="The medium widget: the next prayer and the day's schedule" width="240"> |

These images are the test suite's own renders ([`SalahTests/Baselines`](SalahTests/Baselines/README.md)),
checked on every change, so they show what the app draws today.

- **The menu bar.** The next prayer's symbol and a countdown or its time, on a gold
  capsule in the last 15 minutes, then a 15-minute count-up after the adhan. The dropdown
  shows the Hijri date, the next prayer on the sky of the time of day, the day's timeline,
  the six times with per-prayer alert toggles, silent mode and a stop button.
- **One window.** Open Salah shows Today (the next prayer, the day's timeline and its
  prayers) and the settings in a sidebar. While the window is open Salah has a Dock
  icon, a place in ⌘-Tab and its own menus. Closing it, ⌘Q included, keeps Salah in the
  menu bar; Quit Salah, in the dropdown and on Today, turns it off, scheduled alerts
  included.
- **Widgets** in small, medium, large and extra-large sizes, with a live countdown and a
  stop button while audio plays; the extra-large one adds the day's sun arc. The widget
  calculates its own times, so it stays right on days Salah isn't running.
- **Appearance.** Light, dark or the system's, for the window, the dropdown and the
  widgets. The sky follows the prayer period you're in, from dawn at Fajr to night at
  Isha, or stays neutral.
- **Alerts.** Per-prayer adhan alerts with before and after reminders, a Jumu'ah
  override, six built-in recordings, a soft tone or your own audio, a du'a after the
  adhan, and a catch-up when the Mac wakes from sleep.
- **Calculation.** Eleven methods plus custom angles, Shafi or Hanafi Asr, high-latitude
  rules, per-prayer adjustments, a Hijri offset and a delayed Isha in Ramadan.
- **Nine languages:** English, Arabic, French, Urdu, Indonesian, Turkish, Persian,
  Bengali and Malay, with right-to-left layouts and local digits.
- **Private.** Prayer times are computed on your Mac, and work offline. The only
  network use is Apple's: your coordinates go to Apple's geocoding service to name your
  city, and what you type in the location search goes to Apple Maps' search. No
  accounts, no analytics, no tracking.

What it deliberately isn't:

- It isn't a mosque timetable app: it calculates times from your location, and doesn't
  show a mosque's published iqama times.
- It isn't on the Mac App Store, and there is no signed download yet. Salah is released
  as source; you build it yourself.
- It's macOS only. The prayer-time code it is built on,
  [SalahKit](https://github.com/salah-kit/SalahKit) and
  [SalahTimes](https://github.com/salah-kit/SalahTimes), is how other apps on other
  platforms share it.

Salah is the [salah-kit](https://github.com/salah-kit) ecosystem's own app and a working
sample of the packages, used through their public API only. SalahTimes calculates the
times (SalahCalculation); SalahCore decides which prayer is next, which just started and
what a day can't give; the widget extension builds its own timelines from settings the
app mirrors into their shared App Group (SalahWidgets); the rows and the focus are
SalahUI's components in Salah's own styles; and SalahAlerts plans the alerts, installs
the ones macOS can keep and follows every one while the app runs. Salah's look, settings,
sounds and wording stay in the app.

## Installation

Build it with Xcode 27 on macOS. The app runs on macOS 14 or later.

1. Clone the repo and add your signing team. The app shares an App Group with its widget,
   so it needs a team to run; a free Apple Developer account works.

   ```sh
   git clone https://github.com/salah-kit/Salah.git
   cd Salah
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   # Edit Config/Local.xcconfig: DEVELOPMENT_TEAM = <your team ID>
   ```

2. Build a release copy:

   ```sh
   xcodebuild build -project Salah.xcodeproj -scheme Salah -configuration Release \
     -destination 'platform=macOS' -derivedDataPath build -allowProvisioningUpdates
   ```

   Or open `Salah.xcodeproj` in Xcode and run the `Salah` scheme.

3. Move `build/Build/Products/Release/Salah.app` to `/Applications` and open it.

## Quick start

1. Open Salah. A welcome explains what Salah does and asks for the location and
   notifications, each on its own page; then Salah's window opens on Today, and a
   moon-and-stars icon with the time to the next prayer appears in the menu bar; click it
   for the day's schedule. Salah keeps running there when you close the window.
2. Press ⌘, for the settings, or click **Open Salah** in the dropdown and pick a pane
   under Settings. In **Location**, use your current location or search for a city. **Calculation** picks a method from
   your country; you can change it.
3. In **Notifications**, choose each prayer's alert and reminders. If you chose Not Now
   in the welcome, macOS asks for permission when you open this pane with an alert on.
4. To add a widget, right-click the desktop, choose **Edit Widgets**, and search for
   Salah.

## Documentation

This README and [CONTRIBUTING.md](CONTRIBUTING.md) cover using and building the app. The
visual baselines' [index](SalahTests/Baselines/README.md) lists every widget and menu
state the tests render. The packages Salah builds on document their APIs in their own
repos: [SalahKit](https://github.com/salah-kit/SalahKit) and
[SalahTimes](https://github.com/salah-kit/SalahTimes).
The design system for the apps (tokens, the prayer symbols, the app icon and previews of
key screens) is described in [Design](Design/README.md).

## Supported platforms

macOS 14 Sonoma or later, on Apple silicon and Intel Macs.

## Status and versioning

Salah 1.1.2 is a source release on SalahKit 0.4.0. Releases use a
marketing version (1.1.2) and a build number; [CHANGELOG.md](CHANGELOG.md) records every
change.

Not done yet: a signed and notarized download, a Mac App Store listing, and confirmation
of the rights to redistribute the bundled adhan recordings (see [NOTICE](NOTICE)). Native-language
review includes the new volume accessibility label.

Salah's colors are the design system's tokens. A test holds their text to 4.5:1 and their
glyphs, marks and passed prayers to 3:1 on the skies and surfaces they're drawn on, in light
and dark, with and without Increase Contrast. It checks the token pairs, not every rendered
pixel; the visual baselines show what each face draws.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing, formatting and releasing. The
org-wide code of conduct and security policy live in
[salah-kit/.github](https://github.com/salah-kit/.github). Checks that need a real Mac, time
or a native speaker are open issues labelled
[`help wanted`](https://github.com/salah-kit/Salah/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22).

## License

MIT. See [LICENSE](LICENSE). The bundled audio recordings aren't covered by it: see
[NOTICE](NOTICE).
