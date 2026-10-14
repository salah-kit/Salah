import Foundation
import SalahCore
import SalahWidgets

/// What the app is playing for a prayer: its adhan, du'a or reminder. The widget shows it
/// as the Stop control; the menu bar as the stop card and the playing prayer's row.
///
/// The app saves it with `SharedValue.playback` when playback starts and saves `nil`
/// when it stops or quits. The widget's Stop button clears it and posts
/// `DarwinSignal.stopAudio`; the running app stops on the signal, not on the stored
/// value, which can reach it later than the signal does, and then saves what's playing
/// again to confirm. An app that crashes saves nothing, so the widget shows the Stop
/// control only while the sound can still be playing (`mayBePlaying(at:)`).
nonisolated struct SalahPlayback: Codable, Equatable, Sendable {
  /// Which alert the sound belongs to.
  enum Slot: String, Codable, Equatable, Sendable {
    case alert
    case preReminder
    case postReminder
  }

  /// The prayer the sound is for.
  var event: PrayerEvent
  /// Which of the prayer's alerts is sounding.
  var slot: Slot
  /// Whether it's the du'a that follows an adhan, rather than the alert's own sound.
  var isDua: Bool
  /// The reminder's offset in minutes, for a reminder.
  var offsetMinutes: Int?

  init(event: PrayerEvent, slot: Slot, isDua: Bool = false, offsetMinutes: Int? = nil) {
    self.event = event
    self.slot = slot
    self.isDua = isDua
    self.offsetMinutes = offsetMinutes
  }

  /// How long after its alert's time a sound is taken to play at most: an adhan caught up
  /// a few minutes late, then the du'a.
  static let longestPlay: TimeInterval = 30 * 60

  /// When the alert sounded: the prayer's time, moved by a reminder's offset.
  var alertDate: Date {
    let offset = TimeInterval((offsetMinutes ?? 0) * 60)
    switch slot {
    case .alert: return event.time
    case .preReminder: return event.time.addingTimeInterval(-offset)
    case .postReminder: return event.time.addingTimeInterval(offset)
    }
  }

  /// Whether the sound can still be playing at `date`.
  func mayBePlaying(at date: Date) -> Bool {
    date < alertDate.addingTimeInterval(Self.longestPlay)
  }

  /// The tone the playing state draws in.
  var tone: SalahWidgetTone {
    switch slot {
    case .alert: .playingPrayerAudio
    case .preReminder: .playingPreReminderAudio
    case .postReminder: .playingPostReminderAudio
    }
  }
}

nonisolated extension SharedValue where Value == SalahPlayback {
  /// What's playing, in Salah's App Group: written by the app, cleared by the widget's
  /// Stop button.
  static var playback: Self {
    SharedValue(appGroup: SalahWidgetConstants.appGroupID, key: SalahWidgetConstants.playbackKey)
  }
}

#if canImport(notify)
  nonisolated extension DarwinSignal {
    /// The widget's Stop button tells the running app to stop playing. A running app
    /// only: the signal can't launch the app, and playback needs the app running anyway.
    static var stopAudio: Self { DarwinSignal(name: SalahWidgetConstants.stopAudioSignal) }
  }
#endif
