import Foundation
import SalahCore
import SalahUI

/// What one Salah surface shows at one moment: a widget entry, the menu-bar dropdown, a
/// preview.
///
/// SalahCore decides the facts: which day is listed, which prayer is next, which just
/// started, whether the next one is near, and what the schedule can't say. This value
/// adds Salah's settings and what's playing, and answers the questions Salah's views ask
/// of those facts: the focus, the tone, each row's state, the text.
nonisolated struct SalahDisplay: Sendable {
  /// When a prayer counts as approaching (the imminent red, 15 minutes before it) and how
  /// long it counts as just started (the green count-up, 15 minutes after it). Salah has
  /// no iqama, so the window is fixed.
  static let policy = StatePolicy(
    approaching: .seconds(15 * 60), justStarted: .fixed(.seconds(15 * 60)))

  /// How far ahead a state looks: far enough that after Isha the next day's Fajr is known.
  static let lookahead: TimeInterval = 2 * 86_400

  /// The moment shown.
  var date: Date
  /// The mirrored settings: language, appearance, silent mode, Hijri offset, alerts.
  var settings: SalahSettings
  /// The listed day: the owning day that is the moment's civil date in the location's
  /// zone, or why it can't be listed.
  var day: PrayerDayAvailability
  /// The schedule's state at the moment.
  var state: ScheduleState
  /// What's playing, if anything.
  var playback: SalahPlayback?
  /// The prayer names, in the settings' language.
  var names: PrayerNames
  /// The header's dates and place.
  var header: SalahHeader
  /// The day after the listed one, which the widgets list after Isha; `nil` when unknown.
  var nextDay: PrayerDay?

  /// Builds a display from its parts; the names and the header follow the settings
  /// unless given (previews give their own).
  init(
    date: Date, settings: SalahSettings, day: PrayerDayAvailability, state: ScheduleState,
    playback: SalahPlayback? = nil, names: PrayerNames? = nil, header: SalahHeader? = nil,
    nextDay: PrayerDay? = nil
  ) {
    self.nextDay = nextDay
    self.date = date
    self.settings = settings
    self.day = day
    self.state = state
    self.playback = playback
    self.names = names ?? PrayerNames(locale: settings.locale)
    self.header = header ?? SalahHeader(date: date, settings: settings)
  }

  /// The display of `schedule` at `date`: the listed day and the state, as every surface
  /// asks for them.
  init(
    date: Date, settings: SalahSettings, schedule: PrayerSchedule,
    playback: SalahPlayback? = nil
  ) {
    let day = schedule.day(containing: date)
    self.init(
      date: date, settings: settings, day: day,
      state: schedule.state(
        at: date, through: date.addingTimeInterval(Self.lookahead), policy: Self.policy),
      playback: playback,
      nextDay: Self.day(after: day, in: schedule, zone: settings.location.timeZone))
  }

  /// The day after `day` in `schedule`, which the widgets list after Isha.
  static func day(after day: PrayerDayAvailability, in schedule: PrayerSchedule, zone: TimeZone)
    -> PrayerDay?
  {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    guard let listed = day.day,
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: listed.day.start(in: zone))
    else { return nil }
    return schedule.day(containing: tomorrow).day
  }

  // MARK: - Text

  var locale: Locale { settings.locale }
  var isRightToLeft: Bool { locale.language.characterDirection == .rightToLeft }
  var text: SalahText { SalahText(locale: locale, timeZone: settings.location.timeZone) }
  var labels: SalahWidgetLabels { text.labels }
  /// The time of day the surfaces draw in: the prayer period now, or the neutral sky when
  /// Salah doesn't follow the time of day or the day's times aren't known.
  var phase: SalahPhase {
    guard settings.followsTimeOfDay, let events = listedDay?.events else { return .neutral }
    return SalahPhase.at(date, events: events)
  }

  /// The prayer whose adhan or du'a plays, or the one a reminder after it plays for: the
  /// prayer one is in while it plays. `nil` for a reminder before a prayer, which plays
  /// while the prayer is still to come, and when nothing plays.
  var playingPrayer: PrayerEvent? {
    guard let event = playback?.event, event.time <= date else { return nil }
    return event
  }

  /// The known state, or `nil` when the schedule can't establish one.
  var prayerState: PrayerState? { state.prayerState }

  /// The face shared by the extension, its rendered preview and the Stop harness.
  enum WidgetFace: Equatable, Sendable {
    case stop
    case unavailable
    case schedule
  }

  /// A known alert can play during a schedule gap. Its Stop action takes precedence
  /// over the missing countdown; the timeline already bounds stale playback.
  var widgetFace: WidgetFace {
    if playback != nil { return .stop }
    return prayerState == nil ? .unavailable : .schedule
  }

  /// The listed day, when it's available.
  var listedDay: PrayerDay? { day.day }

  func name(of event: PrayerEvent) -> String { names.name(of: event) }
  func name(of kind: PrayerKind) -> String { names.name(of: kind) }
  func timeText(of event: PrayerEvent) -> String {
    text.timeFormatter().string(from: event.time).bidiIsolated
  }
  func alerts(for event: PrayerEvent) -> PrayerAlerts { settings.alerts(for: event) }
  func reminderDetail(for event: PrayerEvent) -> String? {
    text.reminderDetail(alerts(for: event))
  }

  // MARK: - The listed day

  /// One place in the listed day: a known event, or an expected kind the source couldn't
  /// give.
  enum Slot: Hashable, Sendable, Identifiable {
    case event(PrayerEvent)
    case missing(PrayerKind)

    var kind: PrayerKind {
      switch self {
      case .event(let event): event.kind
      case .missing(let kind): kind
      }
    }

    var id: PrayerKind { kind }
  }

  /// The listed day's places in canonical order: its events, and its missing kinds where
  /// they belong. Empty when the day isn't available.
  var slots: [Slot] {
    guard case .available(let day, let coverage) = day else { return [] }
    var slots = day.events.map(Slot.event)
    if case .partial(let missing) = coverage {
      slots += missing.keys.map(Slot.missing)
    }
    return slots.sorted { $0.kind < $1.kind }
  }

  /// Whether `event` belongs to the listed day.
  func isListed(_ event: PrayerEvent) -> Bool {
    listedDay.map { event.scheduleDay == $0.day } ?? false
  }

  // MARK: - Focus

  /// The one element that leads every surface: the green count-up of a prayer that just
  /// started, or the countdown to the next event, sunrise included.
  typealias Focus = PrayerFocus

  /// The package selects the just-started prayer or the next event, sunrise included.
  var focus: Focus? {
    prayerState.flatMap { PrayerFocus(state: $0, selection: .justStartedOrNextEvent) }
  }

  /// Whether the focus belongs to a later day than the listed one, such as tomorrow's
  /// Fajr after Isha: the Tomorrow card.
  var focusIsTomorrow: Bool {
    guard case .countdown(let event)? = focus, let day = listedDay else { return false }
    return event.scheduleDay > day.day
  }

  /// The focus when it isn't a row of the listed day, so it floats beneath the rows.
  var floatingFocus: Focus? {
    guard let focus, !isListed(focus.event) else { return nil }
    return focus
  }

  // MARK: - Tones and row states

  /// Tone for the moment: silent, the playing slot's color, the imminent red in the last
  /// 15 minutes before a prayer (never before sunrise, which isn't one), or normal.
  var tone: SalahWidgetTone {
    if settings.silentMode { return .silent }
    if let playback { return playback.tone }
    return prayerState?.isApproaching == true ? .imminent : .normal
  }

  /// Tone for the ambient background wash: like `tone`, but green while a prayer counts
  /// up.
  var backgroundTone: SalahWidgetTone {
    if settings.silentMode { return .silent }
    if let playback { return playback.tone }
    if focus?.isCountUp == true { return .playingPrayerAudio }
    return tone
  }

  /// A row's state from its status in the state, with the playing prayer's override.
  /// Without a known state, a row is passed or upcoming by its time alone.
  func rowState(for event: PrayerEvent, status: PrayerEventStatus?) -> SalahWidgetRowState {
    if let playback, playback.event.id == event.id {
      return .active(playback.tone)
    }
    switch status {
    case .next?: return .next(tone)
    case .justStarted?: return .current
    case .passed?: return .passed
    case .upcoming?: return .upcoming
    case nil: return event.time <= date ? .passed : .upcoming
    }
  }

  /// The "since" count-up on the row of the latest event, sunrise included ("+1:30"),
  /// unless that row shows the green "Now" count-up itself. It anchors the row the user
  /// is "at", the playing prayer's row included.
  func sinceText(for event: PrayerEvent, status: PrayerEventStatus?) -> String? {
    guard let previous = prayerState?.previous, previous.id == event.id,
      rowState(for: event, status: status) != .current
    else { return nil }
    return text.duration(
      date.timeIntervalSince(previous.time), direction: .elapsed, bidiIsolated: true)
  }

  /// The small widget's "since previous prayer" line ("Dhuhr since: +1:30"), in the
  /// language's word order, or `nil` while a prayer counts up or when the latest event
  /// isn't known.
  var sinceLine: String? {
    guard focus?.isCountUp != true, let previous = prayerState?.previous else { return nil }
    let elapsed = text.duration(
      date.timeIntervalSince(previous.time), direction: .elapsed, bidiIsolated: true)
    return labels.sinceLine(prayer: name(of: previous), time: elapsed)
  }

  // MARK: - Playing

  /// The playing banner's title: "Playing Adhan", "Playing Du’ā’", "Pre-reminder".
  var playingTitle: String? {
    guard let playback else { return nil }
    if playback.isDua { return labels.playingDua }
    switch playback.slot {
    case .alert: return labels.playingAdhan
    case .preReminder: return labels.playingPreReminder
    case .postReminder: return labels.playingPostReminder
    }
  }

  /// The playing banner's subtitle: the prayer and its time, or the reminder's offset
  /// ("Maghrib · 7:00 PM", "Maghrib · 10m before").
  var playingSubtitle: String? {
    guard let playback else { return nil }
    let prayer = name(of: playback.event)
    switch playback.slot {
    case .alert:
      return "\(prayer) · \(timeText(of: playback.event))"
    case .preReminder, .postReminder:
      guard let offset = playback.offsetMinutes else { return prayer }
      return "\(prayer) · \(text.offsetPhrase(offset, before: playback.slot == .preReminder))"
    }
  }
}

/// The header's dates and place: the Hijri date after the user's offset, the Gregorian
/// date, and the location's name.
nonisolated struct SalahHeader: Equatable, Sendable {
  var hijriDay: String
  var hijriMonth: String
  var hijriYear: String
  var gregorianDate: String
  var location: String

  init(
    hijriDay: String, hijriMonth: String, hijriYear: String, gregorianDate: String,
    location: String
  ) {
    self.hijriDay = hijriDay
    self.hijriMonth = hijriMonth
    self.hijriYear = hijriYear
    self.gregorianDate = gregorianDate
    self.location = location
  }

  /// The header for a moment, in the settings' language and the location's zone.
  init(date: Date, settings: SalahSettings) {
    let text = SalahText(locale: settings.locale, timeZone: settings.location.timeZone)
    let hijri = text.hijri(date, dayOffset: settings.hijriOffset)
    self.init(
      hijriDay: hijri.day, hijriMonth: hijri.month, hijriYear: hijri.year,
      gregorianDate: text.gregorianDate(date), location: settings.location.name ?? "")
  }
}
