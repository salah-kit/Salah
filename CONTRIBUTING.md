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
| `SalahTests` | Unit, characterization and visual-baseline tests |

`Salah/` holds the app, `SalahWidgetsExtension/` the extension, and `Shared/` the code both
compile (the widget's snapshot model, store, theme and views). The two share the App Group
`group.io.github.salah-kit.Salah`.

## Signing

No signing team is committed. `Config/Shared.xcconfig` includes your own
`Config/Local.xcconfig`, which git ignores:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
# then set DEVELOPMENT_TEAM = <your team ID> in Config/Local.xcconfig
```

With a team, Xcode signs automatically; add `-allowProvisioningUpdates` to command-line
builds so it can register the bundle identifiers and the App Group. The app needs a team
to run with its App Group: macOS asks before an app signed without one reads the shared
container.

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
swift format format --in-place --recursive Salah SalahWidgetsExtension Shared SalahTests Scripts
swift format lint --strict --recursive Salah SalahWidgetsExtension Shared SalahTests Scripts
```

## Strings and languages

User-facing text lives in String Catalogs: `Salah/Resources/Localizable.xcstrings`,
`Salah/Resources/InfoPlist.xcstrings` and `SalahWidgetsExtension/Localizable.xcstrings`.
The widget's own labels are in `SalahWidgetLabels` (`Shared/SalahWidgetModels.swift`),
because the extension reads them from the app's snapshot. Every change needs all nine
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
