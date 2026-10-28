# Remaining work

What Salah still needs, app by app. CI builds every app, runs the unit tests and drives the
simulator journeys on every change, so nearly everything left needs what CI can't give: real
hardware, days of elapsed time, or a person, such as a VoiceOver user or a native speaker.
Each check and bug links to the issue with its steps and what to record. The open bugs and
follow-ups in each section are code work, and the release tasks are the owner's.

## A plan

Each row needs one kind of equipment, so one sitting can cover it. Most Mac checks take 20 to
30 minutes; [#16] needs a night, and [#65] a few days of ordinary use.

| With | Checks |
|---|---|
| A Mac | [#14] first, then [#11], [#12], [#15], [#16], [#28], [#38], [#45] and [#46], [#54], [#64] |
| An iPhone and an iPad | [#65], and StandBy in [#28] |
| An iPhone Duo | [#67], with its simulator checks |
| An Apple TV with a television | [#69] |
| An Apple Watch and its iPhone | [#77], and [#27], which a simulator can do too |
| A VoiceOver user | [#17], in each app |
| Native speakers | [#18] to [#25] |

## Mac

### Checks on a real Mac

- [#11]: after the Mac sleeps through a prayer, the adhan plays once on waking within five
  minutes of the prayer, and a reminder more than two minutes late is skipped.
- [#12]: setting the clock back doesn't deliver an alert a second time.
- [#15]: the widget on a new user account, before Salah first runs.
- [#16]: the widget moves to the next day overnight while Salah is quit. The first night
  turned over at midnight but showed placeholders in the morning, and a later run stopped
  before midnight, so it needs a full night.
- [#38]: the accented and vibrant rendering fix is on `main`, and the clear and tinted styles
  have been seen on a real desktop. What's left is the widget in vibrant rendering itself, and
  its states beyond the idle one.
- [#45] and [#46]: the fixes are on `main` with regression tests. What's left is watching
  macOS deliver a notification while Salah handles the same alert, which only a real
  notification center shows.
- [#54]: the large desktop widget redraws after Salah quits while the adhan plays.
- [#64]: notification banners show the place under the title, stack by day, keep the title
  with previews hidden, and open Today when clicked.
- [#14]: run the dropdown's accessibility audit again on a Mac with room for Salah's item.
  Its first run failed on contrast; the contrast fixes for [#40] have landed since, and this
  run decides whether [#40] needs more.

### Open bugs

- [#43]: macOS lowers the priority of scheduled notifications, so Salah's read-back never
  confirms them and replaces unchanged requests on every replan.
- [#28]: the extra-large desktop widget measured 704 × 344 pt, but its faces still draw at
  715 × 342; moving them needs new visual baselines. The banner's Before and After variants
  still need measuring on a Mac.
- The VoiceOver findings listed in [#17]'s comments: check each against the current app, and
  fix the ones that still happen.

### Before a release

The owner's tasks: a signed and notarized download, a Mac App Store listing, and confirmed rights to redistribute
the bundled macOS adhan recordings ([NOTICE](../NOTICE)).

## iPhone and iPad

### Checks on a device

- [#65], over a few days:
  - Qibla against a known bearing, and on iOS 26 with the device lying flat;
  - setup and the current location with Precise Location off;
  - notifications while locked, with Mute on and off;
  - full adhan playback and Stop, a route change and an interruption;
  - background refresh across days;
  - widgets, Live Activities and the Dynamic Island at a real prayer boundary.
- [#28]: StandBy's real widget size.

### Follow-ups

- [#72]: when the stored settings can't be read, Salah keeps the scheduled alerts and the
  widgets' settings, but shows the welcome as on a first launch. It should say the settings
  couldn't be read.
- [#73]: with its language at System, Salah follows the device's languages, not one chosen
  for Salah alone in Settings. The Apple TV app does the same.
- [#75]: a permission journey fails on some Macs, where the simulator's Settings puts
  Salah's row under its search field.

### Before a release

The owner's tasks: App Store Connect records for the app and its widgets, distribution signing, the privacy
answers from [privacy.md](privacy.md), screenshots, and TestFlight.

## iPhone Duo

- [#67], in the hand: the outer display, the open display on its side and upright, opening
  and closing on each screen, the vertical Dynamic Island with its live progress ring, and
  Qibla in each pose.
- [#67]'s simulator checks, which need a person because XCTest can't choose a pose: the
  pose journeys in Device Hub, a pose change while a screen shows, upright in Arabic and at
  accessibility sizes, and Split View on the inner display.

### Not built

Ideas from the design that the app leaves out, each a feature change: two Salah windows side
by side, the bell sheet for a prayer's alerts, a sky that follows the hinge, and Qibla on the
table.

## Apple TV

- [#69], with a television and a Siri Remote:
  - the adhan through the television, and each way to stop it;
  - leaving Salah during the adhan;
  - the screen saver and sleep, and an hour of the room display;
  - the Top Shelf in light and dark appearance, and after a prayer begins while Salah is
    closed;
  - the clickpad and the touch surface, with Larger Text and Bold Text;
  - the settings after a restart.
- The Apple TV section of [#17]: VoiceOver through setup, Today, the room display, the adhan,
  Week and Settings, in English and Arabic.
- [#74]: a journey for Back on the location alert, and a unit test for the Top Shelf's
  reload at a phase change.

### Before a release

The owner's task: the Apple TV app has its own bundle identifier, `io.github.salah-kit.Salah.tvOS`. Whether it
shares a universal purchase with the iPhone app is the owner's decision at release.

## Apple Watch

- [#77], with an Apple Watch and its iPhone:
  - the preferences reaching a newly installed watch app, a change on the iPhone following,
    and the watch keeping its times with the iPhone away;
  - the iPhone's notifications on the watch, and while Salah is open on it;
  - the compass, its location request, and the tap on the wrist when facing the Qibla;
  - the adhan through the watch's speaker and through headphones, with the wrist down;
  - the complications on real faces in each family, full color and tinted, and the Smart
    Stack around a prayer.
- [#27]: the icon in the App Switcher, which needs a person to double-press the Digital
  Crown.
- The Apple Watch section of [#17]: VoiceOver through the pages, the Qibla dial and Stop.

### Before a release

The owner's task: the watch app ships inside the iPhone app, so it's on the iPhone app's App
Store record, and distribution signing covers its bundle identifiers,
`io.github.salah-kit.Salah.iOS.watchkitapp` and its complications'.

## Every app

- [#17]: a VoiceOver user listening through each app.
- Native speakers reviewing the drafted text. String Catalog entries stay `needs_review`
  until then: Arabic [#18], French [#19], Urdu [#20], Indonesian [#21], Turkish [#22],
  Persian [#23], Bengali [#24] and Malay [#25].

[#11]: https://github.com/salah-kit/Salah/issues/11
[#12]: https://github.com/salah-kit/Salah/issues/12
[#14]: https://github.com/salah-kit/Salah/issues/14
[#15]: https://github.com/salah-kit/Salah/issues/15
[#16]: https://github.com/salah-kit/Salah/issues/16
[#17]: https://github.com/salah-kit/Salah/issues/17
[#18]: https://github.com/salah-kit/Salah/issues/18
[#19]: https://github.com/salah-kit/Salah/issues/19
[#20]: https://github.com/salah-kit/Salah/issues/20
[#21]: https://github.com/salah-kit/Salah/issues/21
[#22]: https://github.com/salah-kit/Salah/issues/22
[#23]: https://github.com/salah-kit/Salah/issues/23
[#24]: https://github.com/salah-kit/Salah/issues/24
[#25]: https://github.com/salah-kit/Salah/issues/25
[#27]: https://github.com/salah-kit/Salah/issues/27
[#28]: https://github.com/salah-kit/Salah/issues/28
[#38]: https://github.com/salah-kit/Salah/issues/38
[#40]: https://github.com/salah-kit/Salah/issues/40
[#43]: https://github.com/salah-kit/Salah/issues/43
[#45]: https://github.com/salah-kit/Salah/issues/45
[#46]: https://github.com/salah-kit/Salah/issues/46
[#54]: https://github.com/salah-kit/Salah/issues/54
[#64]: https://github.com/salah-kit/Salah/issues/64
[#65]: https://github.com/salah-kit/Salah/issues/65
[#67]: https://github.com/salah-kit/Salah/issues/67
[#69]: https://github.com/salah-kit/Salah/issues/69
[#72]: https://github.com/salah-kit/Salah/issues/72
[#73]: https://github.com/salah-kit/Salah/issues/73
[#74]: https://github.com/salah-kit/Salah/issues/74
[#75]: https://github.com/salah-kit/Salah/issues/75
[#77]: https://github.com/salah-kit/Salah/issues/77
