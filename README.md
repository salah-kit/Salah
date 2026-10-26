# Salah

<img src="Design/Previews/app-icon.png" alt="" width="96" align="right">

A calm prayer app for iPhone, iPad, Apple TV and macOS, with prayer times, widgets and reminders.

[![CI](https://github.com/salah-kit/Salah/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/salah-kit/Salah/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/salah-kit/Salah?sort=semver)](https://github.com/salah-kit/Salah/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## What it is

### On iPhone and iPad

The iOS app has Today, Times, Qibla and Settings, with tabs on iPhone and adaptive
navigation on iPad. On iPhone Duo, the tabs and controls sit in the outer display's side
bar, and the open display shows two pages that meet at the fold. It calculates prayer
times on the device from your current location or a city you choose, with no account or
subscription.

- **Today and Times.** The next prayer, a live countdown, the day's schedule and sun
  arc, with day and week views for other dates. The sky follows the prayer period, or
  stays neutral. English and Arabic include local digits and right-to-left layout.
- **Qibla.** The bearing and distance to the Kaaba, with a compass where the device
  supplies a heading and a bearing-only view when it cannot.
- **Calculation.** Automatic selection, all fourteen methods from the engine, or
  custom twilight angles; Shafi or Hanafi Asr; high-latitude rules; per-prayer
  adjustments; a Hijri offset; and delayed Isha in Ramadan.
- **Reminders and sound.** Independent at-time, before and after alerts for each
  prayer, optional Sunrise alerts, and different alerts on Friday. Mute keeps the
  notifications and silences their sounds. Choose the licensed built-in regular or
  Fajr adhan, a system sound, a synthesized soft tone, or import your own recording.
  Recordings get a notification excerpt under 30 seconds; full playback starts from an
  explicit app action and can continue in the background. iOS notifications do not
  start a full adhan automatically. Imported recordings can be up to 30 minutes long;
  longer files are rejected. The optional spoken du'a can add up to two minutes.
- **System surfaces.** Home Screen and Lock Screen widgets, prayer Live Activities,
  Dynamic Island, and Control Center controls for mute and Stop. Widgets calculate
  their own schedule from shared settings. Setup, unavailable and stale states explain
  when to open the app, without showing an old countdown.

The iOS app is available as source in the Unreleased changes. There is no App Store
listing or installable iOS download yet. See [Installation](#installation) to run a
simulator build without a paid developer membership.
The [iOS privacy policy](docs/privacy.md) explains local storage and Apple services.

### On macOS

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
- It isn't on the Mac App Store or iOS App Store, and there is no signed download yet.
  Salah is available as source; you build it yourself.

Salah is the [salah-kit](https://github.com/salah-kit) ecosystem's own app and a working
sample of the packages, used through their public API only. SalahTimes calculates the
times (SalahCalculation); SalahCore decides which prayer is next, which just started and
what a day can't give; the widget extension builds its own timelines from settings the
app mirrors into their shared App Group (SalahWidgets); the rows and the focus are
SalahUI's components in Salah's own styles; and SalahAlerts plans the alerts, installs
the ones macOS can keep and follows every one while the app runs. Salah's look, settings,
sounds and wording stay in the app.

### On Apple TV

The Apple TV app has Today, Week and Settings, made for the Siri Remote and for a room. It
calculates prayer times on the Apple TV from its location, found once, or from a city you
choose.

- **Today.** The next prayer and its countdown beside the day's prayers. Pressing a
  prayer opens its sound. The sky follows the prayer period, or stays neutral.
- **The room display.** Keep on Screen shows the day's times, a clock and the next prayer
  across a room, at home or in a musalla, and holds off the screen saver while it's open.
- **Week.** Seven days of times, a column a day. Moving past either end turns the week.
- **The adhan while Salah is open.** At each prayer, the regular or Fajr adhan or a soft
  tone, with the optional spoken du'a, over whatever is on screen. Stop, Play/Pause or
  Back ends it. Apple TV can't play it while Salah is closed.
- **Top Shelf.** With Salah in the top row of the Home Screen, banners for the next
  prayer, today's prayers and the room display; pressing one opens it.
- **Settings.** Location, the calculation method and its options, each prayer's sound,
  volume, appearance, language and the Hijri date, in tvOS's own lists. Right-to-left
  languages lay out right to left with their own digits, and Larger Text gives Today one
  column.

The Apple TV app is available as source in the Unreleased changes. There is no App Store
listing or download yet. See [Installation](#apple-tv) to run a simulator build without a
paid developer membership. The [privacy policy](docs/privacy.md) covers the Apple TV app
too.

## Installation

### macOS

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

### iPhone and iPad

Build with Xcode 27 on a Mac. The app requires iOS or iPadOS 26 or later. A simulator
build needs no paid Apple Developer membership, signing team or provisioning profile:

```sh
git clone https://github.com/salah-kit/Salah.git
cd Salah
xcodebuild build -project Salah.xcodeproj -scheme SalahIOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .derived/ios \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
```

To run it, open `Salah.xcodeproj`, choose the `SalahIOS` scheme and an iPhone or iPad
simulator, then Run. [CONTRIBUTING.md](CONTRIBUTING.md#ios-and-ipados) covers the command-line
simulator journeys and unsigned device build. Installing on a physical device needs
your local signing configuration; App Store distribution needs a paid membership.

### Apple TV

Build with Xcode 27 on a Mac. The app requires tvOS 26 or later. A simulator build needs
no paid Apple Developer membership, signing team or provisioning profile:

```sh
git clone https://github.com/salah-kit/Salah.git
cd Salah
xcodebuild build -project Salah.xcodeproj -scheme SalahTV -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' -derivedDataPath .derived/tvos \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
```

To run it, open `Salah.xcodeproj`, choose the `SalahTV` scheme and an Apple TV simulator,
then Run. [CONTRIBUTING.md](CONTRIBUTING.md#tvos) covers the command-line simulator
journeys and the unsigned device build. Installing on an Apple TV needs your local signing
configuration.

## Quick start

### macOS

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

### iPhone and iPad

1. Open Salah and complete setup. Allow current location or choose a city, choose
   whether to allow notifications, and confirm the calculation method. A city remains
   usable when location access is off.
2. Use **Today** for the next prayer and today's times, **Times** for another day or
   week, and **Qibla** for the direction of prayer. The compass needs heading hardware;
   a simulator can show the calculated bearing.
3. Open **Settings → Prayer alerts** to configure each prayer's at-time, before and
   after reminders, including its sound. Use the Friday override for Jumu'ah, or leave it
   off to inherit Dhuhr's alerts. **Sound** controls mute, in-app playback volume and
   the optional spoken du'a after a built-in or imported adhan.
4. Add a Salah widget through the Home Screen or Lock Screen editor. Control Center's
   control gallery includes mute and Stop. Live Activities follow a prayer while it is
   relevant; iOS controls their availability and presentation.

### Apple TV

1. Open Salah and choose **Use This Apple TV's Location**; Allow Once is enough. Or
   choose **Choose a City** and search. Salah picks the calculation method for the country.
2. **Today** shows the next prayer beside the day's prayers. Press a prayer to choose its
   sound, or **Keep on Screen** for the room display; Back leaves it.
3. **Week** shows seven days; move past Monday or Sunday for another week. **Settings**
   has the location, the calculation, the sounds, volume, appearance and language.
4. Keep Salah open at prayer time to hear the adhan; Stop, Play/Pause or Back ends it.
   Move Salah into the top row of the Home Screen to see its Top Shelf.

## Documentation

This README and [CONTRIBUTING.md](CONTRIBUTING.md) cover using and building the app. The
visual baselines' [index](SalahTests/Baselines/README.md) lists every widget and menu
state the tests render. The packages Salah builds on document their APIs in their own
repos: [SalahKit](https://github.com/salah-kit/SalahKit) and
[SalahTimes](https://github.com/salah-kit/SalahTimes).
The design system for the apps (tokens, the prayer symbols, the app icon and previews of
key screens) is described in [Design](Design/README.md).
The [iOS architecture](docs/ios-architecture.md) describes state, persistence, platform
services and the app's system surfaces. The [tvOS architecture](docs/tvos-architecture.md)
describes the Apple TV app, its sound and its Top Shelf.

## Supported platforms

| App | Minimum system |
|---|---|
| macOS menu-bar app | macOS 14 Sonoma, on Apple silicon and Intel Macs |
| iPhone app | iOS 26 |
| iPad app | iPadOS 26 |
| Apple TV app | tvOS 26 |

## Status and versioning

Salah 1.1.2 is a source release on SalahKit 0.4.0. Releases use a
marketing version (1.1.2) and a build number; [CHANGELOG.md](CHANGELOG.md) records every
change.

The iOS app is part of the Unreleased source on the same SalahKit version. Its source
availability does not mean an iOS App Store release, a signed download, or completed
physical-device validation. The simulator build and test commands are in
[CONTRIBUTING.md](CONTRIBUTING.md#ios-and-ipados). The
[iOS validation notes](docs/ios-validation.md) link the remaining hardware, VoiceOver
and native-language reviews and explain the notification and background-refresh limits.
The Apple TV app is Unreleased source in the same way; the
[tvOS validation notes](docs/tvos-validation.md) link its remaining hardware, VoiceOver
and native-language reviews and explain why the adhan plays only while Salah is open.

Not done yet: a signed and notarized download, a Mac App Store listing, and confirmation
of the rights to redistribute the bundled adhan recordings (see [NOTICE](NOTICE)). Native-language
review includes the new volume accessibility label.

The iOS and tvOS targets include two recordings under CC BY 4.0, with full attribution in
[NOTICE](NOTICE) and each app's audio credits. System sounds, a synthesized tone and
imported recordings are also available. It does not bundle the macOS recordings whose
redistribution rights are still unconfirmed.

Salah's colors are the design system's tokens. A test holds their text to 4.5:1 and their
glyphs, marks and passed prayers to 3:1 on the skies and surfaces they're drawn on, in light
and dark, with and without Increase Contrast. It checks the token pairs, not every rendered
pixel; the visual baselines show what each face draws.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for building, testing, formatting and releasing. The
org-wide code of conduct and security policy live in
[salah-kit/.github](https://github.com/salah-kit/.github). Checks that need a real device, time
or a native speaker are open issues labelled
[`help wanted`](https://github.com/salah-kit/Salah/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22).

## License

MIT. See [LICENSE](LICENSE). The bundled audio recordings aren't covered by it: see
[NOTICE](NOTICE).
