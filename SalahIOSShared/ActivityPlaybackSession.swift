import Foundation
import SalahWidgets

/// A user-started iOS playback session expires by its actual start and duration.
/// Prayer time is content, never a proxy for when a person pressed Play.
nonisolated struct IOSPlaybackSession: Codable, Equatable, Sendable {
  static let maximumRecordingDuration: TimeInterval = 30 * 60
  static let duaMaximumDuration: TimeInterval = 120
  /// An accepted recording can finish its queued du’a before external Stop controls expire.
  static let maximumDuration = maximumRecordingDuration + duaMaximumDuration

  var playback: SalahPlayback
  var startedAt: Date
  var expiresAt: Date

  init(playback: SalahPlayback, startedAt: Date, duration: TimeInterval) {
    self.playback = playback
    self.startedAt = startedAt
    let boundedDuration = duration.isFinite ? min(Self.maximumDuration, max(0, duration)) : 0
    expiresAt = startedAt.addingTimeInterval(boundedDuration)
  }

  func playing(at date: Date) -> SalahPlayback? {
    let duration = expiresAt.timeIntervalSince(startedAt)
    guard duration.isFinite, duration > 0, duration <= Self.maximumDuration else { return nil }
    return startedAt <= date && date < expiresAt ? playback : nil
  }
}

nonisolated extension SharedValue where Value == IOSPlaybackSession {
  static var iosPlayback: Self {
    SharedValue(
      appGroup: SalahWidgetConstants.appGroupID, key: "Salah.iOS.playbackSession.v1")
  }
}

/// Overlays actual user playback on the reusable schedule without applying macOS alert-time expiry.
nonisolated enum IOSSurfaceTimeline {
  static func make(settings: SalahSettings?, session: IOSPlaybackSession?, now: Date)
    -> SalahWidgetTimeline
  {
    let normal = SalahWidgetTimeline.make(settings: settings, playback: nil, now: now)
    return applying(session: session, to: normal, now: now)
  }

  /// A Stop during schedule calculation must be observed before publishing a new archive.
  static func makeForPublication(
    settings: SalahSettings?, now: Date, loadSession: () -> IOSPlaybackSession?,
    planSchedule: (SalahSettings?, Date) -> SalahWidgetTimeline = {
      SalahWidgetTimeline.make(settings: $0, playback: nil, now: $1)
    }
  ) -> SalahWidgetTimeline {
    let normal = planSchedule(settings, now)
    return applying(session: loadSession(), to: normal, now: now)
  }

  private static func applying(
    session: IOSPlaybackSession?, to normal: SalahWidgetTimeline, now: Date
  ) -> SalahWidgetTimeline {
    guard let session, let playback = session.playing(at: now),
      let first = normal.entries.first, case .schedule(var display) = first.content
    else { return normal }
    display.playback = playback
    let end = session.expiresAt
    var published = [SalahWidgetEntry(date: first.date, content: .schedule(display))]
    let expiry = normal.entries.first {
      if case .expired = $0.content { return true }
      return false
    }
    if let expiry, expiry.date <= end {
      published.append(expiry)
    } else {
      published.append(
        SalahWidgetEntry(
          date: end,
          content: .schedule(
            SalahDisplay(date: end, settings: display.settings, schedule: display.settings.schedule)
          )))
      published += normal.entries.filter { $0.date > end }
    }
    if published.count > SalahWidgetTimeline.entryLimit {
      let cut = published[SalahWidgetTimeline.entryLimit - 1].date
      published =
        Array(published.prefix(SalahWidgetTimeline.entryLimit - 1))
        + [SalahWidgetEntry(date: cut, content: .expired(display.settings))]
    }
    let reload: SalahWidgetTimeline.Reload
    if let last = published.last {
      reload = .after(now.addingTimeInterval(max(1, last.date.timeIntervalSince(now) / 2)))
    } else {
      reload = normal.reload
    }
    return SalahWidgetTimeline(entries: published, reload: reload, planned: normal.planned)
  }
}
