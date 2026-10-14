import Foundation
import SalahCore

/// The menu bar's clock and duration text, in the app's language and the location's
/// time zone. It's `SalahText` in the app's locale, so the menu bar and every widget
/// size render identically.
struct PrayerDisplayFormatter {
  var timeZone: TimeZone

  init(timeZone: TimeZone) {
    self.timeZone = timeZone
  }

  private var text: SalahText { SalahText(locale: .app, timeZone: timeZone) }

  /// Time remaining until a prayer, for the menu bar ("45s" / "49m" / "2:49").
  func countdown(from startDate: Date, to endDate: Date) -> String {
    text.duration(endDate.timeIntervalSince(startDate), direction: .remaining, bidiIsolated: true)
  }

  /// Elapsed time since a prayer started, for the menu-bar Iqama count-up
  /// ("+45s" / "+12m" / "+2:49").
  func countUp(from startDate: Date, to endDate: Date) -> String {
    text.duration(endDate.timeIntervalSince(startDate), direction: .elapsed, bidiIsolated: true)
  }

  func compactTime(for date: Date) -> String {
    text.compactTime(date)
  }

  func fullTime(for date: Date) -> String {
    text.timeFormatter().string(from: date).bidiIsolated
  }
}
