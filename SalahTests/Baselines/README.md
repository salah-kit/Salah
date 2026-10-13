# Visual baselines

PNG renders of the app's widget faces and menu-bar dropdown, made by `VisualBaselineTests` in SalahTests. A2 first recorded them from the imported Guidance app (`4bc00e9` plus test seams), before the rebrand; the folder's `git log` shows every later re-record. B2 re-renders them after the rebrand and D1 after the move onto SalahKit; each diffs its renders against these files. This index is generated with the images by the same test: don't edit it by hand.

## Re-render or check

From the repository root, both commands:

```sh
TEST_RUNNER_SALAH_RECORD_BASELINES=1 xcodebuild test -project Salah.xcodeproj -scheme Salah -destination 'platform=macOS' -only-testing:SalahTests/VisualBaselineTests CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
TEST_RUNNER_SALAH_RECORD_BASELINES=1 xcodebuild test -project Salah.xcodeproj -scheme Salah -destination 'platform=macOS' -only-testing:SalahTests/VisualBaselineTests -testLanguage ar CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

The first renders every image but the Arabic menu dropdown; the second, whose `-testLanguage ar` replaces the scheme's language pin, renders only the Arabic dropdown (below). In the salah-kit workspace, run them through `orchestration/heavy.sh` and add `-derivedDataPath .derived`. Without the `TEST_RUNNER_SALAH_RECORD_BASELINES=1` prefix the same commands compare every render with its PNG, fail on any difference and leave the new render in `.baseline-failures/`. After a re-render, `git status SalahTests/Baselines` lists what changed.

## How they're rendered

- SwiftUI `ImageRenderer` at scale 1 (one pixel per point), written as PNG. Each image is the render that repeats: the first render of a face in a process can differ slightly while glyphs are first rasterized.
- Each state at a fixed moment (below), with the process in the Asia/Riyadh time zone and the language set through the app's own language preference (English, Arabic, French). The setup face has no snapshot to take a language from: the extension shows it in English whatever the language.
- Each image renders in a process with fixed preferred languages, because with a tall script such as Arabic among them macOS gives system-font text taller lines in every language. The main run prefers US English only (the scheme's test arguments pass `-AppleLanguages (en-US)`; `environment.json` records the list): the widget faces as the extension shows them on a Mac whose languages are English, and the previews. The menu-bar dropdown runs in the app's own process, which the app gives its chosen language, so the Arabic dropdown renders in a second run preferring Arabic (`-testLanguage ar`); English and French render the same in their own languages as under US English. `index.json` lists each image's process languages.
- Light and dark through the `colorScheme` environment; the default Nocturne theme follows it.
- Accessibility settings at the macOS defaults, as on the hosted runners: Reduce Motion and Reduce Transparency off. The views read both (`MenuHeroCard` drops the imminent face's breathing border under Reduce Motion, `SalahWidgetBackground` its glows under Reduce Transparency), and a render can't override them, so record with both off.
- Widget faces render in `WidgetPreviewContainer`, the app's reproduction of the macOS widget container (158×158, 338×158 and 338×354 points). The setup and stale faces mirror the extension shell's first two branches in that same container (`WidgetShellMessage` in the tests), since WidgetKit's container renders only in a widget host.
- The menu-bar dropdown is `MenuDropdownContent`, 300 points wide.
- Compared pixel by pixel. A channel difference of up to 2/255 counts as equal, and up to 16 pixels per image may differ by more, none of them by more than 32/255: antialiasing can shift a pixel or two by a few levels between processes, while a changed digit, glyph, diacritic, icon or color moves pixels far more. Recording keeps a PNG that still matches, so a re-render only rewrites real changes. Comparisons run only on the macOS major version in `environment.json`, because fonts and text rendering change between releases.

## Fixture

The app's default settings: Makkah (21.4167, 39.8167), Asia/Riyadh, Umm al-Qura, Shafi, middle of the night, the Nocturne theme. Fajr has a 30-minute before-reminder, and Maghrib a 10-minute before and a 5-minute after reminder. The day is Tuesday 2 June 2026 (16 Dhuʻl-Hijjah 1447). Adhan 1.4.0 gives:

| Day | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha |
|---|---|---|---|---|---|---|
| 2026-06-02 | 04:11 | 05:38 | 12:19 | 15:35 | 19:00 | 20:30 |
| 2026-06-03 | 04:11 | 05:38 | 12:19 | 15:36 | 19:00 | 20:30 |

## Spec states: `widget/` and `menu/`

The states the widget spec's verification plan lists (`Guidance/docs/superpowers/specs/2026-06-02-prayer-widget-living-schedule-design.md:318`), built by the app's real snapshot builder from the fixture. The images show what the app renders; where that departs from the spec (silent count-up, setup face), the table says so. Files are `widget/<state>-<small|medium|large>-<en|ar|fr>-<light|dark>.png` and `menu/<state>-dropdown-<en|ar|fr>-<light|dark>.png`; the setup and stale states exist only in the widget.

| State | Spec | Moment (Riyadh) | Setup |
|---|---|---|---|
| `idle` | idle/normal | 2026-06-02 13:19 | Dhuhr + 60 min |
| `imminent` | imminent (fixed 15-min red, not before Sunrise) | 2026-06-02 15:25 | Asr − 10 min |
| `countUp` | Iqama count-up (green, leads 15 min, next prayer secondary) | 2026-06-02 12:23 | Dhuhr + 4 min |
| `countUpSilent` | count-up in silent mode (spec: muted grey; the app keeps the count-up green, badge, timer and row, while silent mode mutes the rest) | 2026-06-02 12:23 | Dhuhr + 4 min, silent mode on |
| `countUpImminent` | count-up overlapping an imminent next (count-up leads, next line red) | 2026-06-02 19:04 | Maghrib + 4 min, Isha adjusted −78 min (19:12) |
| `endOfDay` | end-of-day Tomorrow card | 2026-06-02 21:30 | Isha + 60 min |
| `playingAdhan` | playing audio (stop control): adhan, green | 2026-06-02 19:02 | Maghrib + 2 min, Maghrib's adhan playing |
| `playingPreReminder` | playing audio (stop control): before-reminder, orange | 2026-06-02 18:50 | Maghrib − 10 min, Maghrib's 10-min before-reminder playing |
| `playingPostReminder` | playing audio (stop control): after-reminder, purple | 2026-06-02 19:05 | Maghrib + 5 min, Maghrib's 5-min after-reminder playing |
| `silent` | silent mode | 2026-06-02 13:19 | Dhuhr + 60 min, silent mode on |
| `setupNeeded` | setup-needed | 2026-06-02 13:19 | no published snapshot: the extension's setup entry (sample data, English in every language), at Dhuhr + 60 min |
| `stale` | stale | 2026-06-03 00:10 | the fixture day's snapshot shown at 00:10 the next day |

## `WidgetPreviewContainer` scenarios: `preview/` and `theme/`

The `WidgetPreviewData` scenarios behind the widget's Xcode previews (`Salah/Features/Widgets/WidgetPreviewContainer.swift`), with their clock fixed at 2026-06-02 16:00. They place prayers at minute offsets from that clock and use the previews' hand-written names, which differ from the app's catalog (French Sunrise is “Lever”). Files are `preview/<scenario>-<family>-<language>-<appearance>.png`, and the theme presets at medium size, as their previews show them, are `theme/<preset>-medium-<language>-<appearance>.png`.

| Scenario | Shows |
|---|---|
| `idle` | A normal day; the next prayer, Maghrib, is 2 h 42 min away and carries both reminders. |
| `imminent` | 10 minutes before Maghrib: imminent red. |
| `countUp` | 4 minutes after Dhuhr: the green count-up leads; Asr is the secondary next. |
| `countUpEnded` | 16 minutes after Dhuhr: the count-up has ended; back to Asr's countdown. |
| `since` | 90 minutes after Dhuhr: the resting countdown to Asr with the “since” treatment. |
| `tomorrow` | After Isha: the focus is tomorrow's Fajr. |
| `silent` | The normal day in silent mode. |
| `playing` | Maghrib's adhan playing: the whole widget is the stop control. |

Theme presets: `nocturne`, `dawn`, `oasis`, `ink`, `highContrast`.

## Count

- `widget/`: 216 images
- `menu/`: 60 images
- `preview/`: 144 images
- `theme/`: 30 images
- total: 450 images, 20 of them from the Arabic run; `index.json` lists each with its inputs.
