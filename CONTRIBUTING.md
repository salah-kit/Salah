# Contributing to Salah

Thanks for helping. This file covers building, testing and formatting this repo. The
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
(`automationmodetool` shows whether it will). The two alert tests take about five
minutes:

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
  preferences it was launched with in a scratch suite, so this Mac's own Salah
  preferences are untouched. What remains is the App Group's mirrored settings from the
  last test launch (Makkah, that test's alerts), until Salah runs again and publishes its
  own.

The dropdown test skips when the menu bar is so full that macOS puts Salah's status
item behind the camera housing, where it can't be clicked.

### Real-app tests

`SalahRoundTripTests` runs the real, signed app and `SalahStopHarness` as separate
processes. The harness stands in for the widget extension: sandboxed in the same App
Group, it runs the Stop intent's own code and reads back what the app stored. The tests
move a prayer a minute or two ahead with Salah's own adjustments, so a real alert comes
due, then check the widget's stop round trip, the stop signal alone, an alert missed
while the app was frozen as during sleep (caught up once) and a reminder missed past its
grace (dropped), and that a changed alert setting replans. They read the app's log with
`log stream`, so they run without a host app, outside any sandbox. They take about 15
minutes:

```sh
xcodebuild test -project Salah.xcodeproj -scheme SalahRoundTripTests \
  -destination 'platform=macOS' -allowProvisioningUpdates
```

They need your team, like the UI tests, and CI only builds them. The app runs muted and
with `-salah.debug.withoutSystemPrompts` (Debug builds only), so it never asks for
notification permission or sends Music an Apple Event. Afterwards Salah keeps the
settings the last test launched it with (Makkah, every alert but one off, English), and
the App Group holds what the app last published.

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
pull request.

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
you verified. A fix comes with a test that would have caught the bug.
