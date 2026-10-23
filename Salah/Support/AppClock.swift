import Foundation

/// The moment Salah's window and dropdown show: now, or in Debug builds the moment a launch
/// asks for with `-salah.debug.now`, running on from there, so a screen can be compared
/// with a design at the design's time. The alerts, the widget extension and the system's
/// own live timers keep the real time.
nonisolated enum AppClock {
  /// How far the shown moment sits from the real one.
  private static let offset: TimeInterval = {
    #if DEBUG
      if let start = DebugOptions.now() { return offset(showing: start, at: Date()) }
    #endif
    return 0
  }()

  /// The offset that shows `start` at the real moment `now`, in whole minutes, so each
  /// real minute starts a shown minute as it does without one: a timeline's minute entries
  /// then land on the shown minutes, as the countdowns expect.
  static func offset(showing start: Date, at now: Date) -> TimeInterval {
    func minute(_ date: Date) -> TimeInterval {
      (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
    }
    return minute(start) - minute(now)
  }

  /// Whether a launch asked for a moment other than now.
  static var isShifted: Bool { offset != 0 }

  /// The moment to show now.
  static var now: Date { Date().addingTimeInterval(offset) }

  /// The moment to show for a real `date`, such as a timeline's.
  static func shifted(_ date: Date) -> Date { date.addingTimeInterval(offset) }

  /// The real moment for a shown `date`, for the system's live timers, which count against
  /// the real clock.
  static func unshifted(_ date: Date) -> Date { date.addingTimeInterval(-offset) }
}
