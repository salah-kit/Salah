# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Document the release process in CONTRIBUTING, and point contributors to the checks that
  need a real Mac or a native speaker, which are open `help wanted` issues.

### Fixed

- Show the banner for an alert the Mac slept through even when Salah's alert timer reports
  it before macOS reports the wake. The adhan played, but the banner was skipped and its
  request removed.
- Fix French, Arabic, Urdu and Bengali wording:
  - French notifications read "C'est l'heure de Asr"; they now say "C'est l'heure : Asr".
  - The Friday section in Settings spelled the prayer "Jumu'ah" in French, unlike its name
    "Joumouah" everywhere else.
  - Arabic reminders and their Settings steppers wrote "١٠ دقيقة", which doesn't agree
    with 3 to 10. They now write minutes as "١٠ د", as the dropdown does.
  - The Ramadan Isha footer writes its 120 minutes in the language's digits, as the rest of
    the app does.
- Name the time zone's pop-up in Settings → Location for VoiceOver, which read only the zone.
- Draw the version line under the Settings sidebar and the menu bar preview's caption in the
  secondary label colour; they had too little contrast.
- Group the Appearance preview's rows for VoiceOver, in a group named "Preview".
- Give the widget's text enough contrast on every theme, in the widget and the Appearance
  preview ([#35](https://github.com/salah-kit/Salah/issues/35)). Secondary text uses the
  design system's secondary label; the system's was about 3.6:1 in light. Text in the
  theme's or a state's color, such as the next prayer's row, the countdown and the count-up,
  keeps its hue, and lightens or darkens only as far as the sky, glow and tint under that
  text need for 4.5:1; on the presets it was as low as 2.3:1. Passed prayers stay dimmed, but
  with Increase Contrast they draw undimmed in the secondary label.
- Keep the next prayer prominent in accented and vibrant widgets by using the system's
  text hierarchy and making its name the accent element
  ([#38](https://github.com/salah-kit/Salah/issues/38)).
- Read the count-up after a prayer in each language's word order. On the small widget's
  line, Turkish read "Öğle önce" ("Öğle ago") and Persian put "از" after the name. For
  VoiceOver in the dropdown, English, Indonesian and Malay said "since 5 minutes", Turkish
  "önce", and Persian, Urdu and Bengali put their word on the wrong side of the time.

## [1.1.2] - 2026-10-14

### Fixed

- Keep small widget/menu headings and the silent-mode label legible with separate
  text ink while preserving the selected theme's decorative accents.

## [1.1.1] - 2026-10-14

### Fixed

- Keep the widget's Stop action available while a known prayer's audio plays during a
  schedule gap, including polar days with missing later prayer times.
- Give the notification volume slider a localized accessibility name.

## [1.1.0] - 2026-10-14

### Changed

- Use SalahKit 0.4.0 for missing-kind rows, sunrise-aware focus and just-started count-up,
  midnight widget entries and the handled-alert record after a clock reversal. The app no
  longer carries those workarounds; method detection, reminder wording, widget labels and
  the live last-minute timer keep their existing behavior.
- Rows and focus cards use SalahUI's localized short time text. In 24-hour locales this
  includes the locale's leading zero. App-owned notification and compact status text use
  the same Foundation short-time style.

### Fixed

- The Settings sidebar reads the app version from bundle metadata, so it stays aligned
  with the About panel after an update.
- A clock rollback into the engine's early-report window no longer requests an already
  handled alert again, including on later ordinary refreshes. The package retains the
  exclusion; ordinary wake and activation replans keep new early requests pending.

## [1.0.0] - 2026-10-14

Salah's first release, as source. Salah grew out of a 2026 rebuild of Batoul Apps' Guidance
for Mac ([batoulapps/GuidanceMac#8](https://github.com/batoulapps/GuidanceMac/pull/8)), and the
Changed and Removed sections compare it with that rebuild.

### Added

- Salah, a macOS menu-bar app for the five daily prayers:
  - a menu-bar status item with a countdown or the next prayer's time, which turns red
    in the last 15 minutes and green for a 15-minute count-up after the adhan;
  - a dropdown with the day's schedule, the Hijri date, per-prayer alert toggles, silent
    mode and a stop control;
  - small, medium and large desktop and Notification Center widgets, with a stop button;
  - per-prayer alerts with before and after reminders, a Jumu'ah override, built-in or
    custom adhan sounds, volume, a du'a after the adhan and catch-up after sleep;
  - eleven calculation methods plus custom angles, madhab, high-latitude rules,
    per-prayer adjustments, a Hijri offset and a delayed Isha in Ramadan;
  - automatic or manual location, with a manual time zone;
  - five widget themes and a custom theme with contrast guardrails;
  - nine languages (English, Arabic, French, Urdu, Indonesian, Turkish, Persian, Bengali
    and Malay), with right-to-left layouts and local digits.
- Characterization tests and 450 visual baselines of the widget faces and the menu-bar
  dropdown, in English, Arabic and French, light and dark.
- UI tests that drive the real app: its status item, menu-bar dropdown, Settings link
  and About panel, and an alert turned on and off in Settings, which the running app
  replans.
- Real-app tests (`SalahRoundTripTests`, with `SalahStopHarness` standing in for the
  widget extension): the widget's stop round trip, the stop signal alone, an alert
  missed while the app was frozen as during sleep, a reminder missed past its grace,
  and a changed alert setting at the next launch.

### Changed

- Built on [SalahKit](https://github.com/salah-kit/SalahKit) 0.2.0 and
  [SalahTimes](https://github.com/salah-kit/SalahTimes) 0.1.0, through their public API
  only:
  - Prayer times come from SalahCalculation. At Salah's default settings they're the
    same to the minute; with the Muslim World League, Egyptian, Karachi and North
    America methods Dhuhr is a minute earlier (adhan-swift added a minute it doesn't
    document); from about 55° of latitude Asr can differ by a few minutes, and the days
    adhan-swift couldn't calculate near the poles are now partial days that name what's
    missing. SalahKit's `docs/calculation-parity.md` explains every difference.
  - The widget builds its own timelines in the extension, from settings the app mirrors
    into the App Group, so it stays right when Salah isn't running and crosses midnight;
    a timeline that runs out before WidgetKit asks for another shows "Open Salah to
    update" instead of an old countdown, and opening Salah, or waking the Mac, asks for
    a new one. The Stop control shows only while a sound can still be playing.
  - The state comes from SalahCore: before Fajr the small widget shows the time since
    the previous night's Isha, and where the next prayer's time can't be calculated the
    menu bar shows "–" and the widget and dropdown say so, without a countdown. A prayer
    the calculation can't give today keeps its row, with a dash; while today's times
    aren't available at all, the dropdown shows the last known day, marked as such.
  - Alerts are planned by SalahAlerts: requests keep one identifier per prayer and alert,
    so a changed time replaces its request; the next two days' alerts and reminders come
    first, then prayer-time alerts up to two weeks ahead; and every alert, reminders the
    system plan leaves out included, still plays while Salah runs, caught up after sleep.
    A clock set back past an alert doesn't deliver it again.
  - Rows and the focus are SalahUI's `PrayerTimesList` and `NextPrayerView` in Salah's
    own styles; the custom theme's guardrails are SalahUI's `ContrastCheck`.
  - Countdowns use SalahCore's durations: the same in English, Arabic and French;
    Turkish, Indonesian, Malay, Bengali and Urdu now use their languages' standard short
    units.
- The setup face of a widget placed before Salah first runs follows the device's
  language.
- VoiceOver reads the dropdown's countdown in words.
- Custom twilight angles stay within 1 to 30 degrees and per-prayer adjustments within a
  day either way, the range the calculation accepts.
- Rebranded from Guidance: bundle identifiers `io.github.salah-kit.Salah` and
  `io.github.salah-kit.Salah.Widgets`, App Group `group.io.github.salah-kit.Salah`,
  the `salah://` deep link, Salah's notification identifiers, logging subsystem and
  preference keys, and a new app icon drawn from code.
- The Xcode project is generated by XcodeGen from `project.yml`. Signing comes from a
  gitignored `Config/Local.xcconfig`.

### Removed

- adhan-swift, the widget snapshot (`SalahWidgetSnapshot.v1`) and its store, and the
  app's own alert scheduler, state logic, duration formatter and theme contrast math,
  which SalahKit replaces.
- Guidance compatibility: the migration of Guidance's `kBA*` preferences and v2
  settings, the older stored sound and bookmark formats, and the widget snapshot
  Guidance wrote. Salah starts from its own defaults.

[Unreleased]: https://github.com/salah-kit/Salah/compare/1.1.2...HEAD
[1.1.2]: https://github.com/salah-kit/Salah/compare/1.1.1...1.1.2
[1.1.1]: https://github.com/salah-kit/Salah/compare/1.1.0...1.1.1
[1.1.0]: https://github.com/salah-kit/Salah/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/salah-kit/Salah/releases/tag/1.0.0
