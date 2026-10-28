import XCTest

/// The complication outside the app: Salah's widget added to the Smart Stack from the watch
/// face, where WidgetKit runs the extension on the settings the app mirrored.
///
/// The watch face exposes no accessibility elements in the Smart Stack and its editor, so
/// the steps tap coordinates measured on a 46 mm watch with watchOS 27, and may need new ones
/// on another watch or system. `scripts/smart-stack-journey.sh` runs it with
/// `SALAH_WATCH_SMART_STACK=1` on a new simulator and checks the extension's log for the
/// timeline it built; otherwise it skips.
nonisolated final class WatchSmartStackJourneys: XCTestCase {
  override func setUpWithError() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SALAH_WATCH_SMART_STACK"] == "1",
      "The Smart Stack journey runs only from scripts/smart-stack-journey.sh.")
    continueAfterFailure = false
  }

  @MainActor
  private var carousel: XCUIApplication {
    XCUIApplication(bundleIdentifier: "com.apple.Carousel")
  }

  @MainActor
  private func tap(x: CGFloat, y: CGFloat, wait: TimeInterval = 4) {
    carousel.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    Thread.sleep(forTimeInterval: wait)
  }

  /// From the face, turning the crown opens the Smart Stack; a second turn moves the stack
  /// up, which puts its Edit button where the editing steps tap.
  @MainActor
  private func openTheSmartStack(turns: Int) {
    XCUIDevice.shared.press(.home)
    Thread.sleep(forTimeInterval: 3)
    for _ in 0..<turns {
      XCUIDevice.shared.rotateDigitalCrown(delta: 1, velocity: .default)
      Thread.sleep(forTimeInterval: 6)
    }
  }

  @MainActor
  func testTheComplicationCountsDownInTheSmartStack() {
    // The app mirrors the preferences the iPhone sent for the complication.
    var journey = WatchJourneyApp()
    journey.now = nil
    journey.frozen = false
    journey.launch()
    require("hero", in: journey.app)
    openTheSmartStack(turns: 2)
    screenshot("smartstack-1-stack")
    tap(x: 0.5, y: 0.86)  // Edit, under the stack
    screenshot("smartstack-2-editing")
    tap(x: 0.5, y: 0.43)  // The add slot
    screenshot("smartstack-3-apps")
    // The list of apps is alphabetical; Salah sits near its end.
    for _ in 0..<6 {
      carousel.swipeUp()
      Thread.sleep(forTimeInterval: 1.5)
    }
    screenshot("smartstack-4-apps-end")
    let salah = carousel.staticTexts["Salah"]
    if salah.exists, salah.isHittable {
      salah.tap()
      Thread.sleep(forTimeInterval: 4)
    } else {
      tap(x: 0.5, y: 0.72)  // Salah, as the list ends on a 46 mm watch
    }
    screenshot("smartstack-5-gallery")
    tap(x: 0.5, y: 0.5)  // Its widget
    tap(x: 0.15, y: 0.14, wait: 6)  // Done
    openTheSmartStack(turns: 1)
    Thread.sleep(forTimeInterval: 10)
    screenshot("smartstack-6-salah")
    // The taps can't be checked in the face; the script reads the extension's log, which
    // records a timeline only once the widget is in the Smart Stack.
  }
}
