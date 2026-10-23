import Foundation
import Testing

/// One committed PNG under `SalahTests/Baselines/`: what is rendered, in which
/// language and appearance. Pure data, so the catalog can feed parameterized tests
/// and the index; the render pipeline lives in `BaselineRendering.swift`.
nonisolated struct Baseline: Sendable, Hashable, Codable, CustomTestStringConvertible {
  enum Surface: String, Sendable, Codable, CaseIterable {
    /// A widget face, built by the app's real pipeline from the fixture day.
    case widget
    /// The menu-bar dropdown (`MenuDropdownContent`), same pipeline.
    case menu
    /// A `WidgetPreviewContainer` scenario (`WidgetPreviewData`).
    case preview
    /// The medium widget in each time of day, and in the neutral sky when Salah doesn't
    /// follow the time of day.
    case phase
  }

  enum Family: String, Sendable, Codable, CaseIterable { case small, medium, large }
  enum Language: String, Sendable, Codable, CaseIterable { case en, ar, fr }
  enum Appearance: String, Sendable, Codable, CaseIterable { case light, dark }

  var surface: Surface
  var state: String
  /// nil for the menu-bar dropdown.
  var family: Family?
  var language: Language
  var appearance: Appearance

  var path: String {
    "\(surface.rawValue)/\(state)-\(family?.rawValue ?? "dropdown")-\(language.rawValue)-\(appearance.rawValue).png"
  }

  var testDescription: String { path }

  /// The preferred languages of the test run that renders most images: the scheme's
  /// test arguments pin them.
  static let mainProcessLanguages = ["en-US"]

  /// The preferred languages of the process that renders this image. The menu-bar
  /// dropdown runs in the app's own process, which the app gives its chosen language
  /// (`AppLanguage.appleLanguagesOverride`), and Arabic gives text taller lines, so
  /// the Arabic dropdown renders in an Arabic process (`-testLanguage ar`). English
  /// and French render the same in their own languages as under US English. The
  /// widget extension runs in the system's languages and the previews in Xcode's, so
  /// those render as on a Mac whose languages are US English.
  var processLanguages: [String] {
    surface == .menu && language == .ar ? ["ar"] : Self.mainProcessLanguages
  }
}

/// The widget and menu states the baselines check, as moments on the fixture day. The
/// playing state is split by slot, since its color follows the slot.
/// `stale` is the face a timeline that ran out shows (`SalahWidgetEntry.Content.expired`).
nonisolated enum SpecState: String, Sendable, CaseIterable {
  case idle
  case imminent
  case countUp
  case countUpSilent
  case countUpImminent
  case endOfDay
  case playingAdhan
  case playingPreReminder
  case playingPostReminder
  case silent
  case setupNeeded
  case stale

  /// The index's description of the state.
  var specName: String {
    switch self {
    case .idle: "idle/normal"
    case .imminent: "imminent (15 min before, gold, not before Sunrise)"
    case .countUp: "Iqama count-up (the time of day's mark, leads 15 min, next prayer secondary)"
    case .countUpSilent:
      "count-up in silent mode (the count-up keeps its badge, timer and row, while silent mode mutes the rest)"
    case .countUpImminent:
      "count-up overlapping an imminent next (count-up leads, next line follows)"
    case .endOfDay: "end-of-day Tomorrow card"
    case .playingAdhan: "playing audio (stop control): adhan"
    case .playingPreReminder: "playing audio (stop control): before-reminder"
    case .playingPostReminder: "playing audio (stop control): after-reminder"
    case .silent: "silent mode"
    case .setupNeeded: "setup-needed"
    case .stale: "stale"
    }
  }

  /// How the moment and inputs are chosen, for the index.
  var setup: String {
    switch self {
    case .idle: "Dhuhr + 60 min"
    case .imminent: "Asr − 10 min"
    case .countUp: "Dhuhr + 4 min"
    case .countUpSilent: "Dhuhr + 4 min, silent mode on"
    case .countUpImminent: "Maghrib + 4 min, Isha adjusted −78 min (19:12)"
    case .endOfDay: "Isha + 60 min"
    case .playingAdhan: "Maghrib + 2 min, Maghrib's adhan playing"
    case .playingPreReminder: "Maghrib − 10 min, Maghrib's 10-min before-reminder playing"
    case .playingPostReminder: "Maghrib + 5 min, Maghrib's 5-min after-reminder playing"
    case .silent: "Dhuhr + 60 min, silent mode on"
    case .setupNeeded:
      "no settings mirrored: the extension's setup entry, in the device's language, at Dhuhr + 60 min"
    case .stale: "the expired entry of a timeline that ran out, at 00:10 the next day"
    }
  }

  /// The extension-only states have no menu-bar counterpart.
  var onMenu: Bool { self != .setupNeeded && self != .stale }

  var silentMode: Bool { self == .countUpSilent || self == .silent }
  var ishaAdjustment: Int { self == .countUpImminent ? -78 : 0 }
}

/// The `WidgetPreviewData` scenarios in `WidgetPreviewContainer.swift`.
nonisolated enum PreviewScenario: String, Sendable, CaseIterable {
  case idle, imminent, countUp, countUpEnded, since, tomorrow, silent, playing
}

nonisolated enum BaselineCatalog {
  /// The images this test process renders: those whose process languages are its own.
  static var forThisProcess: [Baseline] {
    all.filter { $0.processLanguages == Locale.preferredLanguages }
  }

  /// Why this process renders none of them.
  static var processSkipReason: Comment? {
    guard forThisProcess.isEmpty else { return nil }
    return Comment(
      rawValue:
        "this process prefers \(Locale.preferredLanguages); baselines render in a process preferring [\"en-US\"] (the scheme's test arguments) or [\"ar\"] (-testLanguage ar)"
    )
  }

  static let all: [Baseline] = {
    var baselines: [Baseline] = []
    for language in Baseline.Language.allCases {
      for appearance in Baseline.Appearance.allCases {
        for state in SpecState.allCases {
          for family in Baseline.Family.allCases {
            baselines.append(
              Baseline(
                surface: .widget, state: state.rawValue, family: family, language: language,
                appearance: appearance))
          }
          if state.onMenu {
            baselines.append(
              Baseline(
                surface: .menu, state: state.rawValue, family: nil, language: language,
                appearance: appearance))
          }
        }
        for scenario in PreviewScenario.allCases {
          for family in Baseline.Family.allCases {
            baselines.append(
              Baseline(
                surface: .preview, state: scenario.rawValue, family: family, language: language,
                appearance: appearance))
          }
        }
        for phase in SalahPhase.allCases {
          baselines.append(
            Baseline(
              surface: .phase, state: phase.rawValue, family: .medium, language: language,
              appearance: appearance))
        }
      }
    }
    return baselines
  }()
}
