import Adhan
import Foundation
import Testing

/// Characterizes the snapshot the app publishes (`GuidanceWidgetSnapshotBuilder`):
/// the app-side inputs D1's settings mirror must reproduce (§10 parity: reminder
/// summaries, Friday overrides, the Hijri offset, a language-only change).
@Suite("Widget snapshot builder")
struct WidgetSnapshotBuilderTests {
  init() { TestEnvironment.configure() }

  /// Builds today's snapshot as `PrayerManager.publishWidgetSnapshot` does, from
  /// scratch preferences. The builder's formatter reads `Locale.app`, so the shared
  /// preferences take the same language for the duration.
  static func build(
    at now: Date,
    dayOffset: Int = 0,
    audio: AudioPlaybackState = .idle,
    _ configure: (Preferences) -> Void = { _ in }
  ) -> GuidanceWidgetSnapshot? {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.appLanguage = .english
    configure(preferences)
    let today = Fixture.prayerTimes(dayOffset: dayOffset)
    return AppLanguageScope.with(preferences.appLanguage) {
      GuidanceWidgetSnapshotBuilder(
        preferences: preferences, prayerTimes: today,
        tomorrowPrayerTimes: Fixture.prayerTimes(dayOffset: dayOffset + 1),
        currentPrayer: today.currentPrayer(at: now), nextPrayer: today.nextPrayer(at: now),
        audioState: audio, now: now
      ).build()
    }
  }

  // MARK: - Reminder summaries

  /// Plain data, because Swift Testing builds arguments outside the main actor.
  nonisolated struct SummaryCase: Sendable, CustomTestStringConvertible {
    var language: String
    var summary: String
    var detail: String
    var short: String
    var alertOff: String
    var silent: String
    var testDescription: String { language }
  }

  static func appLanguage(_ code: String) -> AppLanguage {
    switch code {
    case "ar": .arabic
    case "fr": .french
    default: .english
    }
  }

  @Test(arguments: [
    SummaryCase(
      language: "en",
      summary: "Alert on · \u{2068}10m\u{2069} before · \u{2068}5m\u{2069} after",
      detail: "\u{2068}10m\u{2069} before · \u{2068}5m\u{2069} after",
      short: "\u{2068}10m\u{2069}", alertOff: "Alert off", silent: "Silent"),
    SummaryCase(
      language: "ar",
      summary: "تنبيه مُفعّل · قبل \u{2068}١٠ د\u{2069} · بعد \u{2068}٥ د\u{2069}",
      detail: "قبل \u{2068}١٠ د\u{2069} · بعد \u{2068}٥ د\u{2069}",
      short: "\u{2068}١٠ د\u{2069}", alertOff: "تنبيه مُعطّل", silent: "صامت"),
    SummaryCase(
      language: "fr",
      summary: "Alerte activée · \u{2068}10 min\u{2069} avant · \u{2068}5 min\u{2069} après",
      detail: "\u{2068}10 min\u{2069} avant · \u{2068}5 min\u{2069} après",
      short: "\u{2068}10 min\u{2069}", alertOff: "Alerte désactivée", silent: "Silencieux"),
  ])
  func reminderSummaries(_ expected: SummaryCase) throws {
    let snapshot = try #require(
      Self.build(at: Fixture.date(13, 0)) {
        $0.appLanguage = Self.appLanguage(expected.language)
        $0.setConfig(.alert(before: 10, after: 5), for: .maghrib)
      })
    let maghrib = try #require(snapshot.prayer(id: "maghrib"))
    #expect(maghrib.reminderSummaryText == expected.summary)
    #expect(maghrib.reminderDetailText == expected.detail)
    #expect(maghrib.preReminderShortText == expected.short)
    #expect(maghrib.preReminderMinutes == 10)
    #expect(maghrib.postReminderMinutes == 5)
    #expect(snapshot.prayer(id: "sunrise")?.reminderSummaryText == expected.alertOff)
    #expect(snapshot.prayer(id: "sunrise")?.reminderDetailText == nil)

    // Silent mode leads every summary with "Silent", whatever the alert setting.
    let silent = try #require(
      Self.build(at: Fixture.date(13, 0)) {
        $0.appLanguage = Self.appLanguage(expected.language)
        $0.silentMode = true
      })
    #expect(silent.prayers.allSatisfy { $0.reminderSummaryText == expected.silent })
  }

  // MARK: - Language

  /// A language-only change rebuilds every string, the locale and the direction;
  /// the times stay.
  @Test func languageOnlyChangeRebuildsTheStrings() throws {
    let english = try #require(Self.build(at: Fixture.date(13, 0)))
    let arabic = try #require(Self.build(at: Fixture.date(13, 0)) { $0.appLanguage = .arabic })
    let french = try #require(Self.build(at: Fixture.date(13, 0)) { $0.appLanguage = .french })

    #expect(english.prayers.map(\.time) == arabic.prayers.map(\.time))
    #expect(english.prayers.map(\.name) == ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"])
    #expect(
      arabic.prayers.map(\.name) == ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"])
    #expect(
      french.prayers.map(\.name) == ["Fajr", "Lever du soleil", "Dhuhr", "Asr", "Maghrib", "Isha"])
    #expect(english.prayers.map(\.abbreviation) == ["F", "S", "D", "A", "M", "I"])

    #expect(english.localeIdentifier == "en")
    #expect(arabic.localeIdentifier == "ar@numbers=arab")
    #expect(french.localeIdentifier == "fr")
    #expect(
      !english.layoutDirectionIsRTL && arabic.layoutDirectionIsRTL && !french.layoutDirectionIsRTL)
    #expect(english.labels == .english && arabic.labels == .arabic && french.labels == .french)

    #expect(english.prayer(id: "dhuhr")?.timeText == "\u{2068}12:19\u{202F}PM\u{2069}")
    #expect(english.prayer(id: "dhuhr")?.compactTimeText == "\u{2068}12:19\u{2069}")
    #expect(french.prayer(id: "dhuhr")?.timeText == "\u{2068}12:19\u{2069}")
    #expect(english.gregorianDateText == "Tuesday, June 2, 2026")
    #expect(french.gregorianDateText == "mardi 2 juin 2026")
    #expect(
      [english.hijriDay, english.hijriMonth, english.hijriYear] == ["16", "Dhuʻl-Hijjah", "1447 H"])
    #expect([arabic.hijriDay, arabic.hijriYear] == ["١٦", "١٤٤٧ هـ"])
    #expect(english.locationName == "Makkah")
  }

  // MARK: - Friday and the Jumu'ah override

  /// On Friday in the prayer time zone Dhuhr is named Jumu'ah, in every language.
  @Test func fridayDhuhrIsNamedJumuah() throws {
    // Friday 5 June 2026.
    let friday = try #require(Self.build(at: Fixture.date(9, 0, dayOffset: 3), dayOffset: 3))
    #expect(friday.prayer(id: "dhuhr")?.name == "Jumuah")
    #expect(friday.prayer(id: "dhuhr")?.abbreviation == "J")
    let arabic = try #require(
      Self.build(at: Fixture.date(9, 0, dayOffset: 3), dayOffset: 3) { $0.appLanguage = .arabic })
    #expect(arabic.prayer(id: "dhuhr")?.name == "الجمعة")
    let french = try #require(
      Self.build(at: Fixture.date(9, 0, dayOffset: 3), dayOffset: 3) { $0.appLanguage = .french })
    #expect(french.prayer(id: "dhuhr")?.name == "Joumouah")
  }

  /// With the override on, Friday's Dhuhr uses the Jumu'ah settings; other days
  /// keep Dhuhr's own.
  @Test func jumuahOverrideAppliesOnFridayOnly() throws {
    func configure(_ preferences: Preferences) {
      preferences.setConfig(.alert(), for: .dhuhr)
      preferences.jumuahOverrideEnabled = true
      preferences.setJumuahConfig(.alert(before: 20))
    }
    let friday = try #require(
      Self.build(at: Fixture.date(9, 0, dayOffset: 3), dayOffset: 3, configure))
    let tuesday = try #require(Self.build(at: Fixture.date(9, 0), configure))
    #expect(friday.prayer(id: "dhuhr")?.preReminderMinutes == 20)
    #expect(tuesday.prayer(id: "dhuhr")?.preReminderMinutes == nil)
  }

  // MARK: - Hijri offset, location, theme

  @Test func hijriOffsetShiftsTheHijriDate() throws {
    let days = try [-1, 0, 1].map { offset in
      try #require(Self.build(at: Fixture.date(13, 0)) { $0.hijriOffset = offset }).hijriDay
    }
    #expect(days == ["15", "16", "17"])
  }

  @Test func locationAndThemeComeFromPreferences() throws {
    let snapshot = try #require(
      Self.build(at: Fixture.date(13, 0)) {
        $0.city = ""
        $0.countryName = "Saudi Arabia"
        $0.widgetThemeID = "dawn"
      })
    #expect(snapshot.locationName == "Saudi Arabia")
    #expect(snapshot.theme == GuidanceWidgetTheme.dawn)
  }

  @Test func noPrayerTimesMeansNoSnapshot() {
    let scratch = ScratchDefaults()
    let builder = GuidanceWidgetSnapshotBuilder(
      preferences: Preferences(defaults: scratch.defaults), prayerTimes: nil,
      tomorrowPrayerTimes: nil, currentPrayer: nil, nextPrayer: nil, audioState: .idle)
    #expect(builder.build() == nil)
  }

  // MARK: - Playing audio

  /// Plain data, because Swift Testing builds arguments outside the main actor.
  nonisolated struct PlayingCase: Sendable, CustomTestStringConvertible {
    var dua = false
    var slot: String
    var offset: Int?
    var title: String
    var subtitleSuffix: String
    var testDescription: String { dua ? "dua" : slot }
  }

  /// The playing banner's title and subtitle per slot; the menu bar and the widget's
  /// stop control show these.
  @Test(arguments: [
    PlayingCase(slot: "alert", offset: nil, title: "Playing Adhan", subtitleSuffix: "TIME"),
    PlayingCase(
      dua: true, slot: "alert", offset: nil, title: "Playing Du’ā’", subtitleSuffix: "TIME"),
    PlayingCase(
      slot: "preReminder", offset: 10, title: "Pre-reminder",
      subtitleSuffix: "\u{2068}10m\u{2069} before"),
    PlayingCase(
      slot: "postReminder", offset: 5, title: "Post-reminder",
      subtitleSuffix: "\u{2068}5m\u{2069} after"),
  ])
  func activeAlertBanner(_ playing: PlayingCase) throws {
    let maghrib = Fixture.prayerTimes().maghrib
    let context = AudioPlaybackContext(
      prayer: .maghrib, source: playing.dua ? .dua : .prayerAlert,
      slot: PrayerNotificationSoundSlot(rawValue: playing.slot), prayerTime: maghrib,
      prayerAlertOffsetMinutes: playing.offset)
    let snapshot = try #require(
      Self.build(at: maghrib.adding(minutes: 1), audio: .playing(context)))
    let alert = try #require(snapshot.activeAlert)
    let suffix =
      playing.subtitleSuffix == "TIME" ? Fixture.formattedTime(maghrib) : playing.subtitleSuffix
    #expect(alert.prayerID == "maghrib")
    #expect(alert.title == playing.title)
    #expect(alert.subtitle == "Maghrib · \(suffix)")
    #expect(alert.offsetMinutes == playing.offset)
  }

  /// Previewing a sound in Settings isn't an alert: no banner.
  @Test func soundPreviewShowsNoBanner() throws {
    let context = AudioPlaybackContext(source: .preview)
    let snapshot = try #require(Self.build(at: Fixture.date(13, 0), audio: .playing(context)))
    #expect(snapshot.activeAlert == nil)
  }
}

/// Runs `body` with `Preferences.shared`, and so `Locale.app`, in `language`, then
/// restores the previous language. Synchronous, so no other test sees the change.
enum AppLanguageScope {
  static func with<T>(_ language: AppLanguage, _ body: () throws -> T) rethrows -> T {
    let shared = Preferences.shared
    let previous = shared.appLanguage
    shared.appLanguage = language
    defer { shared.appLanguage = previous }
    return try body()
  }
}
