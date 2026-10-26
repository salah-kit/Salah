import Foundation
import SalahCore
import SalahTimes
import SalahWidgets
import Testing
import UIKit

@Suite("The Top Shelf", .serialized)
@MainActor
struct TVTopShelfTests {
  init() { TVTestResources.use() }

  private func snapshot(
    at text: String, preferences: IOSPreferences = TVFixtures.preferences(), isDark: Bool = false
  ) -> TopShelfSnapshot? {
    TopShelfSnapshot(settings: preferences.mirror, date: TVFixtures.date(text), isDark: isDark)
  }

  @Test func withoutALocationTheSystemShowsTheStaticImage() {
    #expect(TopShelfSnapshot(settings: nil, date: Date(), isDark: false) == nil)
  }

  @Test func theBannersNameTheNextPrayerAndTheDay() throws {
    let snapshot = try #require(snapshot(at: "2026-06-02T13:19:00+03:00"))
    #expect(snapshot.banners == [.nextPrayer, .today, .roomDisplay])
    #expect(snapshot.eyebrow(of: .nextPrayer) == "Next prayer · Makkah")
    #expect(plain(snapshot.title(of: .nextPrayer)) == "Asr at 3:35 PM")
    #expect(snapshot.title(of: .today) == "Today’s prayers")
    #expect(snapshot.title(of: .roomDisplay) == "Today’s times, all day")
    #expect(plain(snapshot.dateLine(of: .nextPrayer)) == "Tuesday, June 2 · 16 Dhuʻl-Hijjah 1447")
    #expect(snapshot.events(of: .nextPrayer) == snapshot.events(of: .today))
    #expect(snapshot.phase(of: .nextPrayer) == .asr)
    #expect(snapshot.phase(of: .today) == .dhuhr)
    #expect(snapshot.phase(of: .roomDisplay) == .isha)
    #expect(plain(snapshot.accessibilityTitle(of: .today)).contains("Maghrib 7:00 PM"))
  }

  /// From Isha's count-up on, when the app asks for new images, the next prayer is tomorrow's.
  @Test(arguments: ["2026-06-02T20:35:00+03:00", "2026-06-02T21:30:00+03:00"])
  func afterIshaTheNextPrayersBannerListsTomorrow(at moment: String) throws {
    let snapshot = try #require(snapshot(at: moment))
    #expect(snapshot.eyebrow(of: .nextPrayer) == "Tomorrow · Makkah")
    #expect(plain(snapshot.title(of: .nextPrayer)).hasPrefix("Fajr at "))
    #expect(
      plain(snapshot.dateLine(of: .nextPrayer)) == "Wednesday, June 3 · 17 Dhuʻl-Hijjah 1447")
    let tomorrowsFajr = try #require(snapshot.events(of: .nextPrayer).first)
    #expect(tomorrowsFajr.id == snapshot.nextPrayer?.id)
    // Today's banners still list today.
    #expect(snapshot.eyebrow(of: .today) == "Today · Makkah")
    #expect(plain(snapshot.dateLine(of: .today)) == "Tuesday, June 2 · 16 Dhuʻl-Hijjah 1447")
    let todaysFajr = try #require(snapshot.events(of: .today).first)
    #expect(todaysFajr.time < tomorrowsFajr.time)
  }

  @Test func aNeutralSkyStaysNeutral() throws {
    let snapshot = try #require(
      snapshot(
        at: "2026-06-02T13:19:00+03:00",
        preferences: TVFixtures.preferences { $0.followsTimeOfDay = false }))
    #expect(snapshot.phase(of: .nextPrayer) == .neutral)
    #expect(snapshot.phase(of: .today) == .neutral)
    #expect(snapshot.phase(of: .roomDisplay) == .isha)
  }

  @Test func arabicBannersUseArabicWords() throws {
    let snapshot = try #require(
      snapshot(
        at: "2026-06-02T13:19:00+03:00", preferences: TVFixtures.preferences(language: .arabic)))
    #expect(plain(snapshot.title(of: .nextPrayer)) == "العصر ٣:٣٥ م")
    #expect(snapshot.title(of: .today) == "صلوات اليوم")
  }

  @Test func theImagesChangeWithWhatTheyShow() throws {
    let light = try #require(snapshot(at: "2026-06-02T13:19:00+03:00"))
    let dark = try #require(snapshot(at: "2026-06-02T13:19:00+03:00", isDark: true))
    let arabic = try #require(
      snapshot(
        at: "2026-06-02T13:19:00+03:00", preferences: TVFixtures.preferences(language: .arabic)))
    let afterAsr = try #require(snapshot(at: "2026-06-02T15:40:00+03:00"))
    let sameMinute = try #require(snapshot(at: "2026-06-02T13:19:30+03:00"))
    for banner in TopShelfBanner.allCases {
      #expect(light.fingerprint(of: banner) != dark.fingerprint(of: banner))
      #expect(light.fingerprint(of: banner) != arabic.fingerprint(of: banner))
      #expect(light.fingerprint(of: banner) == sameMinute.fingerprint(of: banner))
    }
    #expect(light.fingerprint(of: .nextPrayer) != afterAsr.fingerprint(of: .nextPrayer))
    #expect(light.fingerprint(of: .today) != afterAsr.fingerprint(of: .today))
  }

  @Test func theTodayImageChangesWhenTheNextPrayerDoes() throws {
    // A neutral sky, so only the next prayer's gold differs within the ten minutes.
    let neutral = TVFixtures.preferences { $0.followsTimeOfDay = false }
    let beforeDhuhr = try #require(snapshot(at: "2026-06-02T12:11:00+03:00", preferences: neutral))
    let afterDhuhr = try #require(snapshot(at: "2026-06-02T12:19:30+03:00", preferences: neutral))
    #expect(beforeDhuhr.nextPrayer?.kind == .dhuhr)
    #expect(afterDhuhr.nextPrayer?.kind == .asr)
    #expect(beforeDhuhr.fingerprint(of: .today) != afterDhuhr.fingerprint(of: .today))
  }

  @Test func aTimeTheScheduleCantGiveKeepsItsPlace() throws {
    // London in June with no high-latitude rule: the Sun never gets 17° or 18° below the
    // horizon, so Fajr and Isha can't be calculated.
    let preferences = TVFixtures.preferences(TVFixtures.london) {
      $0.method = .preset(.muslimWorldLeague)
      $0.automaticHighLatitude = false
      $0.highLatitudeRule = .disabled
    }
    let snapshot = try #require(snapshot(at: "2026-06-02T13:00:00+01:00", preferences: preferences))
    let kinds: [PrayerKind] = [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha]
    for banner in [TopShelfBanner.nextPrayer, .today] {
      let slots = snapshot.slots(of: banner)
      #expect(slots.map(\.kind) == kinds)
      #expect(slots.contains(.missing(.fajr)))
      #expect(slots.contains(.missing(.isha)))
    }
    let board = snapshot.slots(of: .roomDisplay)
    #expect(board.map(\.kind) == kinds.filter(\.isPrayer))
    #expect(board.contains(.missing(.isha)))
    #expect(snapshot.events(of: .today).count == 4)
    #expect(snapshot.name(of: .missing(.isha)) == "Isha")
    let spoken = plain(snapshot.accessibilityTitle(of: .today))
    #expect(spoken.contains("Fajr Not available"))
    #expect(spoken.contains("Isha Not available"))
    for banner in snapshot.banners {
      #expect(TopShelfImages.png(of: banner, snapshot: snapshot, scale: 1) != nil)
    }
  }

  @Test func bannersRenderAtTheTopShelfsSizes() throws {
    let snapshot = try #require(snapshot(at: "2026-06-02T13:19:00+03:00", isDark: true))
    for banner in snapshot.banners {
      for scale in [1.0, 2.0] {
        let data = try #require(TopShelfImages.png(of: banner, snapshot: snapshot, scale: scale))
        let image = try #require(UIImage(data: data))
        let pixels = CGSize(
          width: image.size.width * image.scale, height: image.size.height * image.scale)
        #expect(
          pixels == CGSize(width: 1940 * scale, height: 692 * scale),
          "\(banner) at \(scale)x is \(pixels)")
      }
    }
  }

  @Test func publishingReloadsOnlyWhenTheBannersWouldChange() throws {
    let suite = "io.github.salah-kit.Salah.tvOS.unit." + UUID().uuidString
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    var reloads = 0
    let mirror = SharedValue<SalahSettings>(appGroup: suite, key: "settings")
    let publisher = TVTopShelfPublisher(settings: mirror) { reloads += 1 }
    let settings = TVFixtures.preferences().mirror
    let today = CivilDay(year: 2026, month: 6, day: 2)
    let tomorrow = today.adding(days: 1)
    #expect(try publisher.publish(settings, nextPrayer: "asr", day: today, phase: .dhuhr))
    #expect(mirror.load() == settings)
    #expect(try !publisher.publish(settings, nextPrayer: "asr", day: today, phase: .dhuhr))
    #expect(try publisher.publish(settings, nextPrayer: "fajr", day: today, phase: .isha))
    // At midnight the next prayer is still tomorrow's Fajr, but the Today banner and the dates
    // change.
    #expect(try publisher.publish(settings, nextPrayer: "fajr", day: tomorrow, phase: .isha))
    #expect(try !publisher.publish(settings, nextPrayer: "fajr", day: tomorrow, phase: .isha))
    #expect(
      try publisher.publish(
        TVFixtures.preferences(language: .arabic).mirror, nextPrayer: "fajr", day: tomorrow,
        phase: .isha))
    // At sunrise the next prayer stays Dhuhr, but the Today banner's sky changes.
    let arabic = TVFixtures.preferences(language: .arabic).mirror
    #expect(try publisher.publish(arabic, nextPrayer: "dhuhr", day: tomorrow, phase: .fajr))
    #expect(try publisher.publish(arabic, nextPrayer: "dhuhr", day: tomorrow, phase: .dhuhr))
    #expect(try publisher.publish(nil, nextPrayer: nil, day: nil, phase: nil))
    #expect(mirror.load() == nil)
    #expect(reloads == 7)
  }
}
