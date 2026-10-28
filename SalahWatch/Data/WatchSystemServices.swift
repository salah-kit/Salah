import Foundation
import SalahWidgets
@preconcurrency import UserNotifications

/// Publishes the settings the complications read: the mirror of the preferences, in the
/// watch's own App Group, which the complications' timelines are calculated from.
@MainActor
struct WatchComplicationPublisher {
  var value: SharedValue<SalahSettings> = .settings

  /// Saves the mirror and reloads the complications when it changed. Before the iPhone sends
  /// any preferences there's no mirror, and the complications ask for the iPhone.
  @discardableResult
  func publish(_ settings: SalahSettings?) throws -> Bool {
    try value.save(settings, reloading: [WatchComplicationKind.prayer])
  }
}

/// The iPhone's alerts reach the watch on their own, and the watch schedules none of its own.
/// When one arrives while Salah is the frontmost app, watchOS asks Salah how to present it:
/// as anywhere else, unless the watch is already playing that prayer's adhan.
final class WatchNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
  /// Whether an adhan plays now, read on the main actor.
  private let isPlaying: @MainActor () -> Bool

  init(isPlaying: @escaping @MainActor () -> Bool) {
    self.isPlaying = isPlaying
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    await MainActor.run { isPlaying() } ? [.list] : [.banner, .list, .sound]
  }
}
