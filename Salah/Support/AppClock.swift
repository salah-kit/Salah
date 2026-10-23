import Foundation

/// The moment Salah's surfaces show: now, or in Debug builds the moment a launch asks for
/// with `-salah.debug.now`, running on from there, so a screen can be shown at a given time.
/// Only what Salah displays reads it; the alerts keep the real time.
nonisolated enum AppClock {
  /// How far the shown moment sits from the real one.
  private static let offset: TimeInterval = {
    #if DEBUG
      if let start = DebugOptions.now() { return start.timeIntervalSinceNow }
    #endif
    return 0
  }()

  /// The moment to show now.
  static var now: Date { Date().addingTimeInterval(offset) }

  /// The moment to show for a real `date`, such as a timeline's.
  static func shifted(_ date: Date) -> Date { date.addingTimeInterval(offset) }
}
