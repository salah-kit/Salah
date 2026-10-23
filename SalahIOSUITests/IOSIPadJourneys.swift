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
    XCTAssertGreaterThan(window.frame.width, window.frame.height)
    let sheet = require("onboarding.formSheet", in: app)
    XCTAssertEqual(sheet.frame.width, 540, accuracy: 1)
    XCTAssertEqual(sheet.frame.height, 760, accuracy: 1)
    XCTAssertEqual(sheet.frame.midX, window.frame.midX, accuracy: 1)
    XCTAssertEqual(sheet.frame.midY, window.frame.midY, accuracy: 1)
    XCTAssertTrue(window.frame.contains(sheet.frame))
    let backdrop = require("app.tabs", in: app)
    XCTAssertFalse(backdrop.isHittable, "The onboarding sheet keeps the backing app modal")
    captureSystem("iPad-English-Onboarding-Centered-Form-Sheet")

    tap("onboarding.continue", in: app)
    tap("onboarding.location.chooseCity", in: app)
    selectCity("Makkah, Saudi Arabia", matching: "Makkah", in: app)
    tap("onboarding.notification.notNow", in: app)
    tap("onboarding.calculation.continue", in: app)
    tap("onboarding.ready.start", in: app)
    XCTAssertTrue(waitUntil { !sheet.exists })
    require("today.nextPrayer", in: app)
    XCTAssertTrue(cityMatches("Makkah", label: require("today.location", in: app).label))
    captureSystem("iPad-English-First-Run-Completed")
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
    XCTAssertGreaterThan(window.frame.width, window.frame.height)
    let hero = require("today.nextPrayer", in: app)
    XCTAssertTrue(window.frame.contains(hero.frame))
    captureSystem("iPad-English-Landscape-Today")
    tap("tab.times", in: app)
    tap("times.week", in: app)
    require("times.weekTable", in: app)
    captureSystem("iPad-English-Landscape-Times-Week")
    tap("tab.settings", in: app)
    require("settings.form", in: app)
    require("calculation.form", in: app)
    let masterRow = require("settings.method", in: app)
    let detailRow = require("method.automatic", in: app)
    XCTAssertTrue(masterRow.isHittable)
    XCTAssertTrue(detailRow.isHittable)
    // Native collection-view accessibility bounds can span the split container.
    // The visible controls describe the actual columns and their hit regions.
    XCTAssertGreaterThan(masterRow.frame.width, 200)
    XCTAssertGreaterThan(detailRow.frame.width, 200)
    XCTAssertLessThan(masterRow.frame.midX, detailRow.frame.midX)
    XCTAssertLessThanOrEqual(masterRow.frame.maxX, detailRow.frame.minX + 1)
    captureSystem("iPad-English-Landscape-Settings-Calculation-Split")

    tap("settings.sound", in: app)
    require("settings.form", in: app)
    require("sound.form", in: app)
    XCTAssertTrue(require("settings.location", in: app).isHittable)
    XCTAssertTrue(require("sound.mute", in: app).isHittable)
    captureSystem("iPad-English-Landscape-Settings-Sound-Split")

    tap("settings.alerts", in: app)
    require("settings.form", in: app)
    require("alerts.form", in: app)
    tap("alerts.fajr", in: app)
    setSwitch("alert.fajr.before.enabled", to: true, in: app)
    XCTAssertTrue(require("alert.fajr.before.minutes", in: app).isHittable)
    XCTAssertTrue(require("settings.method", in: app).isHittable)
    require("settings.form", in: app)
    captureSystem("iPad-English-Landscape-Notifications")

    tap("tab.today", in: app)
    require("today.nextPrayer", in: app)
    XCUIDevice.shared.system.open(URL(string: "salah://location")!)
    require("location.form", in: app)
    require("settings.form", in: app)
    XCTAssertTrue(require("location.searchField", in: app).isHittable)
    XCTAssertTrue(require("settings.sound", in: app).isHittable)
    captureSystem("iPad-English-Landscape-Location-Deep-Link-Split")
  }
}
