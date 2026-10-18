# Contributing to Salah

Thanks for helping. This file covers building, testing, formatting and releasing this repo. The
org-wide code of conduct, security policy and support page live in
[salah-kit/.github](https://github.com/salah-kit/.github).

## What you need

- macOS with Xcode 27 (the app itself runs on macOS 14 or later).
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

`Salah/` holds the app, `SalahWidgetsExtension/` the extension, and `Shared/` the code both
compile: the settings the app mirrors for the widget (`SalahSettings`), what's playing
(`SalahPlayback`), Salah's prayer source, the display model the widget and the menu bar
draw from (`SalahDisplay`), the widget's timeline, and the theme and views. The two share
the App Group `group.io.github.salah-kit.Salah`. Prayer times, the schedule, widget
timelines, alerts and the UI components come from
[SalahKit](https://github.com/salah-kit/SalahKit), through its public API only.

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
the `salah://settings` link a widget tap opens, the Settings window and the About panel.
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
VO-Space as Control-Option. They skip before macOS 27, on a Mac that isn't in English, and
when VoiceOver doesn't turn on. They take about ten minutes:

```sh
xcodebuild test -project Salah.xcodeproj -scheme SalahUITests -destination 'platform=macOS' \
  -allowProvisioningUpdates -only-testing:SalahUITests/VoiceOverSpeechUITests
```

VoiceOver speaks aloud while these tests run and reads whichever app is in front, so leave
the Mac alone, with Do Not Disturb on, until they end. A test keeps only what VoiceOver
says after its own moves in the window it reads, and fails at the first move after Salah
leaves the front or that window closes; speech VoiceOver makes for another app right after
a move, such as a notification it reads out, can still be kept. Each test turns VoiceOver
off at its end, unless it was on before; if a run stops first, the next test within half an
hour turns it off, or Command-F5 does. When a test fails, Xcode keeps screenshots and a
screen recording of the whole screen in the result bundle, so share its failure message and
its "VoiceOver" attachment, not the bundle.

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

## Formatting

Code is formatted with `swift format` and the shared `.swift-format` (2-space indentation,
100 columns). CI's lint job fails on any finding.

```sh
swift format format --in-place --recursive Salah SalahWidgetsExtension Shared \
  SalahTests SalahUITests SalahRoundTripTests SalahStopHarness Scripts
swift format lint --strict --recursive Salah SalahWidgetsExtension Shared \
  SalahTests SalahUITests SalahRoundTripTests SalahStopHarness Scripts
```

## Strings and languages

User-facing text lives in String Catalogs: `Salah/Resources/Localizable.xcstrings`,
`Salah/Resources/InfoPlist.xcstrings` and `SalahWidgetsExtension/Localizable.xcstrings`.
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

`Scripts/render-app-icon.swift` draws the icon from one vector drawing and writes every
size the asset catalog needs:

```sh
swift Scripts/render-app-icon.swift Salah/Assets.xcassets/AppIcon.appiconset
```

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
