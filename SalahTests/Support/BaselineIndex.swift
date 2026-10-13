import Adhan
import Foundation

/// Generates `Baselines/README.md` and `Baselines/index.json` from the catalog, so
/// the index always matches the images. Record mode writes them; compare mode checks
/// the committed copies.
enum BaselineIndex {
  struct Entry: Codable, Equatable {
    var path: String
    var surface: String
    var state: String
    var family: String?
    var language: String
    var appearance: String
    /// The preferred languages of the process that renders it.
    var processLanguages: [String]
    /// The rendered moment, in the fixture's zone.
    var moment: String
    var setup: String
  }

  struct Document: Codable, Equatable {
    var schemaVersion = 2
    var renderer = "SwiftUI ImageRenderer, scale \(BaselineRenderer.scale), PNG"
    var timeZone = "Asia/Riyadh"
    var fixture =
      "Makkah (21.4167, 39.8167), Umm al-Qura, Shafi, middle of the night; Fajr 30-min before-reminder; Maghrib 10-min before and 5-min after reminders"
    var rerender = BaselineIndex.rerenderCommands
    var baselines: [Entry]
  }

  /// The main run, then the Arabic menu's run in an Arabic process.
  static let rerenderCommands = [
    "TEST_RUNNER_SALAH_RECORD_BASELINES=1 xcodebuild test -project Salah.xcodeproj -scheme Salah -destination 'platform=macOS' -only-testing:SalahTests/VisualBaselineTests CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=",
    "TEST_RUNNER_SALAH_RECORD_BASELINES=1 xcodebuild test -project Salah.xcodeproj -scheme Salah -destination 'platform=macOS' -only-testing:SalahTests/VisualBaselineTests -testLanguage ar CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=",
  ]

  static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = Fixture.timeZone
    return formatter.string(from: date)
  }

  static func clock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = Fixture.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
  }

  static func entry(_ baseline: Baseline) -> Entry {
    let moment: Date
    let setup: String
    switch baseline.surface {
    case .widget, .menu:
      let state = SpecState(rawValue: baseline.state)!
      moment = BaselinePipeline.moment(for: state)
      setup = state.setup
    case .preview:
      moment = BaselinePipeline.previewNow
      setup = "WidgetPreviewData.\(baseline.state)"
    case .theme:
      moment = BaselinePipeline.previewNow
      setup = "WidgetPreviewData.idle with the \(baseline.state) theme"
    }
    return Entry(
      path: baseline.path, surface: baseline.surface.rawValue, state: baseline.state,
      family: baseline.family?.rawValue, language: baseline.language.rawValue,
      appearance: baseline.appearance.rawValue, processLanguages: baseline.processLanguages,
      moment: timestamp(moment), setup: setup)
  }

  static func json() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(Document(baselines: BaselineCatalog.all.map(entry)))
    data.append(0x0A)
    return data
  }

  static var previewDescriptions: [PreviewScenario: String] {
    [
      .idle:
        "A normal day; the next prayer, Maghrib, is 2 h 42 min away and carries both reminders.",
      .imminent: "10 minutes before Maghrib: imminent red.",
      .countUp: "4 minutes after Dhuhr: the green count-up leads; Asr is the secondary next.",
      .countUpEnded: "16 minutes after Dhuhr: the count-up has ended; back to Asr's countdown.",
      .since: "90 minutes after Dhuhr: the resting countdown to Asr with the “since” treatment.",
      .tomorrow: "After Isha: the focus is tomorrow's Fajr.",
      .silent: "The normal day in silent mode.",
      .playing: "Maghrib's adhan playing: the whole widget is the stop control.",
    ]
  }

  static func readme() -> String {
    var lines: [String] = []
    func add(_ text: String = "") { lines.append(text) }

    add("# Visual baselines")
    add()
    add(
      "PNG renders of the app's widget faces and menu-bar dropdown, made by `VisualBaselineTests` in SalahTests. A2 first recorded them from the imported Guidance app (`4bc00e9` plus test seams), before the rebrand; the folder's `git log` shows every later re-record. B2 re-recorded them after the rebrand: only the 36 setup and stale widget faces changed, the two whose message names the app. D1 re-renders them after the move onto SalahKit and diffs its renders against these files. This index is generated with the images by the same test: don't edit it by hand."
    )
    add()
    add("## Re-render or check")
    add()
    add("From the repository root, both commands:")
    add()
    add("```sh")
    for command in rerenderCommands { add(command) }
    add("```")
    add()
    add(
      "The first renders every image but the Arabic menu dropdown; the second, whose `-testLanguage ar` replaces the scheme's language pin, renders only the Arabic dropdown (below). In the salah-kit workspace, run them through `orchestration/heavy.sh` and add `-derivedDataPath .derived`. Without the `TEST_RUNNER_SALAH_RECORD_BASELINES=1` prefix the same commands compare every render with its PNG, fail on any difference and leave the new render in `.baseline-failures/`. After a re-render, `git status SalahTests/Baselines` lists what changed."
    )
    add()
    add("## How they're rendered")
    add()
    add(
      "- SwiftUI `ImageRenderer` at scale \(BaselineRenderer.scale) (one pixel per point), written as PNG. Each image is the render that repeats: the first render of a face in a process can differ slightly while glyphs are first rasterized."
    )
    add(
      "- Each state at a fixed moment (below), with the process in the Asia/Riyadh time zone and the language set through the app's own language preference (English, Arabic, French). The setup face has no snapshot to take a language from: the extension shows it in English whatever the language."
    )
    add(
      "- Each image renders in a process with fixed preferred languages, because with a tall script such as Arabic among them macOS gives system-font text taller lines in every language. The main run prefers US English only (the scheme's test arguments pass `-AppleLanguages (en-US)`; `environment.json` records the list): the widget faces as the extension shows them on a Mac whose languages are English, and the previews. The menu-bar dropdown runs in the app's own process, which the app gives its chosen language, so the Arabic dropdown renders in a second run preferring Arabic (`-testLanguage ar`); English and French render the same in their own languages as under US English. `index.json` lists each image's process languages."
    )
    add(
      "- Light and dark through the `colorScheme` environment; the default Nocturne theme follows it."
    )
    add(
      "- Accessibility settings at the macOS defaults, as on the hosted runners: Reduce Motion and Reduce Transparency off. The views read both (`MenuHeroCard` drops the imminent face's breathing border under Reduce Motion, `SalahWidgetBackground` its glows under Reduce Transparency), and a render can't override them, so record with both off."
    )
    add(
      "- Widget faces render in `WidgetPreviewContainer`, the app's reproduction of the macOS widget container (158×158, 338×158 and 338×354 points). The setup and stale faces mirror the extension shell's first two branches in that same container (`WidgetShellMessage` in the tests), since WidgetKit's container renders only in a widget host."
    )
    add("- The menu-bar dropdown is `MenuDropdownContent`, 300 points wide.")
    add(
      "- Compared pixel by pixel. A channel difference of up to \(PixelComparison.noiseFloor)/255 counts as equal, and up to \(PixelComparison.allowedOutliers) pixels per image may differ by more, none of them by more than \(PixelComparison.jitterCeiling)/255: antialiasing can shift a pixel or two by a few levels between processes, while a changed digit, glyph, diacritic, icon or color moves pixels far more. Recording keeps a PNG that still matches, so a re-render only rewrites real changes. Comparisons run only on the macOS major version in `environment.json`, because fonts and text rendering change between releases."
    )
    add()
    add("## Fixture")
    add()
    add(
      "The app's default settings: Makkah (21.4167, 39.8167), Asia/Riyadh, Umm al-Qura, Shafi, middle of the night, the Nocturne theme. Fajr has a 30-minute before-reminder, and Maghrib a 10-minute before and a 5-minute after reminder. The day is Tuesday 2 June 2026 (16 Dhuʻl-Hijjah 1447). Adhan 1.4.0 gives:"
    )
    add()
    add("| Day | Fajr | Sunrise | Dhuhr | Asr | Maghrib | Isha |")
    add("|---|---|---|---|---|---|---|")
    for offset in 0...1 {
      let times = Fixture.prayerTimes(dayOffset: offset)
      let row = [times.fajr, times.sunrise, times.dhuhr, times.asr, times.maghrib, times.isha]
        .map { String(clock($0).suffix(5)) }
      add("| \(clock(times.dhuhr).prefix(10)) | \(row.joined(separator: " | ")) |")
    }
    add()
    add("## Spec states: `widget/` and `menu/`")
    add()
    add(
      "The states the widget spec's verification plan lists (`Guidance/docs/superpowers/specs/2026-06-02-prayer-widget-living-schedule-design.md:318`), built by the app's real snapshot builder from the fixture. The images show what the app renders; where that departs from the spec (silent count-up, setup face), the table says so. Files are `widget/<state>-<small|medium|large>-<en|ar|fr>-<light|dark>.png` and `menu/<state>-dropdown-<en|ar|fr>-<light|dark>.png`; the setup and stale states exist only in the widget."
    )
    add()
    add("| State | Spec | Moment (Riyadh) | Setup |")
    add("|---|---|---|---|")
    for state in SpecState.allCases {
      add(
        "| `\(state.rawValue)` | \(state.specName) | \(clock(BaselinePipeline.moment(for: state))) | \(state.setup) |"
      )
    }
    add()
    add("## `WidgetPreviewContainer` scenarios: `preview/` and `theme/`")
    add()
    add(
      "The `WidgetPreviewData` scenarios behind the widget's Xcode previews (`Salah/Features/Widgets/WidgetPreviewContainer.swift`), with their clock fixed at \(clock(BaselinePipeline.previewNow)). They place prayers at minute offsets from that clock and use the previews' hand-written names, which differ from the app's catalog (French Sunrise is “Lever”). Files are `preview/<scenario>-<family>-<language>-<appearance>.png`, and the theme presets at medium size, as their previews show them, are `theme/<preset>-medium-<language>-<appearance>.png`."
    )
    add()
    add("| Scenario | Shows |")
    add("|---|---|")
    for scenario in PreviewScenario.allCases {
      add("| `\(scenario.rawValue)` | \(previewDescriptions[scenario]!) |")
    }
    add()
    add(
      "Theme presets: \(ThemePreset.allCases.map { "`\($0.rawValue)`" }.joined(separator: ", ")).")
    add()
    add("## Count")
    add()
    let all = BaselineCatalog.all
    for surface in Baseline.Surface.allCases {
      add("- `\(surface.rawValue)/`: \(all.filter { $0.surface == surface }.count) images")
    }
    add(
      "- total: \(all.count) images, \(all.filter { $0.processLanguages != Baseline.mainProcessLanguages }.count) of them from the Arabic run; `index.json` lists each with its inputs."
    )
    return lines.joined(separator: "\n") + "\n"
  }
}
