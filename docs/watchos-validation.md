# watchOS verification and remaining validation

The Apple Watch app is available as Unreleased source, inside the iPhone app. There is no
App Store listing or signed download yet. Simulator builds need no paid developer
membership; [CONTRIBUTING](../CONTRIBUTING.md#watchos) explains how to build and run them.

## Reproducible checks

[`scripts/verify-watchos.sh`](../scripts/verify-watchos.sh) builds the Release app and its
complications for a generic Apple Watch, runs the logic tests, and drives the installed app
with taps, swipes and the Digital Crown through XCUITest, on a 46 mm simulator it creates and
deletes. The watchOS CI job runs it and uploads the result bundles. The iPhone jobs build the
iPhone app with the watch app inside it.

- Logic tests cover the hero in each of its states and the rows in English and Arabic,
  the Qibla's states and turns, the receive path for the iPhone's preferences and the
  request for them, the adhan plan and its catch-up across relaunches, the runtime's
  composition with the complications' mirror, the complications' timeline, relevance and
  every family's drawing, links, and the launch configuration. `SalahIOSTests` covers what
  the iPhone sends and when.
- Core journeys cover the next prayer with the rest of its day, the pages through Today to
  the Qibla, the adhan at prayer time with Stop, a muted watch, Arabic with Arabic
  digits, the xxxLarge text size, the Qibla without a compass and facing it, the
  preferences kept across a relaunch, and a watch with no preferences asking for the iPhone.
- The production journey launches without Debug options after a fresh install: the watch
  has no preferences and asks for the iPhone.
- The paired journey ([`scripts/paired-watch-journey.sh`](../scripts/paired-watch-journey.sh))
  sets Salah up on an iPhone simulator and waits on the paired watch simulator for the place
  it sent. The Smart Stack journey
  ([`scripts/smart-stack-journey.sh`](../scripts/smart-stack-journey.sh)) adds Salah's widget
  to the Smart Stack, checks that it names the next prayer, and reads the timeline the
  extension built from the watch's settings. Both run locally, not on CI: WatchConnectivity
  between simulators hasn't been shown to be reliable on hosted runners, and the Smart Stack
  journey drives the system's own interface, which can change with a watchOS release.

## Pending

- [Physical Apple Watch validation (#77)](https://github.com/salah-kit/Salah/issues/77):
  the preferences reaching a new watch from a real iPhone and a change following; the
  iPhone's notifications on the watch; the compass and its location request; the adhan
  through the watch's speaker and through headphones, with the wrist down; the
  complications on real faces in each family; and the Smart Stack around a prayer.
- [The watch icon in the App Switcher (#27)](https://github.com/salah-kit/Salah/issues/27).
- [VoiceOver review (#17)](https://github.com/salah-kit/Salah/issues/17): the hero and rows
  as sentences, the Qibla dial's updates, and Stop. Automated label assertions don't
  complete this listening review.
- Native-speaker review of the draft watchOS text in
  [`Localizable.xcstrings`](../SalahWatchShared/Resources/Localizable.xcstrings) and
  [`InfoPlist.xcstrings`](../SalahWatch/Resources/InfoPlist.xcstrings). Entries stay
  `needs_review` until reviewed, in the same issues as the iOS text:

| Language | Review issue |
|---|---|
| Arabic | [#18](https://github.com/salah-kit/Salah/issues/18) |
| French | [#19](https://github.com/salah-kit/Salah/issues/19) |
| Urdu | [#20](https://github.com/salah-kit/Salah/issues/20) |
| Indonesian | [#21](https://github.com/salah-kit/Salah/issues/21) |
| Turkish | [#22](https://github.com/salah-kit/Salah/issues/22) |
| Persian | [#23](https://github.com/salah-kit/Salah/issues/23) |
| Bengali | [#24](https://github.com/salah-kit/Salah/issues/24) |
| Malay | [#25](https://github.com/salah-kit/Salah/issues/25) |

## Known limitations

- The watch needs the iPhone app: its preferences come from the iPhone, and there is no
  setup on the watch. A watch that has never received them shows where to set Salah up.
- The adhan plays only while Salah is open on the watch. The watch schedules no
  notifications of its own, so the iPhone's alerts are what reach the wrist when Salah
  isn't open, as iOS decides: on the watch while the iPhone is locked and the watch is worn.
- A system sound or an imported recording chosen on the iPhone plays the soft tone on the
  watch, which has neither.
- The compass needs the watch's location to point to true north; without location access,
  or without a compass, the dial gives the bearing in degrees, with no direction to turn.
