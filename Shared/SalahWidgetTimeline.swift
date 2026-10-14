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
  /// timeline over the default 48-hour horizon: an entry wherever the state changes,
  /// the steps between them, the expired entry at its end, and a reload halfway there.
  /// It adds an entry at each midnight in the location's zone, with the state then, so
  /// the listed day turns over with the date (salah-kit/SalahKit#14).
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
      return SalahDisplay(
        date: date, settings: settings, day: day, state: state, playback: playback)
    }

    let planned: PrayerTimeline
    do {
      planned = try PrayerTimelineBuilder(
        schedule: schedule, policy: SalahDisplay.policy, strategy: strategy
      ).timeline(from: now)
    } catch {
      // Only an invalid horizon or strategy fails; show that the times need refreshing
      // until the app reloads the widget, as SalahWidgets' own WidgetKit timeline does.
      return SalahWidgetTimeline(
        entries: [SalahWidgetEntry(date: now, content: .expired(settings))], reload: .never,
        planned: nil)
    }

    var entries: [SalahWidgetEntry] = []
    for (index, entry) in planned.entries.enumerated() {
      switch entry.state {
      case .expired:
        entries.append(SalahWidgetEntry(date: entry.date, content: .expired(settings)))
      case .schedule(let state):
        entries.append(
          SalahWidgetEntry(
            date: entry.date, content: .schedule(display(at: entry.date, state: state))))
        // Midnights before the next entry: the state holds, the listed day changes.
        guard index + 1 < planned.entries.count else { continue }
        let end = planned.entries[index + 1].date
        var midnight = CivilDay(containing: entry.date, in: zone).adding(days: 1).start(in: zone)
        while midnight < end {
          let state = schedule.state(
            at: midnight, through: midnight.addingTimeInterval(SalahDisplay.lookahead),
            policy: SalahDisplay.policy)
          entries.append(
            SalahWidgetEntry(
              date: midnight, content: .schedule(display(at: midnight, state: state))))
          midnight = CivilDay(containing: midnight, in: zone).adding(days: 1).start(in: zone)
        }
      }
    }
    return SalahWidgetTimeline(
      entries: entries, reload: .after(planned.reloadDate), planned: planned)
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
      theme: .nocturne, silentMode: false, hijriOffset: 0,
      alerts: Dictionary(
        uniqueKeysWithValues: PrayerKind.allCases.map { ($0, PrayerAlerts(alert: $0.isPrayer)) }),
      jumuahAlerts: nil)
  }
}
