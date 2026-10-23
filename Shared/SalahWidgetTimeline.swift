import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import SalahWidgets

/// One widget entry: when it starts and what it shows.
nonisolated struct SalahWidgetEntry: Sendable {
  /// What an entry shows.
  enum Content: Sendable {
    /// No settings in the App Group yet: the app hasn't run. The face follows the
    /// device's language, the only one known.
    case setupNeeded
    /// The schedule at the entry's date: the living schedule, the Stop control while
    /// something plays, or the unavailable face when the schedule knows nothing.
    case schedule(SalahDisplay)
    /// The timeline ran out before WidgetKit asked for a new one: the times need
    /// refreshing, so no countdown shows.
    case expired(SalahSettings)
  }

  var date: Date
  var content: Content
}

/// The widget's timeline, as plain values a test can inspect: a pure function of the
/// settings, what's playing and the moment, run by the extension's provider and by the
/// tests with a fixed clock.
nonisolated struct SalahWidgetTimeline: Sendable {
  /// When to ask for the next timeline.
  enum Reload: Equatable, Sendable {
    /// Only when the app asks, after it saves its first settings.
    case never
    /// At this date.
    case after(Date)
  }

  /// Salah's static countdown cadence: an entry every minute within 15 minutes of each
  /// prayer (its imminent and count-up windows), and every five minutes elsewhere.
  static let strategy = RefreshStrategy.steps(
    fine: .seconds(60), coarse: .seconds(5 * 60), window: .seconds(15 * 60))

  /// WidgetKit archives the entries for every installed size before publishing a
  /// replacement. Bound that work so an interactive refresh reaches the display
  /// promptly; the builder ends at the first omitted change and reloads halfway.
  static let entryLimit = 48

  /// The entries, in date order.
  var entries: [SalahWidgetEntry]
  /// When to ask for the next timeline.
  var reload: Reload
  /// SalahWidgets' timeline the entries came from; `nil` while the widget waits for setup
  /// or when the timeline couldn't be planned.
  var planned: PrayerTimeline?

  /// The timeline from `now`.
  ///
  /// Without settings, one setup entry and no reload until the app saves its settings.
  /// With settings, the extension builds its own schedule and SalahWidgets' steps
  /// timeline over the default 48-hour horizon, capped at `entryLimit`: an entry
  /// wherever the state changes, the steps between them, an expired entry where the
  /// archive ends, and a reload halfway there.
  /// What's playing shows in the entries while it can still be playing.
  /// The builder includes civil-day boundaries so the listed day turns over with the date.
  static func make(settings: SalahSettings?, playback: SalahPlayback?, now: Date)
    -> SalahWidgetTimeline
  {
    guard let settings else {
      return SalahWidgetTimeline(
        entries: [SalahWidgetEntry(date: now, content: .setupNeeded)], reload: .never,
        planned: nil)
    }
    let schedule = settings.schedule
    let zone = settings.location.timeZone
    var days: [CivilDay: PrayerDayAvailability] = [:]
    func display(at date: Date, state: ScheduleState) -> SalahDisplay {
      let civilDay = CivilDay(containing: date, in: zone)
      let day = days[civilDay] ?? schedule.day(civilDay)
      days[civilDay] = day
      return SalahDisplay(date: date, settings: settings, day: day, state: state)
    }

    let planned: PrayerTimeline
    do {
      planned = try PrayerTimelineBuilder(
        schedule: schedule, policy: SalahDisplay.policy, strategy: strategy,
        includeDayBoundaries: true, limit: entryLimit
      ).timeline(from: now)
    } catch {
      // Only an invalid horizon or strategy fails; show that the times need refreshing
      // until the app reloads the widget, as SalahWidgets' own WidgetKit timeline does.
      return SalahWidgetTimeline(
        entries: [SalahWidgetEntry(date: now, content: .expired(settings))], reload: .never,
        planned: nil)
    }

    var entries: [SalahWidgetEntry] = []
    for entry in planned.entries {
      switch entry.state {
      case .expired:
        entries.append(SalahWidgetEntry(date: entry.date, content: .expired(settings)))
      case .schedule(let state):
        entries.append(
          SalahWidgetEntry(
            date: entry.date, content: .schedule(display(at: entry.date, state: state))))
      }
    }
    return SalahWidgetTimeline(
      entries: entries, reload: .after(planned.reloadDate), planned: planned
    ).applyingPlayback(playback)
  }

  /// Plan the normal schedule before reading the transient playback value. A Stop
  /// or Quit during planning must not publish the playback captured before it.
  /// The injectable planner observes that ordering without WidgetKit or a clock wait.
  static func makeForPublication(
    settings: SalahSettings?, now: Date, loadPlayback: () -> SalahPlayback?,
    planSchedule: (SalahSettings?, Date) -> SalahWidgetTimeline = {
      SalahWidgetTimeline.make(settings: $0, playback: nil, now: $1)
    }
  ) -> SalahWidgetTimeline {
    let timeline = planSchedule(settings, now)
    guard timeline.planned != nil else { return timeline }
    return timeline.applyingPlayback(loadPlayback())
  }

  /// Applies playback to a complete normal plan. The Stop face has no countdown
  /// or day header: its title, subtitle and tone stay identical for one playback.
  /// Keep only its first entry, then resume the original schedule at the exact
  /// playback bound. Never derive a cleared plan from an already compacted one.
  private func applyingPlayback(_ playback: SalahPlayback?) -> SalahWidgetTimeline {
    guard var planned, let first = entries.first,
      case .schedule(var firstDisplay) = first.content,
      let playback = playback?.playing(at: first.date)
    else { return self }
    let settings = firstDisplay.settings
    let end = playback.alertDate.addingTimeInterval(SalahPlayback.longestPlay)
    firstDisplay.playback = playback
    var published = [SalahWidgetEntry(date: first.date, content: .schedule(firstDisplay))]
    published += entries.filter { $0.date >= end }
    // If validity ends first, its expired entry must still end the Stop face.
    if end >= planned.validUntil {
      published = [published[0], entries[entries.count - 1]]
    } else if !published.contains(where: { $0.date == end }) {
      published.insert(
        SalahWidgetEntry(
          date: end,
          content: .schedule(
            SalahDisplay(date: end, settings: settings, schedule: settings.schedule))), at: 1)
    }
    // An expiry between cadence dates can add one entry when there were no
    // duplicate Stop entries to remove. End at the first omitted change rather
    // than exceeding the archive bound or hiding a missing schedule update.
    if published.count > Self.entryLimit {
      let cutoff = published[Self.entryLimit - 1].date
      published =
        Array(published.prefix(Self.entryLimit - 1))
        + [SalahWidgetEntry(date: cutoff, content: .expired(settings))]
      planned.validUntil = cutoff
      planned.reloadDate = first.date.addingTimeInterval(cutoff.timeIntervalSince(first.date) / 2)
    }
    planned.entries = published.compactMap { entry in
      switch entry.content {
      case .schedule(let display):
        PrayerTimeline.Entry(date: entry.date, state: .schedule(display.state))
      case .expired:
        PrayerTimeline.Entry(date: entry.date, state: .expired(knownThrough: entry.date))
      case .setupNeeded:
        nil
      }
    }
    return SalahWidgetTimeline(
      entries: published, reload: .after(planned.reloadDate), planned: planned)
  }
}

nonisolated extension SalahSettings {
  /// Settings for the widget gallery and placeholders: Makkah with Salah's default
  /// calculation, in the device's language.
  static var sample: SalahSettings {
    var parameters = CalculationMethod.ummAlQura.parameters
    parameters.highLatitudeRule = .middleOfTheNight
    let zone = TimeZone(identifier: "Asia/Riyadh") ?? TimeZone(secondsFromGMT: 3 * 3_600) ?? .gmt
    return SalahSettings(
      location: PrayerLocation(
        latitude: 21.4167, longitude: 39.8167, timeZone: zone, countryCode: "SA",
        name: "Makkah"),
      calculation: CalculationSettings(parameters: parameters), language: .system,
      appearance: .system, followsTimeOfDay: true, silentMode: false, hijriOffset: 0,
      alerts: Dictionary(
        uniqueKeysWithValues: PrayerKind.allCases.map { ($0, PrayerAlerts(alert: $0.isPrayer)) }),
      jumuahAlerts: nil)
  }
}
