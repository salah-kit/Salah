import Foundation
import Observation

/// The app's pages, top to bottom; the Digital Crown moves between them.
nonisolated enum WatchTab: String, CaseIterable, Hashable, Sendable {
  /// The next prayer and the rest of its day.
  case now
  /// Today's prayers.
  case today
  case qibla
}

/// Which page shows. The adhan always shows on the first.
@MainActor @Observable
final class WatchNavigation {
  var tab: WatchTab

  init(tab: WatchTab = .now) { self.tab = tab }

  /// Opens a page from a link such as `salah://today`, which the complications use.
  func open(_ url: URL) {
    guard url.scheme?.lowercased() == "salah",
      let tab = (url.host ?? url.path).lowercased().trimmingCharacters(
        in: CharacterSet(charactersIn: "/")
      ).nonEmpty.flatMap(WatchTab.init(rawValue:))
    else { return }
    self.tab = tab
  }
}

nonisolated extension String {
  fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
