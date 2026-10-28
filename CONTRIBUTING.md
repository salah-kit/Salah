# Contributing to Salah

Thanks for helping. This file covers building, testing, formatting and releasing this repo. The
org-wide code of conduct, security policy and support page live in
[salah-kit/.github](https://github.com/salah-kit/.github).

## What you need

- macOS with Xcode 27. The Mac app runs on macOS 14 or later; the iPhone and iPad
  app runs on iOS and iPadOS 26 or later, and the Apple TV app on tvOS 26 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46, only if you change `project.yml`
  or add, move or remove a file.
- `swift format`, which ships with Xcode.

## The project

`Salah.xcodeproj` is generated from `project.yml` by XcodeGen. Don't edit the project in
Xcode's build settings or target editors: change `project.yml`, run `xcodegen` in the repo
root, and commit both. Run `xcodegen` after adding, moving or removing a source file, too,
because the project lists files explicitly. CI fails when the committed project doesn't
match `project.yml`.

| Target | What it is |
|---|---|
| `Salah` | The menu-bar app (`io.github.salah-kit.Salah`) |
| `SalahWidgetsExtension` | The WidgetKit extension (`io.github.salah-kit.Salah.Widgets`) |
| `SalahTests` | Unit and visual-baseline tests (the `Salah` scheme) |
| `SalahUITests` | UI tests that drive the real app (their own `SalahUITests` scheme) |
| `SalahRoundTripTests` | Tests that run the real app and the stop harness as processes (their own scheme) |
| `SalahStopHarness` | A stand-in for the widget extension in those tests (`io.github.salah-kit.Salah.StopHarness`) |
| `SalahIOS` | The iPhone and iPad app (`io.github.salah-kit.Salah.iOS`) |
| `SalahIOSWidgets` | Home Screen, Lock Screen, Live Activity and Control Center extension (`io.github.salah-kit.Salah.iOS.Widgets`) |
| `SalahIOSTests` | iOS logic and adapter tests (the `SalahIOS` scheme) |
| `SalahIOSUITests` | Journeys through the running iOS app (their own scheme) |
| `SalahTV` | The Apple TV app (`io.github.salah-kit.Salah.tvOS`) |
| `SalahTVTopShelf` | The Top Shelf extension (`io.github.salah-kit.Salah.tvOS.TopShelf`) |
| `SalahTVTests` | tvOS logic tests (the `SalahTV` scheme) |
| `SalahTVUITests` | Journeys through the running Apple TV app (their own scheme) |
| `SalahWatch` | The Apple Watch app, inside the iPhone app (`io.github.salah-kit.Salah.iOS.watchkitapp`) |
| `SalahWatchWidgets` | The complications and Smart Stack widget (`io.github.salah-kit.Salah.iOS.watchkitapp.Widgets`) |
| `SalahWatchTests` | watchOS logic tests (the `SalahWatch` scheme) |
| `SalahWatchUITests` | Journeys through the running watch app (their own scheme) |

`Salah/` holds the app, `SalahWidgetsExtension/` the extension, and `Shared/` the code both
compile: the settings the app mirrors for the widget (`SalahSettings`), what's playing
(`SalahPlayback`), Salah's prayer source, the display model the widget and the menu bar
draw from (`SalahDisplay`), the widget's timeline, and the palette and views. The two share
the App Group `group.io.github.salah-kit.Salah`. Prayer times, the schedule, widget
timelines, alerts and the UI components come from
[SalahKit](https://github.com/salah-kit/SalahKit), through its public API only.

`SalahIOS/` contains the iOS app. Its domain and data layers own preferences, prayer
selection and platform services; its design system and feature views build on those
contracts. `SalahIOSShared/` contains the iOS contracts compiled into the app and the
extension in `SalahIOSWidgets/`. Both reuse the portable settings, prayer, display and
timeline models from `Shared/`, and mirror preferences through the same App Group
identifier. This is local sharing between the app and its extension, without a sync
service between devices.

`SalahTV/` contains the Apple TV app and `SalahTVTopShelf/` its Top Shelf extension.
`SalahTVShared/` holds what both compile: the theme, the wording helpers, the Top Shelf's
snapshot and banners, and the String Catalog. The app also compiles the iOS app's store,
preferences, preference storage, city search and audio files from `SalahIOS/` and
`SalahIOSShared/`, so a change there builds and tests on both. The
[tvOS architecture](docs/tvos-architecture.md) describes the split.

`SalahWatch/` contains the Apple Watch app and `SalahWatchWidgets/` its complications.
`SalahWatchShared/` holds what both compile: the theme, the wording helper and the String
Catalog. The app compiles the iOS app's store, preferences, preference storage, presentation
and audio files, and the complications the Lock Screen's accessory wording, so a change there
builds and tests on both. The iPhone app sends the watch its preferences over
WatchConnectivity (`SalahIOS/Data/Watch`); the watch keeps its own copy. The
[watchOS architecture](docs/watchos-architecture.md) describes the split.

## Signing

No signing team is committed. `Config/Shared.xcconfig` includes your own
`Config/Local.xcconfig`, which git ignores:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
# then set DEVELOPMENT_TEAM = <your team ID> in Config/Local.xcconfig
```

With a team, Xcode signs automatically; add `-allowProvisioningUpdates` to command-line
builds so it can register the bundle identifiers and the App Group. Sign with a team to
run the app: the App Group it shares with its widget comes from your team's provisioning
profile.

Without a team you can still build and test:

```sh
# Unsigned, as CI builds it.
xcodebuild build -project Salah.xcodeproj -scheme Salah -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Building the app registers it, and its widget extension, with LaunchServices. Delete
build products you no longer need, so an old build doesn't serve your widget.

### iOS and iPadOS

Simulator builds and journeys need no paid Apple Developer membership or provisioning
profile. Simulator apps are signed ad hoc so their App Group entitlements are available;
they are not distribution builds. Install an iOS 26 or later simulator runtime through
Xcode's Components settings.
The app's App Group and Time Sensitive notification entitlements are generated from
its `project.yml` declaration; keep the widget's App Group identifier matching.
Run the shared CI entry point from the repository root:

```sh
# Builds an unsigned Release app and extension for a generic iOS device, then
# runs unit tests and real-app journeys on an iPhone simulator.
bash scripts/verify-ios.sh

# Runs unit tests and the iPad journeys on an iPad simulator.
SALAH_IOS_SIMULATOR_FAMILY=iPad bash scripts/verify-ios.sh

# Runs unit tests and the iPhone Duo journeys on its outer display. Needs the
# iOS 27.1 simulator runtime, the first with iPhone Duo.
SALAH_IOS_SIMULATOR_FAMILY=Duo bash scripts/verify-ios.sh
```

The script selects a compatible device from installed runtimes, creates a simulator,
boots it without opening Simulator.app, and deletes that device on success or failure.
It leaves build products and test results in `.derived/ios-iPhone`, `.derived/ios-iPad`
or `.derived/ios-Duo`; remove those directories when they are no longer needed. Each test
run has its own `Results` directory containing the unit and journey result bundles.
The phone, tablet and iPhone Duo have separate core journey classes. Permission journeys
uninstall and reinstall only the app on the task's simulator before each case, so both
Allow and Don't Allow encounter a fresh system prompt. A fixed simulator location supplies
a real Core Location fix. CI runs all three and uploads those bundles.

An iPhone Duo simulator starts closed, so its journeys check the outer display. XCTest
can't fold or turn it, but Device Hub, which Xcode installs in
`Xcode.app/Contents/Applications`, can. `IOSDuoPoseJourneys` checks the other poses.
Create an iPhone Duo simulator, choose it in Device Hub, and use its hinge and rotation
controls to set each of these poses, running the class after each:

- Closed and turned on its side: the tent.
- Open on its side, flat, then partly folded like a book.
- Open upright, flat, then partly folded like a laptop.

```sh
xcrun simctl create "Salah Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo \
  com.apple.CoreSimulator.SimRuntime.iOS-27-1
xcodebuild test -project Salah.xcodeproj -scheme SalahIOSUITests \
  -destination 'platform=iOS Simulator,id=<simulator id>' \
  -only-testing:SalahIOSUITests/IOSDuoPoseJourneys -derivedDataPath .derived/ios-Duo \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
```

Each test skips unless the simulator is in its pose. Delete the simulator when you're done.

To build a simulator app without running tests:

```sh
xcodebuild build -project Salah.xcodeproj -scheme SalahIOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .derived/ios \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
```

To run on a physical device, configure your team in `Config/Local.xcconfig` and use
`-allowProvisioningUpdates`. Enable the existing App Group for the app and extension.
App Store distribution needs a paid membership; device notification delivery, compass
accuracy and system scheduling should also be checked on the intended device. Follow
the steps in [#65](https://github.com/salah-kit/Salah/issues/65), or
[#67](https://github.com/salah-kit/Salah/issues/67) on iPhone Duo, and record the commit,
device, OS version and observed results. The [iOS validation notes](docs/ios-validation.md)
also link VoiceOver and native-language review; leave checks that require hardware,
elapsed time or another person open until their evidence is recorded.

iOS includes licensed regular and Fajr adhan recordings, a synthesized tone and system
sounds, and accepts imported audio. [NOTICE](NOTICE) records the licenses; Audio credits
in the app reads the bundled notice. Notification excerpts are shorter than thirty
seconds. Imported recordings can be up to thirty minutes long; longer files are
rejected before copying and checked again at playback. A scheduled notification does
not launch full adhan playback. Full playback
starts from an explicit app action and uses the background audio mode to continue when
the app leaves the foreground. The optional du'a uses speech synthesis after a built-in
or imported adhan and lasts at most two minutes. Shared playback and external Stop
controls cover the whole session, up to thirty-two minutes including the du'a.
Background refresh replenishes the rolling schedule when iOS grants execution time;
the system controls when it runs.

### tvOS

Simulator builds and journeys need no paid Apple Developer membership or provisioning
profile. Install a tvOS 26 or later simulator runtime through Xcode's Components settings.
The app and its Top Shelf extension share the App Group `group.io.github.salah-kit.Salah`;
both entitlements are generated from `project.yml`. Run the shared CI entry point from the
repository root:

```sh
# Builds an unsigned Release app and Top Shelf extension for a generic Apple TV, then
# runs the logic tests and real-app journeys on an Apple TV simulator.
bash scripts/verify-tvos.sh
```

The script selects an installed runtime and an Apple TV type, creates a simulator, boots it
without opening Simulator.app, and deletes it on success or failure. It leaves build
products and test results in `.derived/tvos`; each run has its own `Results` directory.
A fixed simulator location supplies a Core Location fix. The permission journeys reset
Salah's location permission before each case, so Allow Once and Don't Allow each meet a
fresh system alert; the production journey runs after a fresh install. The city and
location journeys use Apple Maps and need a network connection. The Top Shelf journey
drives the simulator's Home Screen, where Salah's icon has to be in the top row, as it is
on a new simulator. [`SalahTVUITests/README.md`](SalahTVUITests/README.md) lists the
journeys and the Debug launch options they use.

To build a simulator app without running tests:

```sh
xcodebuild build -project Salah.xcodeproj -scheme SalahTV -configuration Debug \
  -destination 'generic/platform=tvOS Simulator' -derivedDataPath .derived/tvos \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
```

To run on an Apple TV, configure your team in `Config/Local.xcconfig`, use
`-allowProvisioningUpdates`, and enable the App Group for the app and the extension.
Sound through a television, the screen saver and the Siri Remote need a real device:
follow [#69](https://github.com/salah-kit/Salah/issues/69) and record the commit,
the Apple TV model, the tvOS version and what you observed. The
[tvOS validation notes](docs/tvos-validation.md) link the VoiceOver and native-language
reviews too.

The Apple TV app bundles the same two CC BY 4.0 recordings as iOS and generates the soft
tone; [NOTICE](NOTICE) records the licenses, and About in the app reads the bundled audio
notice. A tvOS notification can't play a sound, so the adhan plays only while Salah is
open, from SalahAlerts' in-process engine, and stops when Salah leaves the screen. tvOS
keeps only an app's defaults across launches, so preferences live there, and the settings
mirror for the Top Shelf goes through the App Group.

### watchOS

The Apple Watch app is the iPhone app's companion: the `SalahIOS` scheme builds it and embeds
it in the iPhone app, and the `SalahWatch` scheme builds and runs it on its own. Simulator
builds and journeys need no paid Apple Developer membership or provisioning profile. Install
a watchOS 26 or later simulator runtime through Xcode's Components settings. The app and its
complications share the App Group `group.io.github.salah-kit.Salah` on the watch; both
entitlements are generated from `project.yml`. Run the shared CI entry point from the
repository root:

```sh
# Builds an unsigned Release app and its complications for a generic Apple Watch, then runs
# the logic tests and real-app journeys on an Apple Watch simulator.
bash scripts/verify-watchos.sh
```

The script selects an installed runtime and a 46 mm Apple Watch, creates a simulator, boots
it without opening Simulator.app, and deletes it on success or failure. It leaves build
products and test results in `.derived/watchos`; each run has its own `Results` directory.
The journeys stand in for the iPhone with a Debug fixture of the preferences it would send,
and fix the compass's reading, as the simulator has none; the production journey runs after
a fresh install and waits for the iPhone.
[`SalahWatchUITests/README.md`](SalahWatchUITests/README.md) lists the journeys and the Debug
launch options they use.

The paired journey checks the preferences' way from the iPhone app to the watch: it installs
the iPhone app, with the watch app inside, on an iPhone simulator paired with a watch
simulator, sets Salah up on the iPhone from a fixture, and waits for the watch's Qibla page to
show the bearing from the place the iPhone sent. Create and pair the two simulators, then run
it with their identifiers:

```sh
phone=$(xcrun simctl create "Salah paired iPhone" "iPhone 17 Pro")
watch=$(xcrun simctl create "Salah paired watch" "Apple Watch Series 12 (46mm)")
xcrun simctl pair "$watch" "$phone"
bash scripts/paired-watch-journey.sh "$phone" "$watch"
```

WatchConnectivity between simulators hasn't been shown to be reliable on hosted runners, so
CI doesn't run it; run it when you change how the preferences are sent or received.

The Smart Stack journey runs the complications' extension on the watch face: on a new watch
simulator it adds Salah's widget to the Smart Stack through the face's own process, checks
that the widget reads a prayer there and that a tap on it opens Salah's first page, and reads
the timeline the extension logged, which it builds from the settings the app mirrored. It
drives the system's own interface, which can change with a watchOS release, so CI doesn't run
it; run it when you change the complications:

```sh
bash scripts/smart-stack-journey.sh
```

To build a simulator app without running tests:

```sh
xcodebuild build -project Salah.xcodeproj -scheme SalahWatch -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath .derived/watchos \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=
```

To run on an Apple Watch, configure your team in `Config/Local.xcconfig`, run the `SalahIOS`
scheme on the paired iPhone with `-allowProvisioningUpdates`, and enable the App Group for
the watch app and its complications. The compass, sound through the watch's speaker,
notifications forwarded from the iPhone and complications on a real face need a watch:
follow [#77](https://github.com/salah-kit/Salah/issues/77) and record the commit, the watch
and iPhone models, their system versions and what you observed. The [watchOS validation
notes](docs/watchos-validation.md) link the VoiceOver and native-language reviews too.

The watch app bundles the same two CC BY 4.0 recordings as iOS and generates the soft tone;
it ships inside the iPhone app, whose notice and About credit them ([NOTICE](NOTICE)). The
iPhone schedules the alerts, so the watch schedules none: its adhan plays only while Salah is
open, from SalahAlerts' in-process engine, and stops when Salah leaves the screen.

## Tests

The tests run in a test bundle that compiles the app's sources itself and never launches
the app, so they need no team, permission or App Group. Run both commands; CI does:

```sh
xcodebuild test -project Salah.xcodeproj -scheme Salah -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=

# The Arabic menu-bar baselines render in an Arabic process, as the app runs its menu.
xcodebuild test -project Salah.xcodeproj -scheme Salah -destination 'platform=macOS' \
  -only-testing:SalahTests/VisualBaselineTests -testLanguage ar \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

The scheme pins the test process's languages to US English; keep it that way, or the
visual baselines depend on the machine's language list.

### UI tests

`SalahUITests` launches the real app and checks its status item, the menu-bar dropdown,
the `salah://settings` link a widget tap opens, Salah's window and the About panel.
`LifecycleUITests` checks how the window opens, closes and quits: the Dock icon while it's
open (hidden or minimized included), ⌘Q closing it to the menu bar, the one-time note,
Quit Salah, and a login launch staying quiet.
Two of them change an alert in Settings → Notifications and wait for its minute: they
move a prayer about two minutes ahead with Salah's own adjustments, turn its alert on
(the Alafasy adhan then plays at that minute) or off (nothing plays). They read what the
app publishes in its App Group, as the widget does, so the test runner is signed with
your team into the same App Group (`SalahUITests/SalahUITests.entitlements`). It builds
and launches the app, so it needs your team in `Config/Local.xcconfig`. UI testing on
macOS runs in Automation Mode; the first time, macOS may ask an administrator to allow it
(`automationmodetool` shows whether it will). A full run takes about 15 minutes: the two
alert tests take about five, and `VoiceOverSpeechUITests`, which turns VoiceOver on
(below), about ten:

```sh
xcodebuild test -project Salah.xcodeproj -scheme SalahUITests -destination 'platform=macOS' \
  -allowProvisioningUpdates
```

CI builds these tests but doesn't run them, because its runners have no team to sign
the app with. The tests launch Salah under its real identity, without prompts: no
automatic location, English, the default menu-bar format, every alert off but the one a
test changes, and `-salah.debug.withoutSystemPrompts` for the alert tests (Debug builds
only), so neither the app nor its Notifications tab asks for notification permission.
Two things follow on the Mac you run them on:

- They quit a running Salah, and leave it quit.
- With `-salah.debug.scratchPreferences` (Debug builds only), the app keeps the
  preferences it was launched with in a scratch suite, and with
  `-salah.debug.withoutSystemNotifications` its alerts go to a notification center of
  its own that holds nothing, so this Mac's own Salah preferences and notifications are
  untouched. What remains is the App Group's mirrored settings from the last test launch,
  which a placed widget shows until Salah runs again and publishes its own: Makkah with
  every alert off after a full run, or, after the alert tests without the others, a
  prayer moved by the last one's adjustment, with its alert.

The dropdown tests skip when the menu bar is so full that macOS puts Salah's status
item behind the camera housing or in its overflow, where a click doesn't reach it.

`VoiceOverSpeechUITests` turns VoiceOver on through XCTest's VoiceOver service and checks
what VoiceOver says for the pop-ups and pickers each Settings pane shows when it opens, the
Appearance preview, and the dropdown's prayers and countdown in English and Arabic. Keys
reach VoiceOver too: one test opens the time zone's pop-up with VO-Space, and another
changes the name style with VoiceOver and back. They need macOS 27 in English, with
VoiceOver's default settings: VoiceOver says its own words, such as "selected" and
"dimmed", in the Mac's language and as its verbosity settings choose, and the tests send
VO-Space as Control-Option. They turn VoiceOver on and off themselves, and skip when it's
already on, leaving it as it is: turn it off and run them again. They also skip before
macOS 27, on a Mac that isn't in English, and when VoiceOver doesn't turn on. They take
about ten minutes:

```sh
xcodebuild test -project Salah.xcodeproj -scheme SalahUITests -destination 'platform=macOS' \
  -allowProvisioningUpdates -only-testing:SalahUITests/VoiceOverSpeechUITests
```

VoiceOver speaks aloud while these tests run and reads whichever app is in front, so leave
the Mac alone, with Do Not Disturb on, until they end. If VoiceOver Quickstart, VoiceOver's
welcome window, is open, close it first: VoiceOver reads it instead of Salah, and the tests
fail with "VoiceOver didn't say anything in Settings". A test keeps only what VoiceOver
says after its own moves in the window it reads, and, after a key press, the exact words it
waits for; it fails at the first move after Salah leaves the front or that window closes.
Speech VoiceOver makes for another app right after a move, such as a notification it reads
out, can still be kept. Each test turns VoiceOver off at its end. A run that stops first,
or whose VoiceOver didn't turn on, leaves the time it turned VoiceOver on in the test
runner's defaults: for half an hour after that, the tests take VoiceOver that's on as
theirs, even one you turned on meanwhile, restart it, and turn it off at their end.
Command-F5 turns it off too.

When a test fails, Xcode keeps screenshots and a screen recording of the whole screen in
the result bundle, so share its failure message and its "VoiceOver" attachment, not the
bundle, and read both first: they can hold speech for another app. To get the attachment
from a run on the command line, add `-resultBundlePath VoiceOver.xcresult` to the command
above (xcodebuild won't write over a bundle that's already there), then export each
test's "VoiceOver" text file; `VoiceOver/manifest.json` says which test each is from:

```sh
xcrun xcresulttool export attachments --path VoiceOver.xcresult --output-path VoiceOver \
  --filter 'VoiceOver*'
```

### Real-app tests

`SalahRoundTripTests` runs the real, signed app and `SalahStopHarness` as separate
processes. The harness stands in for the widget extension: sandboxed in the same App
Group, it runs the Stop intent's own code and reads back what the app stored. The tests
move a prayer a minute or two ahead with Salah's own adjustments, so a real alert comes
due, then check the widget's stop round trip, the stop signal alone, an alert missed
while the app was frozen as during sleep (caught up once) and a reminder missed past its
grace (dropped), and that a changed alert setting replans at the next launch. They read
the app's log with `log stream`, only the lines of the process they launched, so they
run without a host app, outside any sandbox. They take about 15 minutes:

```sh
xcodebuild test -project Salah.xcodeproj -scheme SalahRoundTripTests \
  -destination 'platform=macOS' -allowProvisioningUpdates
```

They need your team, like the UI tests, and CI only builds them. The app runs muted and
with `-salah.debug.withoutSystemPrompts` (Debug builds only), so it never asks for
notification permission or sends Music an Apple Event, and with
`-salah.debug.scratchPreferences` and `-salah.debug.withoutSystemNotifications`, so this
Mac's own Salah preferences and notifications are untouched.
Like the UI tests, they quit a Salah you have running, and leave it quit, so only the
app under test alerts and publishes. Afterwards the App Group holds what the app last
published (Makkah, a prayer moved by the last test's adjustment, its alerts), which a
placed widget shows until Salah runs again.

### Visual baselines

`SalahTests/Baselines/` holds PNG renders of every widget face and the menu-bar dropdown,
in English, Arabic and French, light and dark, with an index in its `README.md`. The
tests render each one and compare it with the PNG; a render that differs is saved to
`.baseline-failures/` (CI uploads it as an artifact). When you change how something
looks on purpose, re-record:

```sh
TEST_RUNNER_SALAH_RECORD_BASELINES=1 xcodebuild test -project Salah.xcodeproj -scheme Salah \
  -destination 'platform=macOS' -only-testing:SalahTests/VisualBaselineTests \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
TEST_RUNNER_SALAH_RECORD_BASELINES=1 xcodebuild test -project Salah.xcodeproj -scheme Salah \
  -destination 'platform=macOS' -only-testing:SalahTests/VisualBaselineTests -testLanguage ar \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

Record mode rewrites only the PNGs that no longer match, so `git status SalahTests/Baselines`
lists exactly what changed. Check every changed image before you commit it. The baselines
were recorded with Xcode 27 on macOS 27; CI uses the same toolchain.

### Checks on a real Mac

Some behavior only shows on a real desktop, or over time: notification banners, sleep and
wake, a clock set back, the widget's Stop control under a real click, and the widget across
midnight. These checks are open issues labelled
[`help wanted`](https://github.com/salah-kit/Salah/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22),
each with its steps and what to record.

### Comparing a screen with its design

The designs show Makkah on Tuesday 2 June 2026 at a given time. Debug builds take two
launch options that put the running app in that state, for a screenshot next to the
design:

- `-salah.debug.now 2026-06-02T13:19:00+03:00` starts the window, the dropdown and the
  menu bar item at that minute, running on from there. Alerts and the widget keep the
  real time.
- `-salah.debug.windowSize 888x520` opens the window at that size in points, title bar
  included, within the window's minimum size.

Build into `.derived`, then launch the build with scratch preferences, no prompts and its
alerts kept from this Mac's notification center:

```sh
xcodebuild build -project Salah.xcodeproj -scheme Salah -destination 'platform=macOS' \
  -derivedDataPath .derived -allowProvisioningUpdates
open -n .derived/Build/Products/Debug/Salah.app --args \
  -salah.debug.scratchPreferences YES -salah.debug.withoutSystemPrompts YES \
  -salah.debug.withoutSystemNotifications YES -salah.alertVolume 0 \
  -salah.debug.now 2026-06-02T13:19:00+03:00 -salah.debug.windowSize 888x520
```

A placed widget then shows the scratch settings until this Mac's Salah runs again.

## Formatting

Code is formatted with `swift format` and the shared `.swift-format` (2-space indentation,
100 columns). CI's lint job fails on any finding.

```sh
swift format format --in-place --recursive Salah SalahWidgetsExtension Shared \
  SalahTests SalahUITests SalahRoundTripTests SalahStopHarness \
  SalahIOS SalahIOSShared SalahIOSWidgets SalahIOSTests SalahIOSUITests \
  SalahTV SalahTVShared SalahTVTopShelf SalahTVTests SalahTVUITests
swift format lint --strict --recursive Salah SalahWidgetsExtension Shared \
  SalahTests SalahUITests SalahRoundTripTests SalahStopHarness \
  SalahIOS SalahIOSShared SalahIOSWidgets SalahIOSTests SalahIOSUITests \
  SalahTV SalahTVShared SalahTVTopShelf SalahTVTests SalahTVUITests
```

## Strings and languages

User-facing text lives in String Catalogs: `Salah/Resources/Localizable.xcstrings`,
`Salah/Resources/InfoPlist.xcstrings` and `SalahWidgetsExtension/Localizable.xcstrings`;
the Apple TV app's are `SalahTVShared/Resources/Localizable.xcstrings`, which its Top Shelf
extension shares, and `SalahTV/Resources/InfoPlist.xcstrings`; the Apple Watch app's are
`SalahWatchShared/Resources/Localizable.xcstrings`, which its complications share, and
`SalahWatch/Resources/InfoPlist.xcstrings`.
The widget's own labels are in `SalahWidgetLabels` (`Shared/SalahWidgetModels.swift`),
because the extension can't read the app's String Catalog; prayer names come from
SalahCore's `PrayerNames`. Every change needs all nine
languages and right-to-left layouts for Arabic, Urdu and Persian. Mark machine-drafted
translations `needs_review` in the catalog, and ask for a native speaker's review in your
pull request. The entries that still need a native speaker are listed by language in open
issues labelled
[`translation`](https://github.com/salah-kit/Salah/issues?q=is%3Aissue+is%3Aopen+label%3Atranslation).

The app's name is "Salah" in Latin script in every language except Arabic, where it is
صلاة.

## The app icon

The app's icon is `Design/AppIcon/Salah.icon`, an Icon Composer document that Xcode compiles
with the app; [Design/README.md](Design/README.md#app-icon) says how to edit and check it.
The Apple TV app's layered icon and Top Shelf images are brand assets in
`SalahTV/Assets.xcassets`, rendered from the layers in `Design/AppIcon/tvOS`
([Design/README.md](Design/README.md#apple-tv-icon-and-top-shelf) has the steps).

## Pull requests

Work on a short-lived branch named for its topic, keep `main` green, and describe what
you verified. A fix comes with a test that would have caught the bug. If users can notice
the change, add a line to the Unreleased section of [CHANGELOG.md](CHANGELOG.md).

## Releasing

A maintainer releases from `main`, as the ecosystem standard's
[Releases](https://github.com/salah-kit/.github/blob/main/STANDARD.md#releases) section
describes. A release has a marketing version (`1.1.2`) and a build number one higher than
the last release's; tags are the marketing version, with no `v`.

1. **Prepare the release** in a pull request:
   - set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for every target in `project.yml`,
     and run `xcodegen`;
   - update the version strings the UI tests expect in `SalahUITests/SalahUITests.swift`
     (`Salah X.Y.Z` and `Version X.Y.Z (N)`), and the version in the README's Status and
     versioning section;
   - if the release moves to another SalahKit or SalahTimes version, update that version in
     the README's Status and versioning section and in NOTICE's linked code too;
   - move the Unreleased entries of [CHANGELOG.md](CHANGELOG.md) into a new
     `## [X.Y.Z] - YYYY-MM-DD` section, and update the comparison links at the bottom.
2. **Merge it, and wait for CI to pass** on the commit you'll tag. CI only builds the UI and
   real-app tests, so run them locally with your team.
3. **Tag that commit** and push the tag:

   ```sh
   git tag -a X.Y.Z -m "Salah X.Y.Z"
   git push origin X.Y.Z
   ```

   Never move or delete a tag; a mistake is fixed with a new release.
4. **Publish a GitHub release** for the tag, with three headings:
   - **Proven:** the gates and their evidence, such as the CI run on the tagged commit and the
     local UI and real-app test runs;
   - **Pending:** what still needs a person, a device or elapsed time, each item linked to the
     `help wanted` issue that tracks it (open one if none exists);
   - **Known limitations.**

   A check that didn't run is never listed as proven.

Releases are source only. A signed download or a Mac App Store build also needs a paid
developer team and confirmed rights to the bundled recordings (see [NOTICE](NOTICE)).
