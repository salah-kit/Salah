import SwiftUI

/// A pane of Salah's window, in sidebar order: Today, then the settings.
enum WindowPane: String, CaseIterable, Identifiable {
  case today, general, location, calculation, adjustments, notifications, appearance

  var id: String { rawValue }

  /// The panes under the sidebar's Settings header.
  static let settings: [WindowPane] = allCases.filter { $0 != .today }

  /// The catalog key of the pane's name, for the sidebar and the window's title.
  var titleKey: String {
    switch self {
    case .today: "window.today"
    case .general: "settings.tab.general"
    case .location: "settings.tab.location"
    case .calculation: "settings.tab.calculation"
    case .adjustments: "settings.tab.adjustments"
    case .notifications: "settings.tab.notifications"
    case .appearance: "settings.tab.appearance"
    }
  }

  var icon: String {
    switch self {
    case .today: "sun.horizon.fill"
    case .general: "gearshape"
    case .location: "location.fill"
    case .calculation: "function"
    case .adjustments: "slider.horizontal.3"
    case .notifications: "bell.fill"
    case .appearance: "paintpalette.fill"
    }
  }
}

/// The pane the window shows. It outlives the window, so Open Salah shows Today the first
/// time and the last pane after that.
@Observable
final class WindowNavigation {
  var pane: WindowPane = .today
}
