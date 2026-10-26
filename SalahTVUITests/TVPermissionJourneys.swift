import XCTest

/// Setup with the real location alert, answered with the remote. Each journey resets Salah's
/// location permission first, so the alert is fresh. Allowing needs a simulated location,
/// such as latitude 21.4225, longitude 39.8262, and the network for Apple Maps.
nonisolated final class TVPermissionJourneys: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  /// Allow Once is enough: an Apple TV doesn't move, and Salah asks for one fix.
  @MainActor
  func testAllowingLocationOnceSetsUpTheCity() {
    let journey = launchSetup()
    let app = journey.app
    let use = require("onboarding.useLocation", in: app)
    XCTAssertTrue(waitUntil { self.hasFocus(use, in: app) }, "Use Location doesn't have focus")
    capture("onboarding", in: app)
    remote.press(.select)
    answer(TVLocationAlert.allowOnce, named: "Allow-Once")
    let source = require("today.source", in: app, timeout: 60)
    XCTAssertTrue(cityMatches("Makkah", label: source.label), source.label)
    capture("today-after-location", in: app)

    journey.relaunch()
    XCTAssertTrue(cityMatches("Makkah", label: require("today.source", in: app).label))
    XCTAssertFalse(element("onboarding.useLocation", in: app).exists)
  }

  /// Don't Allow says so and leaves choosing a city, which needs no permission.
  @MainActor
  func testDenyingLocationLeavesChoosingACity() {
    let journey = launchSetup()
    let app = journey.app
    let use = require("onboarding.useLocation", in: app)
    XCTAssertTrue(waitUntil { self.hasFocus(use, in: app) }, "Use Location doesn't have focus")
    remote.press(.select)
    answer(TVLocationAlert.dontAllow, named: "Dont-Allow")
    let error = require("onboarding.error", in: app)
    XCTAssertTrue(error.label.hasPrefix("Location access is off for Salah."), error.label)
    capture("onboarding-denied", in: app)
    // Focus comes back to Use Location once the alert closes.
    XCTAssertTrue(
      waitUntil { self.hasFocus(use, in: app) }, "Use Location didn't get focus back")
    moveFocus(.right, to: element("onboarding.chooseCity", in: app), in: app, maximumPresses: 2)
    remote.press(.select)
    chooseCity("Makkah", in: app)
    let source = require("today.source", in: app, timeout: 30)
    XCTAssertTrue(cityMatches("Makkah", label: source.label), source.label)

    journey.relaunch()
    XCTAssertTrue(cityMatches("Makkah", label: require("today.source", in: app).label))
  }

  /// Setup with no city and Salah's location permission not yet asked.
  @MainActor
  private func launchSetup() -> TVJourneyApp {
    var journey = TVJourneyApp()
    journey.fixture = nil
    journey.skipOnboarding = false
    journey.app.resetAuthorizationStatus(for: .location)
    addTeardownBlock { @MainActor in TVLocationAlert.dismissLeftover() }
    journey.launch()
    return journey
  }

  /// Answers the system's location alert with the remote.
  @MainActor
  private func answer(
    _ button: NSPredicate, named name: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    let alert = TVLocationAlert.alert
    XCTAssertTrue(
      alert.waitForExistence(timeout: 15), "Expected the location alert.", file: file, line: line)
    captureScreen("System-Location-\(name)")
    XCTAssertTrue(TVLocationAlert.choose(button), alert.debugDescription, file: file, line: line)
  }
}
