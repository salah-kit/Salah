import Foundation
import SalahCore

extension SalahPlayback {
  /// What the prayer-alert controller's state shows the widget: an alert's sound or the
  /// du'a after it. Nothing for idle, or for a sound previewed in Settings.
  init?(_ state: AudioPlaybackState) {
    guard case .playing(let context) = state,
      context.source == .prayerAlert || context.source == .dua,
      let event = context.event, let slot = context.slot
    else { return nil }
    self.init(
      event: event, slot: Slot(slot), isDua: context.source == .dua,
      offsetMinutes: context.prayerAlertOffsetMinutes)
  }
}

extension SalahPlayback.Slot {
  init(_ slot: PrayerNotificationSoundSlot) {
    switch slot {
    case .alert: self = .alert
    case .preReminder: self = .preReminder
    case .postReminder: self = .postReminder
    }
  }
}
