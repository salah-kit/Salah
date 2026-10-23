# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A welcome on the first launch, in a small window of its own: what Salah does, then why it
  wants the location (Allow Location Access, or Choose a City…) and to alert (Allow
  Notifications, or Not Now). Each asks macOS only from its own page, and only while macOS
  hasn't asked before; finishing opens Today, or the Location pane after Choose a City….
  Salah no longer asks for either at launch. Closing the welcome early asks for nothing; it
  shows again the first time Salah opens in a later run, a login launch included, while
  there's still something to ask.
- Salah's window: Today, an overview with the next prayer, the day's timeline and its
  prayers, and the six settings panes in a sidebar. Open Salah in the dropdown, ⌘, (at
  General), Finder, Spotlight, the Dock icon and a widget's tap open it, or bring it
  forward; it opens on Today the first time, then on the last pane.
- While the window is open, Salah has a Dock icon, a place in ⌘-Tab and its own menus,
  hidden and minimized included. A login launch stays in the menu bar.
- An extra-large desktop widget: the next prayer and its countdown, the day's sun arc,
  and the day's six times.

### Changed

- The app icon is the design system's: a gold arch and crescent on the evening sky, with
  dark and tinted versions for macOS's icon styles.
- Closing the window, ⌘Q included, keeps Salah running in the menu bar, and the first
  time a note says so. Quit Salah, the power button in the dropdown and the button on
  Today, turns Salah off: it removes the alerts Salah scheduled, so nothing alerts until
  Salah opens again, and quits. Logout, restart and shutdown quit and keep the alerts.
- The dropdown's footer is Silent, Open Salah and Quit Salah. The window replaces the
  Settings window, so Help and About are in its menus.
- New look for the widgets, the dropdown, Today and the status item. The next prayer sits
  on a sky that follows the prayer period you're in: dawn from Fajr, day from sunrise,
  afternoon from Asr, dusk from Maghrib and night from Isha. Widgets count down live to
  the second, the large one shows the progress to the next prayer, and after Isha they
  show tomorrow's times. The status item shows the next prayer's symbol, and a gold
  capsule in the last 15 minutes.
- Settings → Appearance is now Light, Dark or System, for the window, the dropdown and the
  widgets, with a switch to keep the sky neutral instead of following the time of day,
  and a preview of the medium widget. It replaces the widget themes, sizes and colors; a
  custom theme set to always light or always dark carries over.
- Settings → Notifications follows the new look: Sound (mute, the du’a, volume), a prayer
  picker across the pane whose segments show a muted bell when every alert of that prayer
  is off, then At prayer time, Before and After, each with its sound, and System
  notification settings last. Jumu’ah is the picker’s last segment, with a switch for
  different alerts on Friday; with it off, Fridays use Dhuhr’s alerts. Reminder offsets
  read "10 min" beside their stepper.

- Document the release process in CONTRIBUTING, and point contributors to the checks that
  need a real Mac or a native speaker, which are open `help wanted` issues.

### Fixed

- Refresh the widget promptly after stopping audio, including when small, medium and
  large widgets are installed together ([#52](https://github.com/salah-kit/Salah/issues/52)).
  Recheck playback after planning a refresh, archive the static Stop face only once, and
  return to the schedule at its exact playback expiry.
- Draw the Appearance widget preview at the desktop size measured on macOS 27.0.1
  ([#28](https://github.com/salah-kit/Salah/issues/28)).
- Keep menu-bar prayer names, times and countdowns readable, including passed prayers and
  Increase Contrast.
- Expose the menu-bar countdown and count-up as read-only accessible text while retaining
  the full duration in the selected language.
- Preserve a scheduled prayer notification while macOS is delivering it, including a
  refresh after the app reports the alert, so it is neither withdrawn nor replaced.
  Queued fallback notifications use the updated language and sound settings.
- Open Settings when a sandboxed app follows a `salah://settings` link.
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
- Name the menu-bar dropdown for VoiceOver in the selected app language
  ([#14](https://github.com/salah-kit/Salah/issues/14)).
- Draw the version line under the Settings sidebar and the menu bar preview's caption in the
  secondary label colour; they had too little contrast.
- Group the Appearance preview's rows for VoiceOver, in a group named "Preview".
- Give the widget's text enough contrast in the widget and the Appearance preview
  ([#35](https://github.com/salah-kit/Salah/issues/35)): text draws in the design system's
  text colors, held to 4.5:1 on every time of day's sky, and passed prayers to 3:1.
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
