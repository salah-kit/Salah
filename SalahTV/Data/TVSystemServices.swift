import Foundation
import SalahCore
import SalahWidgets
import TVServices
import UIKit

/// Keeps the screen on. Apple asks apps to do it only while they must, so Salah does while
/// the room display or the adhan is showing.
@MainActor
protocol TVIdleTimerControlling: AnyObject {
  var keepsScreenOn: Bool { get set }
}

@MainActor
final class TVApplicationIdleTimer: TVIdleTimerControlling {
  var keepsScreenOn: Bool {
    get { UIApplication.shared.isIdleTimerDisabled }
    set { UIApplication.shared.isIdleTimerDisabled = newValue }
  }
}

/// Mirrors the settings into the App Group for the Top Shelf extension, and asks the system
/// for new Top Shelf images when what they show changes.
@MainActor
final class TVTopShelfPublisher {
  private let settings: SharedValue<SalahSettings>
  private let reload: @MainActor () -> Void
  /// The next prayer, the day and the time of day the banners last showed.
  private var lastShown: Shown?

  private nonisolated struct Shown: Equatable {
    var nextPrayer: String?
    var day: CivilDay?
    var phase: SalahPhase?
  }

  init(
    settings: SharedValue<SalahSettings> = .settings,
    reload: @escaping @MainActor () -> Void = {
      TVTopShelfContentProvider.topShelfContentDidChange()
    }
  ) {
    self.settings = settings
    self.reload = reload
  }

  /// Saves the mirror and reloads the Top Shelf when the settings, the next prayer, the day
  /// or the time of day changed: at midnight the Today banner and the dates change while the
  /// next prayer, tomorrow's Fajr, doesn't, and at sunrise the sky does. Returns whether it
  /// asked for a reload.
  @discardableResult
  func publish(
    _ value: SalahSettings?, nextPrayer: String?, day: CivilDay?, phase: SalahPhase?
  ) throws -> Bool {
    let changed = try settings.save(value)
    let shown = Shown(nextPrayer: nextPrayer, day: day, phase: phase)
    guard changed || shown != lastShown else { return false }
    lastShown = shown
    reload()
    return true
  }
}
