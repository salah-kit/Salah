import Foundation
import SalahCore

/// One of the Top Shelf's banners, above the app row while Salah's icon has focus.
nonisolated enum TopShelfBanner: String, CaseIterable, Sendable {
  case nextPrayer, today, roomDisplay

  /// Where pressing the banner goes in the app.
  var url: URL {
    switch self {
    case .nextPrayer, .today: TVRoute.today.url
    case .roomDisplay: TVRoute.roomDisplay.url
    }
  }
}

/// The links the Top Shelf and the app agree on: `salah://today`, `salah://room`.
nonisolated enum TVRoute: String, CaseIterable, Sendable {
  case today
  case week
  case settings
  case roomDisplay = "room"

  var url: URL {
    var components = URLComponents()
    components.scheme = SalahWidgetConstants.deepLinkScheme
    components.host = rawValue
    // The scheme and host are constants, so the URL always forms.
    return components.url ?? URL(fileURLWithPath: "/")
  }

  init?(url: URL) {
    guard url.scheme?.lowercased() == SalahWidgetConstants.deepLinkScheme,
      let host = url.host?.lowercased(), let route = Self(rawValue: host)
    else { return nil }
    self = route
  }
}

/// What the Top Shelf draws at one moment, from the settings the app mirrors.
///
/// The extension has no clock running: each image shows the times as they are when the
/// system asks for them, never a ticking countdown.
nonisolated struct TopShelfSnapshot: Sendable {
  let display: SalahDisplay
  let isDark: Bool

  /// The snapshot at `date`, or `nil` when Salah has no location yet or the day's times
  /// aren't known: the system shows the static Top Shelf image then.
  init?(settings: SalahSettings?, date: Date, isDark: Bool) {
    guard let settings else { return nil }
    let display = SalahDisplay(date: date, settings: settings, schedule: settings.schedule)
    guard display.listedDay != nil else { return nil }
    self.display = display
    self.isDark = isDark
  }

  var copy: TVCopy { TVCopy(locale: display.locale) }
  var time: TVTimeText {
    TVTimeText(locale: display.locale, timeZone: display.settings.location.timeZone)
  }

  /// The next prayer, sunrise left out, while the schedule knows it.
  var nextPrayer: PrayerEvent? { display.prayerState?.nextPrayer }

  /// The banners, in order. The next prayer's needs a known next prayer.
  var banners: [TopShelfBanner] {
    nextPrayer == nil ? [.today, .roomDisplay] : TopShelfBanner.allCases
  }

  /// The time of day a banner's sky draws in: the period the next prayer opens, the period
  /// now, and night for the room display, which suits a dark room.
  func phase(of banner: TopShelfBanner) -> SalahPhase {
    guard display.settings.followsTimeOfDay else {
      return banner == .roomDisplay ? .isha : .neutral
    }
    switch banner {
    case .nextPrayer:
      guard let next = nextPrayer, let day = display.listedDay else { return display.phase }
      return SalahPhase.at(next.time, events: day.events + [next])
    case .today: return display.phase
    case .roomDisplay: return .isha
    }
  }

  /// The place the banners name: the city, or nothing when it has no name.
  var place: String { display.header.location }

  /// Whether the next prayer is on a later day than the listed one, such as tomorrow's Fajr
  /// after Isha. It's already true while Isha counts up, when the app asks for new images.
  var nextPrayerIsTomorrow: Bool {
    guard let next = nextPrayer, let day = display.listedDay else { return false }
    return next.scheduleDay > day.day
  }

  /// The day a banner lists. After Isha the next prayer's banner lists tomorrow, the day
  /// that prayer is in, as the widgets do; the others list today.
  func day(of banner: TopShelfBanner) -> PrayerDay? {
    listsTomorrow(banner) ? display.nextDay : display.listedDay
  }

  /// A banner's day's events in order, sunrise included.
  func events(of banner: TopShelfBanner) -> [PrayerEvent] {
    day(of: banner)?.events.sorted { $0.time < $1.time } ?? []
  }

  /// A banner's day in canonical order: each expected kind's event, or the kind alone where
  /// the schedule couldn't give its time. The room display leaves sunrise out.
  func slots(of banner: TopShelfBanner) -> [SalahDisplay.Slot] {
    guard let day = day(of: banner) else { return [] }
    let slots: [SalahDisplay.Slot] = display.settings.schedule.source.expectedKinds.sorted()
      .map { kind in
        day[kind].map(SalahDisplay.Slot.event) ?? .missing(kind)
      }
    return banner == .roomDisplay ? slots.filter(\.kind.isPrayer) : slots
  }

  /// A slot's prayer name: Jumu'ah on a declared Friday.
  func name(of slot: SalahDisplay.Slot) -> String {
    switch slot {
    case .event(let event): display.name(of: event)
    case .missing(let kind): display.name(of: kind)
    }
  }

  /// What a banner shows in place of a time the schedule couldn't give.
  static let missingTime = "—"

  /// "Tuesday, June 2 · 16 Dhuʻl-Hijjah 1447": the date of the day a banner lists.
  func dateLine(of banner: TopShelfBanner) -> String {
    let date =
      listsTomorrow(banner)
      ? display.nextDay.map { $0.day.start(in: $0.timeZone) } ?? display.date : display.date
    let gregorian = time.date(date, template: "EEEEMMMMd")
    let hijri = time.hijri(date, offset: display.settings.hijriOffset)
    return "\(gregorian) · \(hijri)"
  }

  private func listsTomorrow(_ banner: TopShelfBanner) -> Bool {
    banner == .nextPrayer && nextPrayerIsTomorrow && display.nextDay != nil
  }

  func eyebrow(of banner: TopShelfBanner) -> String {
    let lead: String
    switch banner {
    // After Isha the next prayer is tomorrow's Fajr, which the app's hero calls Tomorrow too.
    case .nextPrayer:
      lead = nextPrayerIsTomorrow ? display.labels.tomorrow : display.labels.nextPrayer
    case .today: lead = copy("Today", "اليوم")
    case .roomDisplay: return copy("Room display", "عرض الغرفة")
    }
    return place.isEmpty ? lead : "\(lead) · \(place)"
  }

  func title(of banner: TopShelfBanner) -> String {
    switch banner {
    case .nextPrayer:
      guard let next = nextPrayer else { return copy("Today’s prayers", "صلوات اليوم") }
      return copy.format("%1$@ at %2$@", "%1$@ %2$@", display.name(of: next), time.time(next.time))
    case .today: return copy("Today’s prayers", "صلوات اليوم")
    case .roomDisplay: return copy("Today’s times, all day", "أوقات اليوم طوال اليوم")
    }
  }

  /// What the room display banner says under its title.
  var roomDisplayNote: String {
    copy(
      "Keep the day’s prayer times on screen at home or in a musalla.",
      "أبقِ أوقات الصلاة على الشاشة في البيت أو في المصلى.")
  }

  /// The text the system reads for a banner, and its item's title.
  func accessibilityTitle(of banner: TopShelfBanner) -> String {
    switch banner {
    case .nextPrayer, .roomDisplay: return "\(eyebrow(of: banner)), \(title(of: banner))"
    case .today:
      let times: [String] = slots(of: .today).map { slot in
        switch slot {
        case .event(let event): "\(name(of: slot)) \(time.time(event.time))"
        case .missing: "\(name(of: slot)) \(copy("Not available", "غير متاح"))"
        }
      }
      return ([eyebrow(of: banner), title(of: banner)] + times).joined(separator: ", ")
    }
  }

  /// The build number, so an update never reuses the images an earlier build drew.
  private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""

  /// Changes whenever a banner's image would, so the system never keeps an image of other
  /// times, another language, the other appearance or an earlier build.
  func fingerprint(of banner: TopShelfBanner) -> String {
    var parts = [
      banner.rawValue, isDark ? "dark" : "light", display.locale.identifier, Self.build,
      String(display.settings.hijriOffset), String(display.settings.followsTimeOfDay),
      place, String(describing: phase(of: banner)), eyebrow(of: banner), title(of: banner),
      dateLine(of: banner), nextPrayer?.id ?? "",
    ]
    parts += slots(of: banner).map { slot in
      switch slot {
      case .event(let event):
        "\(event.kind.rawValue)\(event.observance)\(event.time.timeIntervalSince1970)"
      case .missing(let kind): "\(kind.rawValue)-missing"
      }
    }
    // The Today banner's ribbon moves its knob through the day.
    if banner == .today { parts.append(String(Int(display.date.timeIntervalSince1970 / 600))) }
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in parts.joined(separator: "|").utf8 {
      hash = (hash ^ UInt64(byte)) &* 0x0100_0000_01b3
    }
    return String(hash, radix: 16)
  }
}
