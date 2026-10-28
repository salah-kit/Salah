import XCTest

/// The production composition, without Debug launch options: a freshly installed watch app
/// has no preferences until the iPhone sends them, and asks for the iPhone. Run it after a
/// fresh installation.
nonisolated final class WatchProductionJourneys: XCTestCase {
  @MainActor
  func testAFreshInstallWaitsForTheIPhone() {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
    app.launch()
    require("screen.setup", in: app, timeout: 30)
    XCTAssertTrue(app.staticTexts["Set up Salah on your iPhone"].exists)
    screenshot("production-setup-en")
  }
}
