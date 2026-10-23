# iOS verification and remaining validation

The iPhone and iPad app is available as Unreleased source. There is no iOS App Store
listing or signed iOS download yet. Simulator builds need no paid developer membership;
[CONTRIBUTING](../CONTRIBUTING.md#ios-and-ipados) explains how to build and run them.

## Reproducible checks

[`scripts/verify-ios.sh`](../scripts/verify-ios.sh) builds the app and extension, runs
logic and adapter tests, and drives the installed app through XCUITest. The iPhone and
iPad CI jobs upload their result bundles. The script keeps each simulator run separate
and uses fresh app installations for permission cases.

- Logic and adapter tests cover calculation and presentation state, preference
  transactions, notification plans, audio bounds, localized text and shared widget and
  activity contracts.
- App journeys cover setup, location and calculation choices, day and week navigation,
  Qibla recovery, independent alert settings, explicit playback and Stop, and preference
  persistence across relaunch. iPad journeys exercise the settings list and detail.
- Permission journeys use the actual system prompts, including Allow, Don't Allow and
  returning after notification access changes in Settings. Production storage journeys
  use the actual App Group rather than an isolated preferences fixture.

A rendered widget test covers the view it draws. Actual placement and interaction in
Home Screen, Lock Screen, Control Center and Live Activity hosts are separate checks;
source inspection or a preview does not establish that a system host ran an action.
Keep the build's commit and OS version with any reported native-host evidence.

## Pending

- [Physical iPhone/iPad and elapsed-time validation (#65)](https://github.com/salah-kit/Salah/issues/65):
  compass accuracy, audible delivery while locked, physical audio routes and
  interruptions, real system presentation and OS-granted refresh across days.
  [StandBy measurements (#28)](https://github.com/salah-kit/Salah/issues/28) remain in
  the existing design-size issue.
- [VoiceOver review (#17)](https://github.com/salah-kit/Salah/issues/17): spoken
  wording, navigation order and actions across the app and system surfaces. Automated
  label and structure assertions do not complete this listening review.
- Native-speaker review of draft iOS app, permission and system-surface text. Entries
  remain `needs_review` until reviewed; compiling and rendering them does not approve
  their wording.

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

- Scheduled notifications use short sound excerpts. Full adhan playback starts only
  from an explicit action; it is not launched by a scheduled notification. iOS and the
  person's notification, Focus, Silent Mode and Time Sensitive settings determine
  presentation and audibility.
- Planning considers fourteen days and installs at most sixty pending prayer alerts.
  The covered time range depends on enabled reminders. Opening the app replenishes
  the plan; background refresh can also replenish it when iOS grants execution time.
  There is no fixed refresh interval or promise of indefinite delivery without opening
  the app.
- A device without heading hardware shows the calculated Qibla bearing rather than a
  working compass. Simulator bearing checks do not establish physical sensor accuracy.
- Live Activities, Dynamic Island, Control Center and widget presentation follow the
  device's capabilities and system rules. App and widget settings are shared locally;
  there is no settings sync between iPhone, iPad and Mac.

