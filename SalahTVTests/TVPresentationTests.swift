import Foundation
import SalahCore
import SalahTimes
import Testing

@Suite("Apple TV wording and numerals", .serialized)
@MainActor
struct TVPresentationTests {
  init() { TVTestResources.use() }

  @Test func theHeroCountsDownToTheNextPrayer() {
    let presentation = TVFixtures.presentation(at: "2026-06-02T13:19:00+03:00")
    #expect(presentation.eyebrow == "Next prayer")
    #expect(presentation.name == "Asr")
    #expect(plain(presentation.subtitle) == "Begins at 3:35 PM")
    #expect(presentation.countdown == "2:16:00")
    #expect(!presentation.isApproaching)
    let note = presentation.soundNote
    #expect(note.map { plain($0.text) } == "Adhan at 3:35 PM while Salah is open")
    #expect(note?.isOn == true)
    #expect(
      plain(presentation.heroAccessibility)
        == "Next prayer, Asr, Begins at 3:35 PM, in 2 hours, 16 minutes, "
        + "Adhan at 3:35 PM while Salah is open")
  }

  @Test func theLastFifteenMinutesAreApproaching() {
    let presentation = TVFixtures.presentation(at: "2026-06-02T15:25:00+03:00")
    #expect(presentation.isApproaching)
    #expect(presentation.countdown == "0:10:00")
    let asr = presentation.display.listedDay!.events.first { $0.kind == .asr }!
    #expect(presentation.status(of: asr) == .next(approaching: true))
    #expect(presentation.detail(for: asr) == "in 10 min")
  }

  @Test func aPrayerThatJustBeganCountsUp() {
    let presentation = TVFixtures.presentation(at: "2026-06-02T15:37:00+03:00")
    #expect(presentation.eyebrow == "Now")
    #expect(presentation.countdown == "+0:02:00")
    #expect(plain(presentation.subtitle) == "Began at 3:35 PM")
    #expect(presentation.soundNote.map { plain($0.text) } == "Next: Maghrib 7:00 PM")
  }

  @Test func afterIshaTheHeroIsTomorrowsFajr() {
    let presentation = TVFixtures.presentation(at: "2026-06-02T21:30:00+03:00")
    #expect(presentation.eyebrow == "Tomorrow")
    #expect(presentation.name == "Fajr")
  }

  @Test func theNoteSaysWhenNothingWillSound() {
    let muted = TVFixtures.presentation(
      at: "2026-06-02T13:19:00+03:00", preferences: TVFixtures.preferences { $0.muteSounds = true })
    #expect(muted.soundNote?.text == "Sounds are off on this Apple TV")
    #expect(muted.soundNote?.isOn == false)

    let off = TVFixtures.presentation(
      at: "2026-06-02T13:19:00+03:00",
      preferences: TVFixtures.preferences { $0.setTVSound(.none, for: .asr) })
    #expect(off.soundNote?.text == "No sound for Asr")

    let tone = TVFixtures.presentation(
      at: "2026-06-02T13:19:00+03:00",
      preferences: TVFixtures.preferences { $0.setTVSound(.softTone, for: .asr) })
    #expect(tone.soundNote.map { plain($0.text) } == "Tone at 3:35 PM while Salah is open")
  }

  @Test func rowsSayHowFarAPrayerIs() {
    let presentation = TVFixtures.presentation(at: "2026-06-02T13:19:00+03:00")
    let events = presentation.display.listedDay!.events
    let byKind = Dictionary(uniqueKeysWithValues: events.map { ($0.kind, $0) })
    #expect(presentation.detail(for: byKind[.asr]!) == "in 2:16")
    #expect(presentation.detail(for: byKind[.dhuhr]!) == "1 hr ago")
    #expect(presentation.detail(for: byKind[.fajr]!) == nil)
    #expect(presentation.detail(for: byKind[.isha]!) == nil)
    #expect(presentation.chip(for: byKind[.asr]!) == "in 2:16")
    #expect(presentation.chip(for: byKind[.maghrib]!) == nil)
    #expect(
      plain(presentation.rowAccessibility(for: byKind[.asr]!))
        == "Asr, 3:35 PM, in 2 hours, 16 minutes, next prayer")
    #expect(plain(presentation.rowAccessibility(for: byKind[.fajr]!)) == "Fajr, 4:11 AM, passed")
    // The prayer that began last is read as its row shows it, "1 hr ago".
    #expect(
      plain(presentation.rowAccessibility(for: byKind[.dhuhr]!)) == "Dhuhr, 12:19 PM, 1 hour ago")
  }

  @Test func arabicUsesItsNamesAndDigits() {
    let presentation = TVFixtures.presentation(
      at: "2026-06-02T13:19:00+03:00", preferences: TVFixtures.preferences(language: .arabic))
    #expect(presentation.name == "العصر")
    #expect(presentation.countdown == "٢:١٦:٠٠")
    #expect(presentation.eyebrow == "الصلاة القادمة")
    #expect(plain(presentation.subtitle) == "تبدأ الساعة ٣:٣٥ م")
  }

  @Test func boardTimesSplitTheirDayPeriod() {
    let time = TVTimeText(locale: Locale(identifier: "en_US"), timeZone: TVFixtures.makkah.timeZone)
    let asr = TVFixtures.date("2026-06-02T15:35:00+03:00")
    #expect(plain(time.clock(asr)) == "3:35")
    #expect(time.period(asr) == "PM")
    #expect(plain(time.time24(asr)) == "15:35")
    let french = TVTimeText(locale: Locale(identifier: "fr"), timeZone: TVFixtures.makkah.timeZone)
    #expect(french.period(asr) == nil)
    #expect(plain(french.clock(asr)) == "15:35")
  }

  @Test func gregorianDatesStayGregorianWhereTheLocaleCountsInHijri() {
    let date = TVFixtures.date("2026-06-02T13:19:00+03:00")
    let zone = TVFixtures.makkah.timeZone
    let english = TVTimeText(locale: Locale(identifier: "en_SA"), timeZone: zone)
    #expect(english.date(date, template: "MMMMd").contains("June"))
    let arabic = TVTimeText(locale: Locale(identifier: "ar_SA"), timeZone: zone)
    #expect(arabic.date(date, template: "MMMMd").contains("يونيو"))
    let header = SalahText(locale: Locale(identifier: "ar_SA"), timeZone: zone).gregorianDate(date)
    #expect(header.contains("يونيو"))
    // Arabic digits, and no comma before the year.
    #expect(header.contains("يونيو ٢٠٢٦"))
    // Persian's civil calendar is the Solar Hijri one, which isn't the Hijri date again.
    let persian = TVTimeText(locale: Locale(identifier: "fa"), timeZone: zone)
    #expect(persian.date(date, template: "MMMMd").contains("خرداد"))
  }

  @Test func theWeeksRangeIsInTheSameCalendarAsItsDays() {
    let monday = TVFixtures.date("2026-06-01T00:00:00+03:00")
    let sunday = TVFixtures.date("2026-06-07T00:00:00+03:00")
    let zone = TVFixtures.makkah.timeZone
    let saudi = TVTimeText(locale: Locale(identifier: "en_SA"), timeZone: zone)
    #expect(saudi.range(from: monday, to: sunday, template: "d MMMM yyyy").contains("June 2026"))
    let arabic = TVTimeText(locale: Locale(identifier: "ar_SA"), timeZone: zone)
    #expect(arabic.range(from: monday, to: sunday, template: "d MMMM yyyy").contains("يونيو"))
    let persian = TVTimeText(locale: Locale(identifier: "fa"), timeZone: zone)
    #expect(persian.range(from: monday, to: sunday, template: "d MMMM yyyy").contains("خرداد"))
  }

  @Test func theSourceNoteNamesTheMethodAndPlace() {
    let preferences = TVFixtures.preferences()
    let note = TVSourceNote(
      display: TVFixtures.display(at: "2026-06-02T13:19:00+03:00", preferences: preferences),
      preferences: preferences)
    #expect(
      note.today
        == "Umm al-Qura, Makkah · Shafi’i · Calculated on this Apple TV for Makkah, Saudi Arabia.")
  }

  @Test func settingsValuesReadAsTheRowsShowThem() {
    let copy = TVSettingsCopy(locale: Locale(identifier: "en"))
    #expect(copy.hijriOffset(0) == "No adjustment")
    #expect(copy.hijriOffset(1) == "+1 day")
    #expect(copy.hijriOffset(-2) == "−2 days")
    #expect(copy.signedMinutes(5) == "+5 min")
    #expect(copy.signedMinutes(-5) == "−5 min")
    #expect(copy.volume(0.75) == "75%")
    #expect(copy.adjustments(.zero) == "None")
    var adjustments = PrayerAdjustments.zero
    adjustments.setSettingsMinutes(3, for: .isha)
    #expect(copy.adjustments(adjustments) == "1 changed")
    #expect(copy.sound(.none) == "Off")
  }

  @Test func aPrayersSoundIsOnOrOff() {
    var preferences = TVFixtures.preferences()
    #expect(preferences.tvSound(for: .fajr) == .fajrAdhan)
    #expect(preferences.tvSound(for: .sunrise) == .none)
    #expect(preferences.tvSoundsOn == 5)
    preferences.setTVSound(.none, for: .isha)
    #expect(preferences.tvSound(for: .isha) == .none)
    #expect(preferences.notifications[.isha]?.sound == .adhan)
    preferences.setTVSound(.softTone, for: .isha)
    #expect(preferences.tvSound(for: .isha) == .softTone)
    #expect(preferences.tvSoundsOn == 5)
  }

  @Test func jumuahHasItsOwnSoundOnlyWithTheOverride() {
    var preferences = TVFixtures.preferences(TVFixtures.jakarta)
    preferences.setTVSound(.softTone, for: .dhuhr, observance: .jumuah)
    #expect(preferences.tvSound(for: .dhuhr) == .softTone)
    preferences.jumuahOverrideEnabled = true
    preferences.jumuahAlerts.sound = .fajrAdhan
    preferences.setTVSound(.none, for: .dhuhr, observance: .jumuah)
    #expect(preferences.tvSound(for: .dhuhr, observance: .jumuah) == .none)
    #expect(preferences.tvSound(for: .dhuhr) == .softTone)
  }
}
