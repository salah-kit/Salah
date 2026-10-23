import XCTest

/// Run on an iPad simulator: the regular-width app must build and navigate its own
/// adaptive layout, including the notification settings detail.
nonisolated final class IOSIPadJourneys: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  func testFirstRunUsesCenteredFormSheetAndCompletesSetup() {
    XCUIDevice.shared.orientation = .landscapeLeft
    let journey = IOSJourneyApp(fixture: true, skipOnboarding: false)
    journey.launch()
    let app = journey.app
    defer {
      app.terminate()
      XCUIDevice.shared.orientation = .portrait
    }

    let window = app.windows.firstMatch
    XCTAssertTrue(window.exists || window.waitForExistence(timeout: 15))
    XCTAssertGreaterThan(window.frame.width, 700, "Run IOSIPadJourneys on an iPad")
    let sheet = require("onboarding.formSheet", in: app)
    XCTAssertEqual(sheet.frame.width, 540, accuracy: 1)
    XCTAssertEqual(sheet.frame.height, 760, accuracy: 1)
    XCTAssertEqual(sheet.frame.midX, window.frame.midX, accuracy: 1)
    XCTAssertEqual(sheet.frame.midY, window.frame.midY, accuracy: 1)
    XCTAssertTrue(window.frame.contains(sheet.frame))
    let backdrop = require("app.tabs", in: app)
    XCTAssertFalse(backdrop.isHittable, "The onboarding sheet keeps the backing app modal")
    capture("iPad-English-Onboarding-Centered-Form-Sheet", in: app)

    tap("onboarding.continue", in: app)
    tap("onboarding.location.chooseCity", in: app)
    selectCity("Makkah, Saudi Arabia", matching: "Makkah", in: app)
    tap("onboarding.notification.notNow", in: app)
    tap("onboarding.calculation.continue", in: app)
    tap("onboarding.ready.start", in: app)
    XCTAssertTrue(waitUntil { !sheet.exists })
    require("today.nextPrayer", in: app)
    XCTAssertTrue(cityMatches("Makkah", label: require("today.location", in: app).label))
    capture("iPad-English-First-Run-Completed", in: app)
  }

  @MainActor
  func testLandscapeTodayWeekAndNotificationSettings() {
    XCUIDevice.shared.orientation = .landscapeLeft
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer {
      app.terminate()
      XCUIDevice.shared.orientation = .portrait
    }

    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 15))
    XCTAssertGreaterThan(window.frame.width, 700, "Run IOSIPadJourneys on an iPad")
    let hero = require("today.nextPrayer", in: app)
    XCTAssertTrue(window.frame.contains(hero.frame))
    capture("iPad-English-Landscape-Today", in: app)
    tap("tab.times", in: app)
    tap("times.week", in: app)
    require("times.weekTable", in: app)
    capture("iPad-English-Landscape-Times-Week", in: app)
    tap("tab.settings", in: app)
    tap("settings.alerts", in: app)
    tap("alerts.fajr", in: app)
    setSwitch("alert.fajr.before.enabled", to: true, in: app)
    XCTAssertTrue(require("alert.fajr.before.minutes", in: app).isHittable)
    capture("iPad-English-Landscape-Notifications", in: app)
  }
}
