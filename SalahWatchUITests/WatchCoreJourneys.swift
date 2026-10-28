import XCTest

/// The watch app as a person uses it: the next prayer and the rest of its day, swiping down
/// to today's list and the Qibla, the adhan at prayer time with Stop, Arabic with its own
/// digits, the larger text sizes, and the preferences kept across a relaunch.
nonisolated final class WatchCoreJourneys: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  func testTheNextPrayerLeadsWithTheRestOfItsDay() {
    let journey = WatchJourneyApp()
    journey.launch()
    let app = journey.app
    require("screen.now", in: app)
    waitForLabel(
      "hero", containing: "Next prayer, Asr, 3:37 PM, in 2 hours, 18 minutes", in: app)
    XCTAssertTrue(plain(require("row.maghrib", in: app).label).contains("Maghrib, 6:14 PM"))
    require("row.isha", in: app)
    XCTAssertFalse(element("row.dhuhr", in: app).exists)
    screenshot("now-en")
  }

  /// Swiping up moves from the first page to today's list and the Qibla, as the Digital Crown
  /// does on a watch. XCUITest's crown rotation scrolls a page but doesn't move between them.
  @MainActor
  func testSwipingMovesThroughThePages() {
    var journey = WatchJourneyApp()
    journey.heading = "93"
    journey.launch()
    let app = journey.app
    require("screen.now", in: app)
    swipe(until: "screen.today", in: app)
    XCTAssertTrue(
      plain(require("row.asr", in: app).label).contains("Asr, 3:37 PM, in 2 hours, 18 minutes"))
    XCTAssertTrue(require("row.fajr", in: app).label.hasSuffix("passed"))
    screenshot("today-en")
    swipe(until: "screen.qibla", in: app)
    waitForLabel("qibla.dial", containing: "Qibla 119°. Turn 26° right", in: app)
    screenshot("qibla-en")
  }

  @MainActor
  func testTheAdhanPlaysAtPrayerTimeAndStops() {
    var journey = WatchJourneyApp()
    // Four seconds before Maghrib, on a running clock; the fixture plays it silently.
    journey.now = "2026-10-12T17:13:56Z"
    journey.frozen = false
    journey.tab = "today"
    journey.launch()
    let app = journey.app
    require("screen.today", in: app)
    // At its time the adhan takes the first page, with Stop.
    let stop = require("hero.stop", in: app, timeout: 30)
    waitForLabel("hero", containing: "Playing adhan, Maghrib, 6:14 PM", in: app)
    XCTAssertTrue(require("row.isha", in: app).label.contains("next prayer"))
    screenshot("adhan-en")
    stop.tap()
    XCTAssertTrue(stop.waitForNonExistence(timeout: 10))
    waitForLabel("hero", containing: "Now, Maghrib, 6:14 PM", in: app)
    screenshot("after-stop-en")
  }

  @MainActor
  func testAMutedWatchPlaysNothing() {
    var journey = WatchJourneyApp()
    journey.now = "2026-10-12T17:13:58Z"
    journey.frozen = false
    journey.extraArguments = ["-salah.watch.mute", "true"]
    journey.launch()
    let app = journey.app
    waitForLabel("hero", containing: "Now, Maghrib", in: app, timeout: 30)
    XCTAssertFalse(element("hero.stop", in: app).exists)
  }

  @MainActor
  func testArabicHasItsOwnWordsAndDigits() {
    var journey = WatchJourneyApp()
    journey.language = "ar"
    journey.launch()
    let app = journey.app
    waitForLabel("hero", containing: "الصلاة القادمة, العصر", in: app)
    // Arabic digits: Asr at ٣:٣٧, two hours and eighteen minutes away.
    XCTAssertTrue(plain(element("hero", in: app).label).contains("٣:٣٧"))
    XCTAssertTrue(require("row.maghrib", in: app).label.contains("المغرب"))
    screenshot("now-ar")
  }

  /// At the largest text size before the accessibility sizes, every row stays in reach on
  /// Today. The time moving under the name is in the screenshot.
  @MainActor
  func testTheLargerTextSizesKeepEveryRow() {
    var journey = WatchJourneyApp()
    journey.tab = "today"
    journey.extraArguments = [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL",
    ]
    journey.launch()
    let app = journey.app
    require("screen.today", in: app)
    for kind in ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"] {
      let row = element("row." + kind, in: app)
      for _ in 0..<6 where !row.exists || !row.isHittable {
        XCUIDevice.shared.rotateDigitalCrown(delta: 0.25, velocity: .default)
      }
      XCTAssertTrue(row.exists && row.isHittable, "Can't reach \(kind) at xxxLarge")
    }
    screenshot("today-xxxl-en")
  }

  @MainActor
  func testTheQiblaKeepsItsBearingWithoutACompass() {
    var journey = WatchJourneyApp()
    journey.tab = "qibla"
    journey.heading = "none"
    journey.launch()
    let app = journey.app
    waitForLabel("qibla.dial", containing: "Qibla 119°. Compass unavailable", in: app)
    screenshot("qibla-no-compass-en")
  }

  @MainActor
  func testFacingTheQibla() {
    var journey = WatchJourneyApp()
    journey.tab = "qibla"
    journey.heading = "120"
    journey.launch()
    waitForLabel("qibla.dial", containing: "Facing the Qibla", in: journey.app)
    screenshot("qibla-aligned-en")
  }

  /// The watch keeps the preferences the iPhone sent, so a relaunch, with the iPhone away,
  /// shows the same times.
  @MainActor
  func testTheWatchKeepsItsPreferencesAcrossARelaunch() {
    let journey = WatchJourneyApp()
    journey.launch()
    waitForLabel("hero", containing: "Asr, 3:37 PM", in: journey.app)
    journey.relaunch()
    waitForLabel("hero", containing: "Asr, 3:37 PM", in: journey.app)
  }

  @MainActor
  func testAFreshWatchAsksForTheIPhone() {
    var journey = WatchJourneyApp()
    journey.fixture = nil
    journey.launch()
    let app = journey.app
    require("screen.setup", in: app)
    XCTAssertTrue(app.staticTexts["Set up Salah on your iPhone"].exists)
    screenshot("setup-en")
  }

  @MainActor
  private func swipe(until identifier: String, in app: XCUIApplication) {
    let target = element(identifier, in: app)
    for _ in 0..<6 where !target.exists {
      app.swipeUp()
      _ = target.waitForExistence(timeout: 1.5)
    }
    XCTAssertTrue(target.exists, "Swiping never reached \(identifier).\n\(app.debugDescription)")
  }
}
