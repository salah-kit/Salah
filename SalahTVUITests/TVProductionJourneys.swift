import XCTest

/// Production composition: the app's own defaults, the real clock and live city search. Run
/// it after a fresh installation; it passes no Debug launch option.
nonisolated final class TVProductionJourneys: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  func testProductionSetupAndASettingSurviveRelaunch() {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    defer { app.terminate() }

    let choose = require("onboarding.chooseCity", in: app)
    moveFocus(.right, to: choose, in: app, maximumPresses: 2)
    remote.press(.select)
    chooseCity("Makkah", in: app)
    let source = require("today.source", in: app, timeout: 30)
    XCTAssertTrue(cityMatches("Makkah", label: source.label), source.label)
    capture("production-today", in: app)

    openTab("Settings", in: app)
    let adhan = element("settings.adhan", in: app)
    moveFocus(.down, to: adhan, in: app, maximumPresses: 10)
    remote.press(.select)
    openTab("Today", in: app)
    XCTAssertTrue(require("hero", in: app).label.contains("Sounds are off on this Apple TV"))

    app.terminate()
    app.launch()
    XCTAssertFalse(element("onboarding.chooseCity", in: app).exists)
    XCTAssertTrue(cityMatches("Makkah", label: require("today.source", in: app).label))
    let hero = require("hero", in: app)
    XCTAssertTrue(hero.label.contains("Sounds are off on this Apple TV"), hero.label)
    capture("production-relaunch", in: app)
  }
}
