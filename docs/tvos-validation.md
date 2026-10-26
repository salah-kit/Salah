# tvOS verification and remaining validation

The Apple TV app is available as Unreleased source. There is no App Store listing or
signed download yet. Simulator builds need no paid developer membership;
[CONTRIBUTING](../CONTRIBUTING.md#tvos) explains how to build and run them.

## Reproducible checks

[`scripts/verify-tvos.sh`](../scripts/verify-tvos.sh) builds the Release app and its Top
Shelf extension for a generic Apple TV, runs the logic tests, and drives the installed app
with the Siri Remote through XCUITest, on a simulator it creates and deletes. The tvOS CI
job runs it and uploads the result bundles.

- Logic tests cover the hero, rows and notes in English and Arabic, navigation and links,
  the adhan plan and its clock, the Top Shelf snapshot, its images at both screen scales,
  when the app asks for a reload, the launch configuration, storage and sound.
- Core journeys cover Today and where focus lands, a prayer row opening its sound, the
  room display with Back and after Home and back, the adhan at prayer time with Stop, with
  Play/Pause and Back over the room display, over a prayer's sound page and over a browsed
  week, the week turning at both ends and coming back to the current week, About scrolling
  to its end, choices kept across a relaunch, Arabic right to left with Arabic digits, and
  Larger Text with Today's hero and source line in reach.
- The Top Shelf journey goes to the Home Screen, finds the three banners the extension drew
  from the app's mirror, and opens the room display from its banner.
- Permission journeys answer the real location alert with Allow Once and with Don't Allow.
  The production journey sets up with a city from Apple Maps search, in the app's own
  defaults and with the real clock, and checks a setting after a relaunch.

## Pending

- [Physical Apple TV validation (#69)](https://github.com/salah-kit/Salah/issues/69):
  the adhan and the tone through a television and a receiver, Stop and Play/Pause on a
  Siri Remote, the room display keeping the screen on for an hour, the Top Shelf on the
  Home Screen across a prayer time, and the app after tvOS clears its caches.
- [VoiceOver review (#17)](https://github.com/salah-kit/Salah/issues/17):
  spoken wording, the order of the rows, columns and Settings, and the week's actions.
  Automated label and structure assertions don't complete this listening review.
- Native-speaker review of the draft tvOS text in
  [`Localizable.xcstrings`](../SalahTVShared/Resources/Localizable.xcstrings) and
  [`InfoPlist.xcstrings`](../SalahTV/Resources/InfoPlist.xcstrings). Entries stay
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

- The adhan plays only while Salah is on screen. A tvOS notification can only badge an
  icon, and the app has no background audio, so leaving Salah stops the sound.
- Outside the room display and the adhan, the Apple TV's own screen saver and sleep
  settings apply. Once the Apple TV sleeps, Salah is no longer open and no adhan plays;
  Keep on Screen holds off the screen saver while it's open.
- Apple TV has no reminders before or after a prayer, no imported recordings and no
  system sounds; each prayer has the regular or Fajr adhan, the soft tone, or no sound.
- The Top Shelf shows the times as they were when tvOS last asked for them. Salah asks for
  a new set when the next prayer, the day or the time of day changes while it runs; while
  it's closed, tvOS decides when to ask, so a banner can still name a prayer that has
  begun.
