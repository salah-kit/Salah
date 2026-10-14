import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import SalahWidgets
import Testing

/// The settings mirror the widget extension builds from (proposal §10, step 1): what
/// the app publishes, when, and what the widget draws from it. These are the parity
/// assertions of the move onto SalahKit: initial publication, a language-only change,
/// the Hijri offset, reminder summaries, Friday overrides and the playing banner.
@Suite("Settings mirror")
struct SettingsMirrorTests {
  init() { TestEnvironment.configure() }

  // MARK: - Publication

  /// At launch the mirror saves the settings and asks the widget to reload; a later
  /// launch with the same settings saves nothing and spends no reload.
  @Test func initialPublicationSavesOnceAndReloadsOnlyOnChange() throws {
    let group = MirrorGroup()
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)

    group.mirror().start(preferences: preferences)
    #expect(group.settings.load() == preferences.mirroredSettings)
    #expect(group.reloads.kinds == [[SalahWidgetConstants.prayerTimesWidgetKind]])

    group.mirror().start(preferences: preferences)
    #expect(group.reloads.kinds.count == 1)
  }

  /// A language-only change (`.localization`) republishes at once: the widget draws the
  /// same times in the new language, with its names, digits and direction.
  @Test func aLanguageOnlyChangeRepublishes() throws {
    let group = MirrorGroup()
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.appLanguage = .english
    let mirror = group.mirror()
    mirror.start(preferences: preferences)
    let english = try #require(group.settings.load())

    preferences.appLanguage = .arabic
    let arabic = try #require(group.settings.load())
    #expect(arabic.language == .arabic)
    #expect(arabic.calculation == english.calculation && arabic.location == english.location)
    #expect(group.reloads.kinds.count == 2)

    let at = Fixture.date(13, 0)
    let before = SalahDisplay(date: at, settings: english, schedule: english.schedule)
    let after = SalahDisplay(date: at, settings: arabic, schedule: arabic.schedule)
    #expect(before.listedDay == after.listedDay)
    let dhuhr = Fixture.event(.dhuhr)
    #expect(before.name(of: dhuhr) == "Dhuhr")
    #expect(after.name(of: dhuhr) == "الظهر")
    #expect(before.timeText(of: dhuhr) == "\u{2068}12:19\u{202F}PM\u{2069}")
    #expect(after.timeText(of: dhuhr) == "\u{2068}١٢:١٩\u{00A0}م\u{2069}")
    #expect(!before.isRightToLeft && after.isRightToLeft)
    #expect(after.labels == .arabic)
  }

  /// Changes without a mirrored effect publish nothing.
  @Test func audioOnlyChangesPublishNothing() throws {
    let group = MirrorGroup()
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    let mirror = group.mirror()
    mirror.start(preferences: preferences)
    preferences.alertVolume = 30
    preferences.duaEnabled = false
    #expect(group.reloads.kinds.count == 1)
    // The mirror was listening: a mirrored change after them publishes.
    preferences.silentMode = true
    #expect(group.settings.load()?.silentMode == true)
    withExtendedLifetime(mirror) {}
  }

  /// The Hijri offset (`.display`) is mirrored: it moves the header's Hijri date and
  /// Ramadan's delayed Isha.
  @Test func theHijriOffsetIsMirrored() throws {
    let group = MirrorGroup()
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.appLanguage = .english
    let mirror = group.mirror()
    mirror.start(preferences: preferences)
    defer { withExtendedLifetime(mirror) {} }

    var days: [String] = []
    for offset in [-1, 0, 1] {
      preferences.hijriOffset = offset
      let settings = try #require(group.settings.load())
      #expect(settings.hijriOffset == offset)
      #expect(
        settings.calculation.parameters.ramadanIsha
          == .interval(minutes: 120, hijriDayOffset: offset))
      days.append(SalahHeader(date: Fixture.date(13, 0), settings: settings).hijriDay)
    }
    #expect(days == ["15", "16", "17"])
    let header = SalahHeader(
      date: Fixture.date(13, 0), settings: try #require(group.settings.load()))
    #expect(header.hijriMonth == "Dhuʻl-Hijjah" && header.hijriYear == "1447 H")
  }

  /// The location's name and the theme come from the preferences.
  @Test func locationAndThemeComeFromPreferences() throws {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.city = ""
    preferences.countryName = "Saudi Arabia"
    preferences.widgetThemeID = "dawn"
    let settings = preferences.mirroredSettings
    #expect(settings.location.name == "Saudi Arabia")
    #expect(settings.location.timeZone.identifier == "Asia/Riyadh")
    #expect(settings.theme == SalahWidgetTheme.dawn)
  }

  // MARK: - Reminder summaries

  /// Plain data, because Swift Testing builds arguments outside the main actor.
  nonisolated struct SummaryCase: Sendable, CustomTestStringConvertible {
    var language: String
    var summary: String
    var detail: String
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

  /// The reminder text the widget and the menu bar show, in each language's word order,
  /// as the app's snapshot builder wrote it before the move.
  @Test(arguments: [
    SummaryCase(
      language: "en",
      summary: "Alert on · \u{2068}10m\u{2069} before · \u{2068}5m\u{2069} after",
      detail: "\u{2068}10m\u{2069} before · \u{2068}5m\u{2069} after",
      alertOff: "Alert off", silent: "Silent"),
    SummaryCase(
      language: "ar",
      summary: "تنبيه مُفعّل · قبل \u{2068}١٠ د\u{2069} · بعد \u{2068}٥ د\u{2069}",
      detail: "قبل \u{2068}١٠ د\u{2069} · بعد \u{2068}٥ د\u{2069}",
      alertOff: "تنبيه مُعطّل", silent: "صامت"),
    SummaryCase(
      language: "fr",
      summary: "Alerte activée · \u{2068}10 min\u{2069} avant · \u{2068}5 min\u{2069} après",
      detail: "\u{2068}10 min\u{2069} avant · \u{2068}5 min\u{2069} après",
      alertOff: "Alerte désactivée", silent: "Silencieux"),
  ])
  func reminderSummaries(_ expected: SummaryCase) throws {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.appLanguage = Self.appLanguage(expected.language)
    preferences.setConfig(.alert(before: 10, after: 5), for: .maghrib)
    let settings = preferences.mirroredSettings
    let display = SalahDisplay(
      date: Fixture.date(13, 0), settings: settings, schedule: settings.schedule)

    let maghrib = Fixture.event(.maghrib)
    #expect(
      display.alerts(for: maghrib) == PrayerAlerts(alert: true, beforeMinutes: 10, afterMinutes: 5))
    #expect(display.reminderDetail(for: maghrib) == expected.detail)
    #expect(
      display.text.reminderSummary(display.alerts(for: maghrib), silentMode: false)
        == expected.summary)
    let sunrise = Fixture.event(.sunrise)
    #expect(
      display.text.reminderSummary(display.alerts(for: sunrise), silentMode: false)
        == expected.alertOff)
    #expect(display.reminderDetail(for: sunrise) == nil)
    // Silent mode leads every summary with "Silent", whatever the alert setting.
    #expect(
      PrayerKind.allCases.allSatisfy {
        display.text.reminderSummary(display.alerts(for: Fixture.event($0)), silentMode: true)
          .hasPrefix(expected.silent)
      })
  }

  // MARK: - Friday and the Jumu'ah override

  /// On Friday in the prayer time zone Dhuhr is named Jumu'ah, in every language;
  /// other days it's Dhuhr.
  @Test func fridayDhuhrIsNamedJumuah() throws {
    let friday = Fixture.event(.dhuhr, dayOffset: 3)  // Friday 5 June 2026
    #expect(friday.observance == .jumuah)
    #expect(Fixture.event(.dhuhr).observance == .ordinary)
    for (language, name) in [
      (AppLanguage.english, "Jumuah"), (.arabic, "الجمعة"), (.french, "Joumouah"),
    ] {
      let scratch = ScratchDefaults()
      let preferences = Preferences(defaults: scratch.defaults)
      preferences.appLanguage = language
      let settings = preferences.mirroredSettings
      let display = SalahDisplay(
        date: Fixture.date(9, 0, dayOffset: 3), settings: settings, schedule: settings.schedule)
      #expect(display.name(of: friday) == name)
      #expect(display.listedDay?[.dhuhr] == friday)
    }
    #expect(PrayerNames(locale: Locale(identifier: "en")).abbreviation(of: friday) == "J")
  }

  /// With the override on, Friday's Dhuhr uses the Jumu'ah settings; other days keep
  /// Dhuhr's own, and with the override off Friday does too.
  @Test func theJumuahOverrideAppliesOnFridayOnly() throws {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.setConfig(.alert(), for: .dhuhr)
    preferences.jumuahOverrideEnabled = true
    preferences.setJumuahConfig(.alert(before: 20))
    let settings = preferences.mirroredSettings
    #expect(settings.jumuahAlerts == PrayerAlerts(alert: true, beforeMinutes: 20))
    #expect(settings.alerts(for: Fixture.event(.dhuhr, dayOffset: 3)).beforeMinutes == 20)
    #expect(settings.alerts(for: Fixture.event(.dhuhr)).beforeMinutes == nil)

    preferences.jumuahOverrideEnabled = false
    #expect(preferences.mirroredSettings.jumuahAlerts == nil)
    #expect(
      preferences.mirroredSettings.alerts(for: Fixture.event(.dhuhr, dayOffset: 3)).beforeMinutes
        == nil)
  }

  // MARK: - Playing

  /// Plain data, because Swift Testing builds arguments outside the main actor.
  nonisolated struct PlayingCase: Sendable, CustomTestStringConvertible {
    var dua = false
    var slot: String
    var offset: Int?
    var title: String
    var subtitleSuffix: String
    var testDescription: String { dua ? "dua" : slot }
  }

  /// What plays reaches the widget as `SalahPlayback`; the playing banner's title and
  /// subtitle per slot are the ones the app's snapshot builder wrote before the move.
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
  func playingBanner(_ playing: PlayingCase) throws {
    let maghrib = Fixture.event(.maghrib)
    let context = AudioPlaybackContext(
      source: playing.dua ? .dua : .prayerAlert,
      slot: PrayerNotificationSoundSlot(rawValue: playing.slot), event: maghrib,
      prayerAlertOffsetMinutes: playing.offset)
    let playback = try #require(SalahPlayback(.playing(context)))
    #expect(playback.event == maghrib && playback.isDua == playing.dua)

    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.appLanguage = .english
    let settings = preferences.mirroredSettings
    let display = SalahDisplay(
      date: maghrib.time.adding(minutes: 1), settings: settings, schedule: settings.schedule,
      playback: playback)
    let suffix =
      playing.subtitleSuffix == "TIME"
      ? Fixture.formattedTime(maghrib.time) : playing.subtitleSuffix
    #expect(display.playingTitle == playing.title)
    #expect(display.playingSubtitle == "Maghrib · \(suffix)")
    #expect(display.rowState(for: maghrib, status: .justStarted) == .active(playback.tone))
  }

  /// Previewing a sound in Settings isn't an alert, and an idle controller plays
  /// nothing: no banner.
  @Test func soundPreviewAndIdleShowNoBanner() {
    #expect(SalahPlayback(.playing(AudioPlaybackContext(prayer: .fajr, source: .preview))) == nil)
    #expect(SalahPlayback(.idle) == nil)
  }

  /// What's playing is published and cleared, and the widget reloads each time.
  @Test func playbackIsPublishedAndCleared() throws {
    let group = MirrorGroup()
    let mirror = group.mirror()
    let playback = SalahPlayback(event: Fixture.event(.maghrib), slot: .alert)
    #expect(mirror.publish(playback: playback))
    #expect(group.playback.load() == playback)
    #expect(!mirror.publish(playback: playback))
    #expect(mirror.publish(playback: nil))
    #expect(group.playback.load() == nil)
    #expect(group.reloads.kinds.count == 2)
  }
}

/// An App Group of its own for one test: a defaults suite named by a path in this run's
/// preferences folder, whose widget reloads are recorded.
final class MirrorGroup {
  let suite: String
  let reloads = ReloadRecorder()
  let settings: SharedValue<SalahSettings>
  let playback: SharedValue<SalahPlayback>

  init() {
    suite = TestEnvironment.preferencesDirectory.appending(path: "group-\(UUID().uuidString)").path
    let reloads = reloads
    settings = SharedValue(
      appGroup: suite, key: SalahWidgetConstants.settingsKey,
      reloadTimelines: { reloads.record($0) })
    playback = SharedValue(
      appGroup: suite, key: SalahWidgetConstants.playbackKey,
      reloadTimelines: { reloads.record($0) })
  }

  deinit {
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }

  /// A mirror over this group, whose explicit reloads are recorded too.
  func mirror() -> WidgetMirror {
    let reloads = reloads
    return WidgetMirror(
      settings: settings, playback: playback,
      reloadWidgetTimelines: { reloads.record(["all"]) })
  }
}

/// The widget kinds each reload asked for, in order. Lock-protected, because
/// `SharedValue` calls it from whatever thread saved.
nonisolated final class ReloadRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [[String]] = []

  func record(_ kinds: [String]) {
    lock.withLock { recorded.append(kinds) }
  }

  var kinds: [[String]] { lock.withLock { recorded } }
}
