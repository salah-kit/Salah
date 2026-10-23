import Foundation
import SalahCore
import SalahUI

/// The app's wording and clock representation around SalahCore's schedule facts.
/// No prayer selection, fallback time, or location policy lives in the view layer.
nonisolated struct IOSPrayerScreenCopy: Sendable {
  let locale: Locale

  func callAsFunction(_ english: String, _ arabic: String) -> String {
    IOSL10n.text(english, arabic: arabic, locale: locale)
  }
}

nonisolated struct IOSPrayerPresentation: Sendable {
  let display: SalahDisplay

  var copy: IOSPrayerScreenCopy { IOSPrayerScreenCopy(locale: display.locale) }
  var event: PrayerEvent? { display.playback?.event ?? display.focus?.event }
  var isCountingUp: Bool { display.playback == nil && display.focus?.isCountUp == true }
  var isApproaching: Bool {
    display.playback == nil && !isCountingUp && display.prayerState?.isApproaching == true
      && display.focus?.event.kind != .sunrise
  }

  var eyebrow: String {
    if let title = display.playingTitle { return title }
    if isCountingUp { return display.labels.now }
    if display.focusIsTomorrow { return display.labels.tomorrow }
    if event?.kind == .sunrise { return copy("Sunrise", "الشروق") }
    return display.labels.nextPrayer
  }

  var name: String { event.map(display.name(of:)) ?? display.labels.nextUnknown }

  var subtitle: String {
    guard let event else { return unavailableExplanation }
    if let playback = display.playback {
      guard playback.slot != .alert, let offset = playback.offsetMinutes else {
        return display.timeText(of: event)
      }
      return String(
        format: playback.slot == .preReminder
          ? copy("%@ min before", "قبل %@ د") : copy("%@ min after", "بعد %@ د"),
        display.text.digits(offset))
    }
    return isCountingUp
      ? copy("Began at", "بدأت الساعة") + " " + display.timeText(of: event)
      : copy("Begins at", "تبدأ الساعة") + " " + display.timeText(of: event)
  }

  var countdown: String {
    guard let event else { return "—" }
    if let playback = display.playback {
      return Self.clock(
        display.date.timeIntervalSince(playback.alertDate), countingUp: true, text: display.text)
    }
    return Self.clock(
      isCountingUp
        ? display.date.timeIntervalSince(event.time) : event.time.timeIntervalSince(display.date),
      countingUp: isCountingUp, text: display.text)
  }

  var footer: String? {
    guard let event else { return nil }
    if display.settings.silentMode {
      return copy("Sounds muted · notifications stay on", "الأصوات مكتومة · الإشعارات مفعّلة")
    }
    if isCountingUp, let next = display.prayerState?.next {
      return copy("Next:", "القادمة:") + " " + display.name(of: next) + " "
        + display.timeText(of: next)
    }
    let alerts = display.alerts(for: event)
    var reminders: [String] = []
    if let minutes = alerts.beforeMinutes {
      reminders.append(
        String(format: copy("%@ min before", "قبل %@ د"), display.text.digits(minutes)))
    }
    if let minutes = alerts.afterMinutes {
      reminders.append(
        String(format: copy("%@ min after", "بعد %@ د"), display.text.digits(minutes)))
    }
    guard !reminders.isEmpty else { return nil }
    return copy("Reminder", "تذكير") + " " + reminders.joined(separator: " · ")
  }

  var missing: [PrayerKind: ScheduleGapReason] {
    guard case .partial(let values)? = display.day.coverage else { return [:] }
    return values
  }

  var hasCalculationGaps: Bool {
    if case .unavailable(.calculationUnavailable) = display.day { return true }
    return missing.values.contains(.calculationUnavailable)
  }

  var calculationGapMessage: String {
    copy("Some prayer times can’t be calculated", "تعذّر حساب بعض أوقات الصلاة")
  }

  var unavailableExplanation: String {
    if hasCalculationGaps { return calculationGapMessage }
    return copy(
      "Prayer times are unavailable for this location and date. Review calculation settings.",
      "أوقات الصلاة غير متاحة لهذا الموقع والتاريخ. راجع إعدادات الحساب.")
  }

  func missingDetail(_ reason: ScheduleGapReason) -> String {
    switch reason {
    case .calculationUnavailable: copy("Can’t be calculated", "يتعذّر حسابه")
    case .noPublishedData: copy("Not published", "غير منشور")
    case .invalidData, .unresolvedWallTime: display.labels.notAvailable
    }
  }

  /// Audio playback is independent of when a prayer starts. Only the schedule can say Now.
  func rowStatus(for event: PrayerEvent) -> PrayerEventStatus {
    display.prayerState?.status(of: event) ?? (event.time <= display.date ? .passed : .upcoming)
  }

  /// This follows the audio queue rather than a preference that might not apply to this sound.
  func playbackFooter(hasQueuedDua: Bool) -> String? {
    guard let playback = display.playback, playback.slot == .alert, !playback.isDua, hasQueuedDua
    else {
      return nil
    }
    return copy("The du’ā’ after the adhan follows", "يلي الأذان الدعاء")
  }

  func detail(for event: PrayerEvent, live: Bool = true) -> String? {
    var pieces: [String] = []
    if live, let state = display.prayerState {
      switch state.status(of: event) {
      case .next:
        let interval = compactRemaining(event.time.timeIntervalSince(display.date))
        pieces.append(copy("in", "بعد") + " " + interval)
      case .justStarted:
        pieces.append(elapsedPhrase(display.date.timeIntervalSince(event.time)))
      case .passed where state.previous?.id == event.id:
        pieces.append(elapsedPhrase(display.date.timeIntervalSince(event.time)))
      case .passed, .upcoming: break
      }
    }
    if let iqama = event.iqama {
      pieces.append(
        copy("Iqama", "الإقامة") + " "
          + display.text.timeFormatter().string(from: iqama).bidiIsolated)
    }
    return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
  }

  private func compactRemaining(_ seconds: TimeInterval) -> String {
    if seconds >= 3_600 { return display.text.duration(seconds) }
    if seconds >= 60 {
      return String(format: copy("%@ min", "%@ د"), display.text.digits(Int(ceil(seconds / 60))))
    }
    return String(format: copy("%@ sec", "%@ ث"), display.text.digits(Int(max(0, ceil(seconds)))))
  }

  private func elapsedPhrase(_ seconds: TimeInterval) -> String {
    if seconds >= 3_600 {
      return String(
        format: copy("%@ hr ago", "منذ %@ س"), display.text.digits(Int(seconds / 3_600)))
    }
    if seconds >= 60 {
      return String(format: copy("%@ min ago", "منذ %@ د"), display.text.digits(Int(seconds / 60)))
    }
    return String(format: copy("%@ sec ago", "منذ %@ ث"), display.text.digits(Int(max(0, seconds))))
  }

  func glyph(for event: PrayerEvent) -> String {
    event.observance == .jumuah ? "salah.jumuah" : "salah." + event.kind.rawValue
  }

  func dayOffset(for event: PrayerEvent) -> String? {
    let actual = CivilDay(containing: event.time, in: display.settings.location.timeZone)
    let offset = event.scheduleDay.days(to: actual)
    guard offset != 0 else { return nil }
    return (offset > 0 ? "+" : "−") + display.text.digits(abs(offset))
  }

  /// The hero has a seconds-resolution clock, while rows use SalahCore's compact duration.
  static func clock(_ interval: TimeInterval, countingUp: Bool, text: SalahText) -> String {
    guard interval.isFinite else { return "—" }
    let seconds = Int(max(0, countingUp ? floor(interval) : ceil(interval)))
    let value = [
      text.digits(seconds / 3_600), text.digits((seconds / 60) % 60, minimumDigits: 2),
      text.digits(seconds % 60, minimumDigits: 2),
    ].joined(separator: ":")
    return (countingUp ? "+" : "") + value
  }
}
