import ActivityKit
import Foundation
import SalahCore
import SalahUI

/// The single prayer a Live Activity follows. Values stay independent of the app process.
nonisolated struct SalahActivityAttributes: ActivityAttributes, Sendable {
  struct ContentState: Codable, Hashable, Sendable {
    enum Mode: String, Codable, Sendable { case countdown, justStarted, playing }

    var mode: Mode
    var prayerKind: PrayerKind
    var prayerObservance: PrayerObservance
    var prayerName: String
    var prayerTime: Date
    var updatedAt: Date
    var validUntil: Date
    var progressStart: Date
    var progressEnd: Date
    var eyebrow: String
    var prayerTimeText: String
    var place: String
    var languageIdentifier: String
    var timeZoneIdentifier: String
    var phase: SalahPhase
    var muteSounds: Bool
    var nextPrayerName: String?
    var nextPrayerTime: String?

    var isRightToLeft: Bool {
      Locale(identifier: languageIdentifier).language.characterDirection == .rightToLeft
    }

    /// At a validity boundary the surface asks for an update instead of counting indefinitely.
    func isValid(at date: Date) -> Bool { date < validUntil }

    /// A snapshot's progress. Live rendering uses the bounded dates to advance without app wakes.
    func progress(at date: Date) -> Double {
      let duration = progressEnd.timeIntervalSince(progressStart)
      guard duration > 0 else { return 0 }
      return min(1, max(0, date.timeIntervalSince(progressStart) / duration))
    }

    /// Manual playback may happen hours after the prayer; elapsed audio starts at Play.
    var timerStart: Date { mode == .playing ? progressStart : prayerTime }

    var timerInterval: ClosedRange<Date> {
      if mode == .countdown { return updatedAt...max(updatedAt, prayerTime) }
      return timerStart...max(timerStart, validUntil)
    }

    func timerSeconds(at date: Date) -> TimeInterval {
      max(
        0,
        mode == .countdown ? prayerTime.timeIntervalSince(date) : date.timeIntervalSince(timerStart)
      )
    }

    func clockValue(at date: Date) -> String {
      Duration.seconds(timerSeconds(at: date).rounded(.down)).formatted(
        .time(pattern: .hourMinuteSecond(padHourToLength: 1))
          .locale(Locale(identifier: languageIdentifier)))
    }

    func spokenLabel(at date: Date) -> String {
      let duration = PrayerDurationFormat.string(
        timerSeconds(at: date), direction: mode == .countdown ? .remaining : .elapsed,
        width: .spoken, locale: Locale(identifier: languageIdentifier))
      return "\(prayerName), \(eyebrow), \(duration)"
    }

    /// A Live Activity never infers playback from a notification or a prayer's start.
    init?(display: SalahDisplay, playbackSession: IOSPlaybackSession? = nil) {
      let playback = playbackSession?.playing(at: display.date)
      guard let event = playback?.event ?? display.focus?.event, event.kind != .sunrise else {
        return nil
      }
      mode =
        playback != nil ? .playing : display.focus?.isCountUp == true ? .justStarted : .countdown
      prayerKind = event.kind
      prayerObservance = event.observance
      prayerName = display.name(of: event)
      prayerTime = event.time
      updatedAt = display.date
      phase = display.phase
      muteSounds = display.settings.silentMode
      place = display.header.location
      languageIdentifier = display.locale.identifier
      timeZoneIdentifier = display.settings.location.timeZone.identifier
      prayerTimeText = display.timeText(of: event)
      nextPrayerName = display.prayerState?.nextPrayer.map { display.name(of: $0) }
      nextPrayerTime = display.prayerState?.nextPrayer.map { display.timeText(of: $0) }
      switch mode {
      case .playing:
        if let playback {
          if playback.isDua {
            eyebrow = display.labels.playingDua
          } else {
            switch playback.slot {
            case .alert: eyebrow = display.labels.playingAdhan
            case .preReminder: eyebrow = display.labels.playingPreReminder
            case .postReminder: eyebrow = display.labels.playingPostReminder
            }
          }
          if playback.slot != .alert, let offset = playback.offsetMinutes {
            prayerTimeText = display.text.offsetPhrase(
              offset, before: playback.slot == .preReminder)
          }
        } else {
          eyebrow = display.labels.playingAdhan
        }
        validUntil = playbackSession?.expiresAt ?? display.date
        progressStart = playbackSession?.startedAt ?? display.date
        progressEnd = validUntil
      case .justStarted:
        eyebrow = display.labels.now
        validUntil = event.time.addingTimeInterval(15 * 60)
        progressStart = event.time
        progressEnd = validUntil
      case .countdown:
        guard event.time > display.date,
          event.time.timeIntervalSince(display.date) <= 8 * 60 * 60
        else { return nil }
        eyebrow = display.focusIsTomorrow ? display.labels.tomorrow : display.labels.nextPrayer
        validUntil = event.time
        progressStart = min(display.prayerState?.previous?.time ?? display.date, display.date)
        progressEnd = event.time
      }
      guard validUntil > display.date else { return nil }
    }
  }

  /// An event identity prevents a dismissed activity from being immediately replaced for the same prayer.
  var eventID: String

  static func eventID(for state: ContentState) -> String {
    "\(state.prayerKind.rawValue):\(state.prayerTime.timeIntervalSince1970)"
  }
}

/// iOS destinations shared by Home Screen, Lock Screen and Live Activity surfaces.
nonisolated enum IOSSurfaceLink {
  static let today = URL(string: "salah://today")!
  static let location = URL(string: "salah://settings/location")!
  static let sound = URL(string: "salah://settings/sound")!
  static let activity = URL(string: "salah://today?source=activity")!
}

nonisolated enum IOSControlKind {
  static let muteSounds = "io.github.salah-kit.Salah.ios.controls.muteSounds"
  static let stopAudio = "io.github.salah-kit.Salah.ios.controls.stopAudio"
}
