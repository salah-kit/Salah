import AppKit
import XCTest

/// The first launch's welcome in the real app: its own window with the Dock icon, a page
/// at a time, and Salah's window when it ends, on Today or on the Location pane.
final class OnboardingUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// Welcome, location and notifications in turn; Choose a City… then Not Now end the
  /// welcome on the Location pane, and the welcome's window is gone.
  @MainActor
  func testTheWelcomeWalksThroughItsPagesAndOpensSalah() throws {
    let app = XCUIApplication()
    // The quiet launch, with the welcome shown and its Allow buttons kept from asking.
    app.launchArguments =
      SalahUITests.quietLaunch + [
        "-salah.debug.withoutSystemPrompts", "YES",
        "-salah.debug.showsOnboarding", "YES",
      ]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }

    let welcome = app.windows["Welcome to Salah"]
    XCTAssertTrue(welcome.waitForExistence(timeout: 30), app.debugDescription)
    XCTAssertFalse(app.salahWindow.exists, "Salah's window waits for the welcome")
    XCTAssertTrue(text("Prayer times, calm and on time", in: welcome).exists)

    welcome.buttons["Continue"].click()
    XCTAssertTrue(
      text("Times for where you are", in: welcome).waitForExistence(timeout: 5),
      welcome.debugDescription)
    welcome.buttons["Choose a City…"].click()
    XCTAssertTrue(
      text("Hear the adhan at each prayer", in: welcome).waitForExistence(timeout: 5),
      welcome.debugDescription)
    welcome.buttons["Not Now"].click()

    let window = app.salahWindow
    XCTAssertTrue(window.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertEqual(window.title, "Location", "Choose a City… ends on the Location pane")
    XCTAssertFalse(welcome.exists)
  }

  /// A text of the welcome by its words, a page's title (a heading) included.
  @MainActor
  private func text(_ value: String, in window: XCUIElement) -> XCUIElement {
    window.descendants(matching: .any)
      .matching(NSPredicate(format: "value == %@ OR label == %@", value, value)).firstMatch
  }
}
