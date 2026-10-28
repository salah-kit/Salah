import Foundation
import SalahCore
import SalahUI

/// The watch's hero and rows: the iPhone app's wording for the same schedule facts
/// (`IOSPrayerPresentation`), in the states the watch design draws. No prayer selection or
/// time policy lives in the views.
nonisolated struct WatchPrayerPresentation: Sendable {
  let display: SalahDisplay

  private var base: IOSPrayerPresentation { IOSPrayerPresentation(display: display) }
  var copy: WatchCopy { WatchCopy(locale: display.locale) }

  // MARK: - The hero

  /// What the hero shows.
  enum HeroMode: Equatable, Sendable {
    /// The next prayer and its countdown.
    case countdown
    /// The last 15 minutes before a prayer: the countdown in gold, inside a gold rim.
    case approaching
    /// A prayer that began less than 15 minutes ago, counting up under a Now badge.
    case justStarted
    /// After Isha: tomorrow's Fajr.
    case tomorrow
    /// The schedule can't name the next prayer.
    case unknown
    /// An adhan plays, with Stop.
    case playing
  }

  var heroMode: HeroMode {
    if display.playback != nil { return .playing }
    guard base.event != nil else { return .unknown }
    if base.isCountingUp { return .justStarted }
    if display.focusIsTomorrow { return .tomorrow }
    if base.isApproaching { return .approaching }
    return .countdown
  }

  /// The event the hero leads with: the prayer whose adhan plays, the prayer that just
  /// started, or the next event, sunrise included.
  var heroEvent: PrayerEvent? { base.event }

  /// "Next prayer", "Tomorrow", "Now", "Sunrise" or "Playing adhan".
  var eyebrow: String {
    switch heroMode {
    case .unknown: display.labels.nextPrayer
    default: base.eyebrow
    }
  }

  var heroName: String { heroEvent.map(display.name(of:)) ?? "—" }

  /// The hero event's time, or why there's none.
  var heroTime: String {
    heroEvent.map(display.timeText(of:)) ?? copy("Not available today", "غير متاح اليوم")
  }

  /// The countdown, or the count-up after a prayer begins: "2:16:00", "+0:04:00". With the
  /// wrist down the watch dims and redraws once a minute, so it drops the seconds: "2:16".
  /// `nil` while the adhan plays and when no prayer is known.
  func countdown(showsSeconds: Bool = true) -> String? {
    guard let event = heroEvent, heroMode != .playing else { return nil }
    let countingUp = heroMode == .justStarted
    let interval =
      countingUp
      ? display.date.timeIntervalSince(event.time) : event.time.timeIntervalSince(display.date)
    guard showsSeconds else {
      let minutes = countingUp ? floor(max(0, interval) / 60) : ceil(max(0, interval) / 60)
      let value = [
        display.text.digits(Int(minutes) / 60),
        display.text.digits(Int(minutes) % 60, minimumDigits: 2),
      ].joined(separator: ":")
      return (countingUp ? "+" : "") + value
    }
    return IOSPrayerPresentation.clock(interval, countingUp: countingUp, text: display.text)
  }

  /// The hero for VoiceOver: "Next prayer, Asr, 3:35 PM, in 2 hours, 16 minutes".
  var heroAccessibility: String {
    // Without a prayer the card shows a dash, which VoiceOver would read as a word.
    guard let event = heroEvent else { return [eyebrow, heroTime].joined(separator: ", ") }
    var parts = [eyebrow, heroName, heroTime]
    switch heroMode {
    case .justStarted:
      let spoken = Self.spokenDuration(display.date.timeIntervalSince(event.time), display.locale)
      parts.append(copy.format("%@ ago", "منذ %@", spoken))
    case .countdown, .approaching, .tomorrow:
      let spoken = Self.spokenDuration(event.time.timeIntervalSince(display.date), display.locale)
      parts.append(copy.format("in %@", "بعد %@", spoken))
    case .playing, .unknown:
      break
    }
    return parts.joined(separator: ", ")
  }

  // MARK: - Rows

  /// A row's state, as the watch design draws it.
  enum RowState: Equatable, Sendable {
    /// Earlier today: quiet.
    case past
    /// Began less than 15 minutes ago, on the phase's wash.
    case current
    /// The next event, on the gold wash with its countdown.
    case next
    /// The next prayer within 15 minutes, on the gold wash.
    case approaching
    /// Later today.
    case upcoming
    /// The day has no time for it.
    case missing
  }

  /// One prayer, or sunrise, in a list.
  struct Row: Identifiable, Equatable, Sendable {
    var id: PrayerKind
    var glyph: String
    var name: String
    /// The time without its day period, as the watch face shows the clock: "3:35", or "—"
    /// when the day has none.
    var time: String
    /// "in 2:16", "Now", "Not today", or nothing.
    var detail: String?
    var state: RowState
    var accessibility: String
  }

  /// Every prayer of the listed day, sunrise included, in order.
  var todayRows: [Row] { display.slots.map(row) }

  /// The rows after the hero's event, on the screen it leads: the rest of its day. Empty when
  /// the hero shows tomorrow's Fajr or nothing.
  var followingRows: [Row] {
    guard let event = heroEvent, display.isListed(event) else { return [] }
    return display.slots.filter { $0.kind > event.kind }.map(row)
  }

  private func row(_ slot: SalahDisplay.Slot) -> Row {
    switch slot {
    case .missing(let kind):
      let name = display.name(of: kind)
      let detail = copy("Not today", "ليس اليوم")
      return Row(
        id: kind, glyph: kind.glyphName, name: name, time: "—", detail: detail, state: .missing,
        accessibility: [name, detail].joined(separator: ", "))
    case .event(let event):
      let state = rowState(for: event)
      let detail: String? =
        switch state {
        case .next, .approaching: base.detail(for: event)
        case .current: display.labels.now
        case .past, .upcoming, .missing: nil
        }
      return Row(
        id: event.kind, glyph: event.glyphName, name: display.name(of: event),
        time: display.text.compactTime(event.time), detail: detail, state: state,
        accessibility: rowAccessibility(for: event, state: state))
    }
  }

  private func rowState(for event: PrayerEvent) -> RowState {
    switch base.rowStatus(for: event) {
    case .passed: .past
    case .justStarted: .current
    case .next(let approaching): approaching && event.kind.isPrayer ? .approaching : .next
    case .upcoming: .upcoming
    }
  }

  /// A row for VoiceOver: "Asr, 3:35 PM, in 2 hours, 16 minutes, next prayer".
  private func rowAccessibility(for event: PrayerEvent, state: RowState) -> String {
    var parts = [display.name(of: event), display.timeText(of: event)]
    switch state {
    case .next, .approaching:
      let spoken = Self.spokenDuration(event.time.timeIntervalSince(display.date), display.locale)
      parts.append(copy.format("in %@", "بعد %@", spoken))
      parts.append(
        event.kind.isPrayer ? copy("next prayer", "الصلاة القادمة") : copy("next", "التالي"))
    case .current:
      parts.append(copy("now", "الآن"))
    case .past:
      parts.append(copy("passed", "انقضت"))
    case .upcoming, .missing:
      break
    }
    return parts.joined(separator: ", ")
  }

  /// A duration as words, for VoiceOver: "2 hours, 16 minutes".
  static func spokenDuration(_ interval: TimeInterval, _ locale: Locale) -> String {
    let formatter = DateComponentsFormatter()
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    formatter.calendar = calendar
    formatter.unitsStyle = .full
    formatter.allowedUnits = interval >= 3_600 ? [.hour, .minute] : [.minute, .second]
    formatter.maximumUnitCount = 2
    return formatter.string(from: max(0, interval.rounded(.up))) ?? ""
  }
}
