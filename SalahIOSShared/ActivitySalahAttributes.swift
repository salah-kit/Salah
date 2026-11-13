import ActivityKit
import Foundation
import SalahCore
import SalahUI

/// The single prayer a Live Activity follows. Values stay independent of the app process.
nonisolated struct SalahActivityAttributes: ActivityAttributes, Sendable {
  struct ContentState: Codable, Hashable, Sendable {
    /// `ended` is never published: it is what a stale playback becomes (see `stale`).
    enum Mode: String, Codable, Sendable { case countdown, justStarted, playing, ended }

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

    /// Whether the content still describes the moment. Past `validUntil` the activity is stale.
    func isValid(at date: Date) -> Bool { date < validUntil }

    /// What a stale activity shows. iOS suspends Salah in the background, so nothing updates or
    /// ends the activity when `validUntil` passes; iOS only tells the extension that the content
    /// is stale, once. This state needs no further update to stay true.
    ///
    /// A countdown goes stale at its prayer's time, and a count-up or an adhan played at the
    /// prayer's time within the 15 minutes after it: the prayer has begun, so the activity
    /// counts up from its time, which the system keeps running. It says where, not "now",
    /// because it can stay on the Lock Screen for hours. Any other playback (a reminder
    /// before its prayer, an adhan replayed later) has nothing left to count: the activity
    /// keeps the prayer and its time.
    var stale: Self {
      var state = self
      state.updatedAt = validUntil
      state.eyebrow = place
      // The prayer's span, or the sound's, is over: a full bar. A reminder played before
      // its prayer goes stale before that prayer's time.
      let end = min(prayerTime, validUntil)
      state.progressStart = end.addingTimeInterval(-1)
      state.progressEnd = end
      let sinceThePrayer = validUntil.timeIntervalSince(prayerTime)
      if sinceThePrayer >= 0, sinceThePrayer <= Self.countUpWindow {
        state.mode = .justStarted
        state.validUntil = prayerTime.addingTimeInterval(Self.staleCountUp)
      } else {
        state.mode = .ended
      }
      return state
    }

    /// How long after its time a prayer counts up.
    static let countUpWindow: TimeInterval = 15 * 60
    /// iOS ends a Live Activity eight hours after it starts and can keep it on the Lock Screen
    /// four hours more, so a stale count-up never reaches its end on screen.
    static let staleCountUp: TimeInterval = 12 * 60 * 60

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

    /// Whether the activity counts toward or from its prayer. A playback has a Stop button
    /// in the timer's place, and an ended one has nothing to count.
    var showsTimer: Bool { mode == .countdown || mode == .justStarted }

    func spokenLabel(at date: Date) -> String {
      let comma = IOSL10n.text(", ", arabic: "، ", locale: Locale(identifier: languageIdentifier))
      guard mode != .ended else { return "\(prayerName)\(comma)\(prayerTimeText)" }
      let duration = PrayerDurationFormat.string(
        timerSeconds(at: date), direction: mode == .countdown ? .remaining : .elapsed,
        width: .spoken, locale: Locale(identifier: languageIdentifier))
      return "\(prayerName)\(comma)\(eyebrow)\(comma)\(duration)"
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
      case .ended: return nil
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
        validUntil = event.time.addingTimeInterval(Self.countUpWindow)
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
