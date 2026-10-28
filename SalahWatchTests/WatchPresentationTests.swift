import Foundation
import SalahCore
import SalahUI
import Testing

@Suite("The watch's hero and rows")
@MainActor
struct WatchPresentationTests {
  init() { WatchTestResources.use() }

  @Test func countsDownToTheNextPrayer() {
    let presentation = WatchFixtures.presentation(at: "2026-10-12T12:19:00Z")
    #expect(presentation.heroMode == .countdown)
    #expect(presentation.eyebrow == "Next prayer")
    #expect(presentation.heroName == "Asr")
    #expect(plain(presentation.heroTime) == "3:37 PM")
    #expect(presentation.countdown() == "2:18:00")
    #expect(
      plain(presentation.heroAccessibility)
        == "Next prayer, Asr, 3:37 PM, in 2 hours, 18 minutes")
  }

  /// With the wrist down the watch redraws once a minute, so the seconds go.
  @Test func dropsTheSecondsWhenTheScreenDims() {
    let presentation = WatchFixtures.presentation(at: "2026-10-12T12:19:20Z")
    #expect(presentation.countdown() == "2:17:40")
    #expect(presentation.countdown(showsSeconds: false) == "2:18")
  }

  @Test func turnsGoldInTheLastFifteenMinutes() {
    let presentation = WatchFixtures.presentation(at: "2026-10-12T17:05:00Z")
    #expect(presentation.heroMode == .approaching)
    #expect(presentation.heroName == "Maghrib")
    #expect(presentation.countdown() == "0:09:00")
  }

  @Test func countsUpUnderNowAfterAPrayerBegins() {
    let presentation = WatchFixtures.presentation(at: "2026-10-12T17:18:00Z")
    #expect(presentation.heroMode == .justStarted)
    #expect(presentation.eyebrow == "Now")
    #expect(presentation.heroName == "Maghrib")
    #expect(presentation.countdown() == "+0:04:00")
    #expect(presentation.countdown(showsSeconds: false) == "+0:04")
    let spoken = plain(presentation.heroAccessibility)
    #expect(spoken.hasSuffix("4 minutes ago"))
  }

  @Test func showsTomorrowsFajrAfterIsha() {
    let presentation = WatchFixtures.presentation(at: "2026-10-12T21:00:00Z")
    #expect(presentation.heroMode == .tomorrow)
    #expect(presentation.eyebrow == "Tomorrow")
    #expect(presentation.heroName == "Fajr")
    // After Isha the first page shows only tomorrow's Fajr; Today keeps today's list.
    #expect(presentation.followingRows.isEmpty)
    #expect(presentation.todayRows.count == 6)
  }

  @Test func holdsStopWhileTheAdhanPlays() {
    let preferences = WatchFixtures.preferences()
    let maghrib = WatchFixtures.display(at: "2026-10-12T17:14:00Z").prayerState?.previous
    let presentation = WatchFixtures.presentation(
      at: "2026-10-12T17:14:30Z", preferences: preferences,
      playback: maghrib.map { SalahPlayback(event: $0, slot: .alert) })
    #expect(presentation.heroMode == .playing)
    #expect(presentation.eyebrow == "Playing adhan")
    #expect(presentation.heroName == "Maghrib")
    #expect(plain(presentation.heroTime) == "6:14 PM")
    #expect(presentation.countdown() == nil)
    // The rest of the evening: Isha next, on the gold wash.
    #expect(presentation.followingRows.map(\.id) == [.isha])
    #expect(presentation.followingRows.first?.state == .next)
  }

  @Test func listsTheRestOfTheDayUnderTheHero() {
    let presentation = WatchFixtures.presentation(at: "2026-10-12T12:19:00Z")
    #expect(presentation.followingRows.map(\.id) == [.maghrib, .isha])
    #expect(presentation.followingRows.allSatisfy { $0.state == .upcoming && $0.detail == nil })
  }

  @Test func marksEachRowOfTheDay() {
    let rows = WatchFixtures.presentation(at: "2026-10-12T12:19:00Z").todayRows
    #expect(rows.map(\.id) == [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha])
    #expect(rows.map(\.state) == [.past, .past, .past, .next, .upcoming, .upcoming])
    // Times leave out the day period, as the watch face shows the clock.
    #expect(rows.map { plain($0.time) } == ["5:28", "7:19", "12:47", "3:37", "6:14", "7:58"])
    #expect(rows[3].detail == "in 2:18")
    #expect(
      plain(rows[3].accessibility) == "Asr, 3:37 PM, in 2 hours, 18 minutes, next prayer")
    #expect(plain(rows[0].accessibility) == "Fajr, 5:28 AM, passed")
  }

  @Test func marksThePrayerThatJustBeganAsNow() {
    let rows = WatchFixtures.presentation(at: "2026-10-12T17:18:00Z").todayRows
    let maghrib = rows.first { $0.id == .maghrib }
    #expect(maghrib?.state == .current)
    #expect(maghrib?.detail == "Now")
    #expect(rows.first { $0.id == .isha }?.state == .next)
  }

  @Test func approachingRowsCountInMinutes() {
    let rows = WatchFixtures.presentation(at: "2026-10-12T17:05:00Z").todayRows
    let maghrib = rows.first { $0.id == .maghrib }
    #expect(maghrib?.state == .approaching)
    #expect(maghrib?.detail == "in 9 min")
  }

  @Test func sunriseLeadsAsNextButNotAsAPrayer() {
    let presentation = WatchFixtures.presentation(at: "2026-10-12T06:00:00Z")
    #expect(presentation.heroName == "Sunrise")
    #expect(presentation.eyebrow == "Sunrise")
    #expect(presentation.heroMode == .countdown)
    let sunrise = presentation.todayRows.first { $0.id == .sunrise }
    #expect(sunrise?.state == .next)
    let spoken = plain(sunrise?.accessibility ?? "")
    #expect(spoken.hasSuffix(", next"))
  }

  @Test func speaksArabicWithItsOwnDigits() {
    let presentation = WatchFixtures.presentation(
      at: "2026-10-12T12:19:00Z", preferences: WatchFixtures.preferences(language: .arabic))
    #expect(presentation.eyebrow == "الصلاة القادمة")
    #expect(presentation.heroName == "العصر")
    #expect(presentation.countdown() == "٢:١٨:٠٠")
    #expect(presentation.todayRows[3].detail == "بعد ٢:١٨")
  }

  @Test func saysWhenADayHasNoTime() {
    // Under the midnight sun the sun never sets, so the day has no sunset to count from.
    let preferences = WatchFixtures.preferences(
      PrayerLocation(
        latitude: 69.6492, longitude: 18.9553, timeZone: TimeZone(identifier: "Europe/Oslo")!,
        countryCode: "NO", name: "Tromsø"))
    let rows = WatchFixtures.presentation(at: "2026-06-21T12:00:00Z", preferences: preferences)
      .todayRows
    let missing = rows.filter { $0.state == .missing }
    #expect(!missing.isEmpty)
    #expect(missing.allSatisfy { $0.time == "—" && $0.detail == "Not today" })
  }
}
