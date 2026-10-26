import Foundation
import SalahCore
import Testing

@Suite("Apple TV navigation")
@MainActor
struct TVNavigationTests {
  private var asr: PrayerEvent {
    PrayerEvent(
      scheduleDay: CivilDay(year: 2026, month: 6, day: 2), kind: .asr,
      time: TVFixtures.date("2026-06-02T15:35:00+03:00"))
  }

  @Test func linksOpenTheirTabOrTheRoomDisplay() {
    let navigation = TVNavigation()
    navigation.handle(url: URL(string: "salah://week")!)
    #expect(navigation.selectedTab == .week)
    navigation.handle(url: URL(string: "salah://room")!)
    #expect(navigation.fullScreen == .roomDisplay)
    navigation.handle(url: URL(string: "salah://today")!)
    #expect(navigation.selectedTab == .today)
    #expect(navigation.fullScreen == nil)
  }

  @Test func foreignLinksChangeNothing() {
    let navigation = TVNavigation()
    navigation.selectedTab = .settings
    for link in ["https://example.com/room", "salah://qibla", "other://today"] {
      navigation.handle(url: URL(string: link)!)
    }
    #expect(navigation.selectedTab == .settings)
    #expect(navigation.fullScreen == nil)
  }

  @Test func routesRoundTripThroughTheirLinks() {
    for route in TVRoute.allCases {
      #expect(TVRoute(url: route.url) == route)
    }
    #expect(TopShelfBanner.today.url == TVRoute.today.url)
    #expect(TopShelfBanner.nextPrayer.url == TVRoute.today.url)
    #expect(TopShelfBanner.roomDisplay.url.absoluteString == "salah://room")
  }

  @Test func theAdhanReturnsToTheRoomDisplayItInterrupted() {
    let navigation = TVNavigation()
    navigation.showRoomDisplay()
    navigation.showAdhan(for: asr)
    #expect(navigation.fullScreen == .adhan(asr))
    navigation.adhanEnded()
    #expect(navigation.fullScreen == .roomDisplay)
  }

  @Test func theAdhanOverTheTabsReturnsToThem() {
    let navigation = TVNavigation()
    navigation.showAdhan(for: asr)
    navigation.adhanEnded()
    #expect(navigation.fullScreen == nil)
  }

  @Test func aRoomDisplayLinkDuringTheAdhanOpensAfterIt() {
    let navigation = TVNavigation()
    navigation.showAdhan(for: asr)
    navigation.handle(url: TVRoute.roomDisplay.url)
    #expect(navigation.fullScreen == .adhan(asr))
    navigation.adhanEnded()
    #expect(navigation.fullScreen == .roomDisplay)
  }

  @Test func aTabLinkDuringTheAdhanSelectsTheTabUnderneath() {
    let navigation = TVNavigation()
    navigation.showAdhan(for: asr)
    navigation.handle(url: TVRoute.week.url)
    #expect(navigation.fullScreen == .adhan(asr))
    #expect(navigation.selectedTab == .week)
    navigation.adhanEnded()
    #expect(navigation.fullScreen == nil)
    #expect(navigation.selectedTab == .week)
  }

  @Test func aTabLinkDuringTheAdhanOverTheRoomDisplayEndsOnTheTab() {
    let navigation = TVNavigation()
    navigation.showRoomDisplay()
    navigation.showAdhan(for: asr)
    navigation.handle(url: TVRoute.settings.url)
    #expect(navigation.fullScreen == .adhan(asr))
    navigation.adhanEnded()
    #expect(navigation.fullScreen == nil)
    #expect(navigation.selectedTab == .settings)
  }

  @Test func backFromTheRoomDisplayForgetsItForLaterAdhans() {
    let navigation = TVNavigation()
    navigation.showRoomDisplay()
    navigation.dismissFullScreen()
    navigation.showAdhan(for: asr)
    navigation.adhanEnded()
    #expect(navigation.fullScreen == nil)
  }

  @Test func adhanEndedWithoutAnAdhanLeavesTheRoomDisplay() {
    let navigation = TVNavigation()
    navigation.showRoomDisplay()
    navigation.adhanEnded()
    #expect(navigation.fullScreen == .roomDisplay)
  }
}
