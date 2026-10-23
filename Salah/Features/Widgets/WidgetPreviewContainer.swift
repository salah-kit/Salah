import SalahCore
import SwiftUI

/// Renders the shared widget content at the measured normal desktop reference size, on the
/// time of day's sky and clipped to the widget's shape, in the appearance the settings
/// choose. The extension takes its actual bounds from WidgetKit; those can vary by host and
/// state. Used by the Appearance pane, design verification and SalahTests.
struct WidgetPreviewContainer: View {
  let display: SalahDisplay
  let size: SalahWidgetSize

  var body: some View {
    let pointSize = size.desktopPointSize
    let shape = RoundedRectangle(cornerRadius: size.desktopCornerRadius, style: .continuous)
    content
      .frame(width: pointSize.width, height: pointSize.height)
      .background {
        WidgetSky(
          phase: display.widgetFace == .schedule || display.widgetFace == .stop
            ? display.phase : .neutral)
      }
      .containerShape(shape)
      .clipShape(shape)
      .environment(\.locale, display.locale)
      .environment(\.layoutDirection, display.isRightToLeft ? .rightToLeft : .leftToRight)
      .salahColorScheme(display.settings.appearance.colorScheme)
  }

  /// The extension shell's branches that don't need a widget host.
  @ViewBuilder
  private var content: some View {
    switch display.widgetFace {
    case .stop:
      WidgetStopContent(display: display, size: size)
    case .unavailable:
      WidgetMessageContent(
        systemImage: "exclamationmark.triangle.fill",
        message: Text(verbatim: display.labels.timesUnavailable), phase: display.phase)
    case .schedule:
      WidgetContentView(display: display, size: size)
    }
  }
}

// MARK: - Verification gallery (previews only)

/// All four sizes for one display, for side-by-side design review. Renders at
/// the real "now" so the live relative timer (which always counts from the system
/// clock) agrees with the now-anchored preview prayer times.
private struct WidgetSizeGallery: View {
  let title: String
  let display: SalahDisplay

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(verbatim: title).font(.headline)
      HStack(alignment: .top, spacing: 20) {
        WidgetPreviewContainer(display: display, size: .small)
        WidgetPreviewContainer(display: display, size: .medium)
      }
      WidgetPreviewContainer(display: display, size: .large)
      WidgetPreviewContainer(display: display, size: .extraLarge)
    }
    .padding(24)
  }
}

/// Preview language: the hand-written prayer names, place and Hijri date the
/// previews have always shown, in English, Arabic or French, so RTL and
/// Arabic-Indic digits can be verified. Internal (with `WidgetPreviewData`) so
/// SalahTests renders these scenarios.
enum PreviewLang: CaseIterable {
  case en, ar, fr

  var language: AppLanguage {
    switch self {
    case .en: .english
    case .ar: .arabic
    case .fr: .french
    }
  }
  var location: String { self == .ar ? "مكة" : "Makkah" }
  var hijri: (day: String, month: String, year: String) {
    self == .ar ? ("١٢", "رمضان", "١٤٤٧") : ("12", "Ramadan", "1447")
  }

  func name(_ kind: PrayerKind) -> String {
    switch self {
    case .ar:
      switch kind {
      case .fajr: "الفجر"
      case .sunrise: "الشروق"
      case .dhuhr: "الظهر"
      case .asr: "العصر"
      case .maghrib: "المغرب"
      case .isha: "العشاء"
      }
    case .fr:
      switch kind {
      case .fajr: "Fajr"
      case .sunrise: "Lever"
      case .dhuhr: "Dhuhr"
      case .asr: "Asr"
      case .maghrib: "Maghreb"
      case .isha: "Isha"
      }
    case .en:
      switch kind {
      case .fajr: "Fajr"
      case .sunrise: "Sunrise"
      case .dhuhr: "Dhuhr"
      case .asr: "Asr"
      case .maghrib: "Maghrib"
      case .isha: "Isha"
      }
    }
  }

  /// SalahCore's names with the previews' own spellings.
  var names: PrayerNames {
    PrayerNames(
      locale: language.locale,
      overrides: Dictionary(
        uniqueKeysWithValues: PrayerKind.allCases.map { (PrayerNames.Entry.name($0), name($0)) }))
  }

  /// The previews' header: their Hijri date and place, and `now`'s Gregorian date.
  func header(now: Date) -> SalahHeader {
    let formatter = DateFormatter()
    formatter.locale = language.locale
    formatter.dateStyle = .full
    formatter.timeStyle = .none
    return SalahHeader(
      hijriDay: hijri.day, hijriMonth: hijri.month, hijriYear: hijri.year,
      gregorianDate: formatter.string(from: now), location: location)
  }
}

/// Builds preview displays with prayer times anchored to `now` (in minute offsets),
/// in the device's time zone, so both SalahCore's state and the live relative timer
/// render truthfully, in the chosen language. Every scenario takes `now` (the real
/// clock by default) so SalahTests can render them at a fixed moment.
enum WidgetPreviewData {
  struct Spec {
    var id: PrayerKind
    var offset: Int  // minutes from now (negative = already passed)
    var alert = true
    var pre: Int? = nil
    var post: Int? = nil
  }

  static func make(
    prayers specs: [Spec],
    tomorrowFajrOffset: Int? = nil,
    silent: Bool = false,
    playing: PrayerKind? = nil,
    lang: PreviewLang = .en,
    now: Date = Date()
  ) -> SalahDisplay {
    let zone = TimeZone.current
    let today = CivilDay(containing: now, in: zone)
    func event(_ kind: PrayerKind, _ offset: Int, on day: CivilDay) -> PrayerEvent {
      PrayerEvent(
        scheduleDay: day, kind: kind, time: now.addingTimeInterval(TimeInterval(offset * 60)))
    }
    let events = specs.map { event($0.id, $0.offset, on: today) }
    var days = [today: events]
    if let tomorrowFajrOffset {
      days[today.adding(days: 1)] = [event(.fajr, tomorrowFajrOffset, on: today.adding(days: 1))]
    }
    let location = PrayerLocation(
      latitude: 21.4167, longitude: 39.8167, timeZone: zone, name: lang.location)
    let schedule = PrayerSchedule(source: PreviewSource(days: days), location: location)

    var alerts: [PrayerKind: PrayerAlerts] = [:]
    for spec in specs {
      alerts[spec.id] = PrayerAlerts(
        alert: spec.alert, beforeMinutes: spec.pre, afterMinutes: spec.post)
    }
    if tomorrowFajrOffset != nil {
      // Tomorrow's Fajr has always carried a 30-minute reminder in the previews.
      alerts[.fajr] = PrayerAlerts(alert: true, beforeMinutes: 30)
    }
    var settings = SalahSettings.sample
    settings.location = location
    settings.language = lang.language
    settings.silentMode = silent
    settings.alerts = alerts

    let playback = playing.flatMap { kind in
      events.first { $0.kind == kind }.map { SalahPlayback(event: $0, slot: .alert) }
    }
    return SalahDisplay(
      date: now, settings: settings, day: schedule.day(today),
      state: schedule.state(
        at: now, through: now.addingTimeInterval(SalahDisplay.lookahead),
        policy: SalahDisplay.policy),
      playback: playback, names: lang.names, header: lang.header(now: now))
  }

  /// A normal day with the next prayer (Maghrib, +2h42m) carrying pre+post reminders.
  static func standard(
    silent: Bool = false, playing: PrayerKind? = nil, lang: PreviewLang = .en, now: Date = Date()
  ) -> SalahDisplay {
    make(
      prayers: [
        Spec(id: .fajr, offset: -8 * 60, pre: 30),
        Spec(id: .sunrise, offset: -6 * 60, alert: false),
        Spec(id: .dhuhr, offset: -3 * 60),
        Spec(id: .asr, offset: -60),
        Spec(id: .maghrib, offset: 162, pre: 10, post: 5),
        Spec(id: .isha, offset: 4 * 60),
      ],
      silent: silent, playing: playing, lang: lang, now: now)
  }

  static func idle(_ lang: PreviewLang = .en, now: Date = Date()) -> SalahDisplay {
    standard(lang: lang, now: now)
  }
  static func silent(_ lang: PreviewLang = .en, now: Date = Date()) -> SalahDisplay {
    standard(silent: true, lang: lang, now: now)
  }
  static func playing(_ lang: PreviewLang = .en, now: Date = Date()) -> SalahDisplay {
    standard(playing: .maghrib, lang: lang, now: now)
  }

  /// 10 min before Maghrib → imminent, in gold.
  static func imminent(_ lang: PreviewLang = .en, now: Date = Date()) -> SalahDisplay {
    make(
      prayers: [
        Spec(id: .fajr, offset: -13 * 60),
        Spec(id: .sunrise, offset: -11 * 60, alert: false),
        Spec(id: .dhuhr, offset: -7 * 60),
        Spec(id: .asr, offset: -3 * 60),
        Spec(id: .maghrib, offset: 10, pre: 10, post: 5),
        Spec(id: .isha, offset: 80),
      ], lang: lang, now: now)
  }

  /// 4 min after Dhuhr started → the count-up leads; Asr is the secondary next.
  static func countUp(_ lang: PreviewLang = .en, now: Date = Date()) -> SalahDisplay {
    make(
      prayers: [
        Spec(id: .fajr, offset: -7 * 60, pre: 30),
        Spec(id: .sunrise, offset: -5 * 60, alert: false),
        Spec(id: .dhuhr, offset: -4),
        Spec(id: .asr, offset: 3 * 60 + 20),
        Spec(id: .maghrib, offset: 6 * 60, pre: 10, post: 5),
        Spec(id: .isha, offset: 8 * 60),
      ], lang: lang, now: now)
  }

  /// 16 min after Dhuhr started → the 15-min count-up window has closed, so the
  /// focus must be back to the next prayer's countdown (Asr), with no count-up.
  /// Guards the focus boundary: the count-up must not linger past 15 min
  /// (the bug where the widget kept counting up for hours).
  static func countUpEnded(
    _ lang: PreviewLang = .en, now: Date = Date()
  ) -> SalahDisplay {
    make(
      prayers: [
        Spec(id: .fajr, offset: -7 * 60, pre: 30),
        Spec(id: .sunrise, offset: -5 * 60, alert: false),
        Spec(id: .dhuhr, offset: -16),
        Spec(id: .asr, offset: 44, pre: 10),
        Spec(id: .maghrib, offset: 3 * 60, pre: 10, post: 5),
        Spec(id: .isha, offset: 5 * 60),
      ], lang: lang, now: now)
  }

  /// 90 min after Dhuhr started (the count-up window long closed) → resting countdown
  /// to Asr, with the always-on "since previous prayer" treatment: Small shows
  /// "Dhuhr since: 1:30"; Medium/Large show the un-dimmed Dhuhr row carrying
  /// "+1:30". Mirrors the user's example and exercises the h:mm since tier.
  static func since(_ lang: PreviewLang = .en, now: Date = Date()) -> SalahDisplay {
    make(
      prayers: [
        Spec(id: .fajr, offset: -10 * 60, pre: 30),
        Spec(id: .sunrise, offset: -8 * 60, alert: false),
        Spec(id: .dhuhr, offset: -90),
        Spec(id: .asr, offset: 100, pre: 10),
        Spec(id: .maghrib, offset: 5 * 60, pre: 10, post: 5),
        Spec(id: .isha, offset: 7 * 60),
      ], lang: lang, now: now)
  }

  /// After Isha → all today prayers passed, focus is tomorrow's Fajr (after midnight).
  static func tomorrow(_ lang: PreviewLang = .en, now: Date = Date()) -> SalahDisplay {
    make(
      prayers: [
        Spec(id: .fajr, offset: -16 * 60),
        Spec(id: .sunrise, offset: -14 * 60, alert: false),
        Spec(id: .dhuhr, offset: -9 * 60),
        Spec(id: .asr, offset: -5 * 60),
        Spec(id: .maghrib, offset: -2 * 60),
        Spec(id: .isha, offset: -30),
      ],
      tomorrowFajrOffset: 18 * 60, lang: lang, now: now)
  }
}

/// The previews' published days: the scenario's events, and nothing else. A day
/// without all six kinds is partial, the rest missing as unpublished.
nonisolated struct PreviewSource: PrayerSource {
  let days: [CivilDay: [PrayerEvent]]

  var expectedKinds: Set<PrayerKind> { Set(PrayerKind.allCases) }
  var maximumLead: Duration { .zero }

  func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
    guard let events = days[day], !events.isEmpty else { return .unavailable(.noPublishedData) }
    let missing = expectedKinds.subtracting(events.map(\.kind))
    return .available(
      PrayerDay(day: day, timeZone: location.timeZone, events: events),
      coverage: missing.isEmpty
        ? .complete
        : .partial(
          missing: Dictionary(uniqueKeysWithValues: missing.map { ($0, .noPublishedData) })))
  }
}

#Preview("Idle · dark") {
  WidgetSizeGallery(title: "Idle", display: WidgetPreviewData.idle()).preferredColorScheme(.dark)
}

#Preview("Idle · light") {
  WidgetSizeGallery(title: "Idle", display: WidgetPreviewData.idle()).preferredColorScheme(.light)
}

#Preview("Imminent · dark") {
  WidgetSizeGallery(title: "Imminent", display: WidgetPreviewData.imminent()).preferredColorScheme(
    .dark)
}

#Preview("Count-up · dark") {
  WidgetSizeGallery(title: "Count-up", display: WidgetPreviewData.countUp()).preferredColorScheme(
    .dark)
}

#Preview("Count-up ended · dark") {
  WidgetSizeGallery(
    title: "Count-up ended → next prayer", display: WidgetPreviewData.countUpEnded()
  )
  .preferredColorScheme(.dark)
}

#Preview("Since previous · dark") {
  WidgetSizeGallery(title: "Since previous prayer (resting)", display: WidgetPreviewData.since())
    .preferredColorScheme(.dark)
}

#Preview("Arabic since previous · dark") {
  WidgetSizeGallery(title: "Arabic since previous prayer", display: WidgetPreviewData.since(.ar))
    .preferredColorScheme(.dark)
}

#Preview("Tomorrow · dark") {
  WidgetSizeGallery(title: "Tomorrow", display: WidgetPreviewData.tomorrow()).preferredColorScheme(
    .dark)
}

#Preview("Silent · dark") {
  WidgetSizeGallery(title: "Silent", display: WidgetPreviewData.silent()).preferredColorScheme(
    .dark)
}

#Preview("Stop · dark") {
  WidgetSizeGallery(title: "Stop", display: WidgetPreviewData.playing()).preferredColorScheme(
    .dark)
}

#Preview("Arabic · dark") {
  WidgetSizeGallery(title: "Arabic", display: WidgetPreviewData.idle(.ar)).preferredColorScheme(
    .dark)
}

#Preview("Arabic count-up · dark") {
  WidgetSizeGallery(title: "Arabic count-up", display: WidgetPreviewData.countUp(.ar))
    .preferredColorScheme(.dark)
}

#Preview("French · dark") {
  WidgetSizeGallery(title: "French", display: WidgetPreviewData.idle(.fr)).preferredColorScheme(
    .dark)
}

// Magnified single small widget, to judge vertical spacing closely.
#Preview("Small ×2 · dark") {
  WidgetPreviewContainer(display: WidgetPreviewData.idle(), size: .small)
    .scaleEffect(2)
    .frame(width: 360, height: 360)
    .preferredColorScheme(.dark)
}

// Every time of day at medium, to check each sky and its marks.
#Preview("Times of day · light") {
  VStack(spacing: 14) {
    ForEach(PreviewLang.allCases, id: \.self) { lang in
      WidgetPreviewContainer(display: WidgetPreviewData.idle(lang), size: .medium)
    }
  }
  .padding(20)
  .preferredColorScheme(.light)
}
