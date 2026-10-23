import XCTest

/// Production composition uses its real shared container, clock and platform services.
/// A fresh install is required; no Debug preference or onboarding override is supplied.
nonisolated final class IOSProductionJourneys: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  func testProductionSetupAndSharedPreferencesSurviveRelaunch() {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    defer { app.terminate() }

    require("onboarding.continue", in: app)
    tap("onboarding.continue", in: app)
    tap("onboarding.location.chooseCity", in: app)
    selectCity("Makkah, Saudi Arabia", matching: "Makkah", in: app)
    tap("onboarding.notification.notNow", in: app)
    tap("onboarding.calculation.continue", in: app)
    tap("onboarding.ready.start", in: app)
    require("today.nextPrayer", in: app)
    XCTAssertFalse(require("today.name", in: app).label.isEmpty)
    XCTAssertTrue(cityMatches("Makkah", label: require("today.location", in: app).label))
    XCTAssertFalse(element("persistence.error", in: app).exists)
    capture("Production-iPhone-Today-After-Setup", in: app)

    tap("tab.settings", in: app)
    tap("settings.sound", in: app)
    setSwitch("sound.mute", to: true, in: app)
    XCTAssertFalse(element("persistence.error", in: app).exists)
    app.terminate()
    app.launch()

    require("today.nextPrayer", in: app)
    XCTAssertFalse(element("onboarding.continue", in: app).exists)
    XCTAssertTrue(cityMatches("Makkah", label: require("today.location", in: app).label))
    XCTAssertFalse(element("persistence.error", in: app).exists)
    tap("tab.settings", in: app)
    tap("settings.sound", in: app)
    XCTAssertEqual(switchValue("sound.mute", in: app), true)
    capture("Production-iPhone-Mute-Persisted", in: app)
  }
}
