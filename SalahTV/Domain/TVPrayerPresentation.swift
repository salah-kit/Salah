import Foundation
import SalahCore
import SalahUI

/// The TV's wording and numerals around SalahCore's schedule facts: the hero, the rows, the
/// room display's cells. No prayer selection or time policy lives in the views.
nonisolated struct TVPrayerPresentation: Sendable {
  let display: SalahDisplay
  /// Whether the adhan can sound at all: a muted Apple TV plays nothing.
  var preferences: IOSPreferences

  var copy: TVCopy { TVCopy(locale: display.locale) }
  var time: TVTimeText {
    TVTimeText(locale: display.locale, timeZone: display.settings.location.timeZone)
  }

  // MARK: - The hero

  /// The event the hero leads with: the prayer that just started, or the next event,
  /// sunrise included.
  var event: PrayerEvent? { display.playback?.event ?? display.focus?.event }
  var isCountingUp: Bool { display.playback == nil && display.focus?.isCountUp == true }
  var isApproaching: Bool {
    display.playback == nil && !isCountingUp && display.prayerState?.isApproaching == true
      && display.focus?.event.kind != .sunrise
  }

  var eyebrow: String {
    if isCountingUp { return display.labels.now }
    if display.focusIsTomorrow { return display.labels.tomorrow }
    if event?.kind == .sunrise { return display.name(of: .sunrise) }
    return display.labels.nextPrayer
  }

  var name: String { event.map(display.name(of:)) ?? copy("Not available", "غير متاح") }

  /// "Begins at 3:35 PM", with the iqama when the source gives one.
  var subtitle: String {
    guard let event else { return unavailableExplanation }
    let start = time.time(event.time)
    var line =
      isCountingUp
      ? copy.format("Began at %@", "بدأت الساعة %@", start)
      : copy.format("Begins at %@", "تبدأ الساعة %@", start)
    if let iqama = event.iqama {
      line += " · " + copy("Iqama", "الإقامة") + " " + time.time(iqama)
    }
    return line
  }

  /// The countdown, or the count-up after a prayer begins: "2:16:00", "+0:02:10".
  var countdown: String {
    guard let event else { return "—" }
    return Self.clock(
      isCountingUp
        ? display.date.timeIntervalSince(event.time) : event.time.timeIntervalSince(display.date),
      countingUp: isCountingUp, text: display.text)
  }

  /// What the hero says about sound: when the adhan plays, or why nothing will.
  var soundNote: (text: String, isOn: Bool)? {
    guard let event else { return nil }
    if isCountingUp, let next = display.prayerState?.nextPrayer {
      return (
        copy("Next:", "القادمة:") + " " + display.name(of: next) + " " + time.time(next.time), true
      )
    }
    if preferences.muteSounds {
      return (
        copy("Sounds are off on this Apple TV", "الأصوات متوقفة على جهاز Apple TV هذا"), false
      )
    }
    let sound = preferences.tvSound(for: event.kind, observance: event.observance)
    guard sound != .none else {
      return (copy.format("No sound for %@", "%@ بلا صوت", display.name(of: event)), false)
    }
    switch sound {
    case .adhan, .fajrAdhan:
      return (
        copy.format(
          "Adhan at %@ while Salah is open", "الأذان الساعة %@ ما دام تطبيق صلاة مفتوحًا",
          time.time(event.time)), true
      )
    default:
      return (
        copy.format(
          "Tone at %@ while Salah is open", "نغمة الساعة %@ ما دام تطبيق صلاة مفتوحًا",
          time.time(event.time)), true
      )
    }
  }

  var unavailableExplanation: String {
    copy(
      "Prayer times are unavailable for this location and date. Review the calculation settings.",
      "أوقات الصلاة غير متاحة لهذا الموقع والتاريخ. راجع إعدادات الحساب.")
  }

  /// The hero for VoiceOver: “Next prayer, Asr, begins at 3:35 PM, in 2 hours 16 minutes”.
  var heroAccessibility: String {
    guard let event else { return [eyebrow, unavailableExplanation].joined(separator: ", ") }
    let interval =
      isCountingUp
      ? display.date.timeIntervalSince(event.time) : event.time.timeIntervalSince(display.date)
    let spoken = Self.spokenDuration(interval, locale: display.locale)
    let relative =
      isCountingUp
      ? copy.format("%@ ago", "منذ %@", spoken) : copy.format("in %@", "بعد %@", spoken)
    return ([eyebrow, name, subtitle, relative] + [soundNote?.text].compactMap { $0 })
      .joined(separator: ", ")
  }

  // MARK: - Rows and cells

  /// Audio playback is independent of when a prayer starts. Only the schedule can say Now.
  func status(of event: PrayerEvent) -> PrayerEventStatus {
    display.prayerState?.status(of: event) ?? (event.time <= display.date ? .passed : .upcoming)
  }

  /// The relative time beside a row: "in 2:16" for the next prayer, "1 hr ago" for the one
  /// that started last.
  func detail(for event: PrayerEvent) -> String? {
    guard let state = display.prayerState else { return nil }
    switch state.status(of: event) {
    case .next:
      return copy.format(
        "in %@", "بعد %@", compactRemaining(event.time.timeIntervalSince(display.date)))
    case .justStarted:
      return elapsedPhrase(display.date.timeIntervalSince(event.time))
    case .passed where state.previous?.id == event.id:
      return elapsedPhrase(display.date.timeIntervalSince(event.time))
    case .passed, .upcoming:
      return nil
    }
  }

  /// The countdown chip on the room display's next cell: "in 1:35".
  func chip(for event: PrayerEvent) -> String? {
    switch status(of: event) {
    case .next:
      return copy.format(
        "in %@", "بعد %@", compactRemaining(event.time.timeIntervalSince(display.date)))
    case .justStarted:
      return copy("Now", "الآن")
    case .passed, .upcoming:
      return nil
    }
  }

  /// A row for VoiceOver: “Asr, 3:35 PM, in 2 hours 16 minutes, next prayer”.
  func rowAccessibility(for event: PrayerEvent) -> String {
    var parts = [display.name(of: event), time.time(event.time)]
    switch status(of: event) {
    case .next(let approaching):
      let spoken = Self.spokenDuration(
        event.time.timeIntervalSince(display.date), locale: display.locale)
      parts.append(copy.format("in %@", "بعد %@", spoken))
      parts.append(
        approaching && event.kind.isPrayer
          ? copy("next prayer, soon", "الصلاة القادمة، قريبًا")
          : (event.kind.isPrayer ? copy("next prayer", "الصلاة القادمة") : copy("next", "التالي")))
    case .justStarted:
      parts.append(copy("now", "الآن"))
      parts.append(elapsed(since: event))
    case .passed where display.prayerState?.previous?.id == event.id:
      parts.append(elapsed(since: event))
    case .passed:
      parts.append(copy("passed", "انقضت"))
    case .upcoming:
      break
    }
    if let iqama = event.iqama {
      parts.append(copy("Iqama", "الإقامة") + " " + time.time(iqama))
    }
    return parts.joined(separator: ", ")
  }

  /// "1 hour ago", as the row's "1 hr ago" is read.
  private func elapsed(since event: PrayerEvent) -> String {
    copy.format(
      "%@ ago", "منذ %@",
      Self.spokenDuration(display.date.timeIntervalSince(event.time), locale: display.locale))
  }

  private func compactRemaining(_ seconds: TimeInterval) -> String {
    if seconds >= 3_600 { return display.text.duration(seconds) }
    if seconds >= 60 {
      return copy.format("%@ min", "%@ د", display.text.digits(Int(ceil(seconds / 60))))
    }
    return copy.format("%@ sec", "%@ ث", display.text.digits(Int(max(0, ceil(seconds)))))
  }

  private func elapsedPhrase(_ seconds: TimeInterval) -> String {
    if seconds >= 3_600 {
      return copy.format("%@ hr ago", "منذ %@ س", display.text.digits(Int(seconds / 3_600)))
    }
    if seconds >= 60 {
      return copy.format("%@ min ago", "منذ %@ د", display.text.digits(Int(seconds / 60)))
    }
    return copy.format("%@ sec ago", "منذ %@ ث", display.text.digits(Int(max(0, seconds))))
  }

  /// The hero's seconds-resolution clock: hours, then two-digit minutes and seconds.
  static func clock(_ interval: TimeInterval, countingUp: Bool, text: SalahText) -> String {
    guard interval.isFinite else { return "—" }
    let seconds = Int(max(0, countingUp ? floor(interval) : ceil(interval)))
    let value = [
      text.digits(seconds / 3_600), text.digits((seconds / 60) % 60, minimumDigits: 2),
      text.digits(seconds % 60, minimumDigits: 2),
    ].joined(separator: ":")
    return (countingUp ? "+" : "") + value
  }

  /// A duration as words, for VoiceOver: “2 hours, 16 minutes”.
  static func spokenDuration(_ interval: TimeInterval, locale: Locale) -> String {
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
