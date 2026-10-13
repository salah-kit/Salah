import Foundation
import Testing

/// One committed PNG under `GuidanceTests/Baselines/`: what is rendered, in which
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
    /// A `WidgetPreviewContainer` theme preset (the "Presets" previews).
    case theme
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
}

/// The states the widget spec's verification plan lists
/// (`Guidance/docs/superpowers/specs/2026-06-02-prayer-widget-living-schedule-design.md:318`),
/// as moments on the fixture day. The playing state is split by slot, since its
/// color follows the slot (spec section 6).
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

  /// The spec's words for the state, and where the app departs from them.
  var specName: String {
    switch self {
    case .idle: "idle/normal"
    case .imminent: "imminent (fixed 15-min red, not before Sunrise)"
    case .countUp: "Iqama count-up (green, leads 15 min, next prayer secondary)"
    case .countUpSilent:
      "count-up in silent mode (spec: muted grey; the app keeps the count-up green, badge, timer and row, while silent mode mutes the rest)"
    case .countUpImminent: "count-up overlapping an imminent next (count-up leads, next line red)"
    case .endOfDay: "end-of-day Tomorrow card"
    case .playingAdhan: "playing audio (stop control): adhan, green"
    case .playingPreReminder: "playing audio (stop control): before-reminder, orange"
    case .playingPostReminder: "playing audio (stop control): after-reminder, purple"
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
      "no published snapshot: the extension's setup entry (sample data, English in every language), at Dhuhr + 60 min"
    case .stale: "the fixture day's snapshot shown at 00:10 the next day"
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

/// The theme presets the "Presets" previews show (`GuidanceWidgetTheme.allPresets`).
nonisolated enum ThemePreset: String, Sendable, CaseIterable {
  case nocturne, dawn, oasis, ink, highContrast
}

nonisolated enum BaselineCatalog {
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
        for preset in ThemePreset.allCases {
          baselines.append(
            Baseline(
              surface: .theme, state: preset.rawValue, family: .medium, language: language,
              appearance: appearance))
        }
      }
    }
    return baselines
  }()
}
