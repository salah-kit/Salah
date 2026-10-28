import XCTest

/// The complication outside the app: Salah's widget added to the Smart Stack from the watch
/// face, where WidgetKit runs the extension on the settings the app mirrored, and the widget
/// in the stack names the next prayer.
///
/// The watch face's own process, `com.apple.clockface`, draws the Smart Stack, its editor and
/// its widget gallery, and the journey finds their parts through it. The gallery lists the
/// apps with widgets alphabetically; Salah's row appears once the system has read its widget,
/// so the journey opens the gallery again when the row isn't there yet.
/// `scripts/smart-stack-journey.sh` runs it with `SALAH_WATCH_SMART_STACK=1` on a new
/// simulator and also checks the extension's log for the timeline it built; otherwise it
/// skips.
nonisolated final class WatchSmartStackJourneys: XCTestCase {
  override func setUpWithError() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SALAH_WATCH_SMART_STACK"] == "1",
      "The Smart Stack journey runs only from scripts/smart-stack-journey.sh.")
    continueAfterFailure = false
  }

  @MainActor
  private var face: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.clockface") }

  /// The cells on the face, for a failure's message.
  @MainActor
  private var cells: String {
    face.cells.allElementsBoundByIndex.map { $0.identifier + " | " + $0.label }
      .joined(separator: "\n")
  }

  /// Below the gallery's title bar and above the bottom edge, where a tap reaches the row.
  @MainActor
  private func isInView(_ element: XCUIElement) -> Bool {
    guard element.exists, element.isHittable else { return false }
    return element.frame.minY >= 62 && element.frame.maxY <= face.frame.maxY
  }

  /// Drags the list by a fraction of the screen and holds before lifting, so it doesn't coast.
  @MainActor
  private func drag(by fraction: CGFloat) {
    let start = face.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55 + fraction / 2))
    let end = face.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55 - fraction / 2))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
    Thread.sleep(forTimeInterval: 1)
  }

  /// Scrolls the gallery to Salah's row; `false` when the list ends without it.
  @MainActor
  private func scrollToSalah() -> Bool {
    let salah = face.cells["AppGroupCell -- Salah"]
    var previous = ""
    var unchanged = 0
    for _ in 0..<30 where unchanged < 2 {
      if isInView(salah) { return true }
      // At the end of the list the row can sit under the title bar.
      if salah.exists, salah.frame.minY < 62 {
        drag(by: -0.25)
        continue
      }
      let current = cells
      unchanged = current == previous ? unchanged + 1 : 0
      previous = current
      drag(by: 0.4)
    }
    return isInView(salah)
  }

  @MainActor
  func testTheComplicationCountsDownInTheSmartStack() {
    // The app mirrors the preferences the iPhone sent for the complication.
    var journey = WatchJourneyApp()
    journey.now = nil
    journey.frozen = false
    journey.launch()
    require("hero", in: journey.app)

    // From the face, the Digital Crown opens the Smart Stack and moves it up to its Edit button.
    XCUIDevice.shared.press(.home)
    Thread.sleep(forTimeInterval: 3)
    let edit = face.buttons["Edit"]
    for _ in 0..<3 where !(edit.exists && edit.isHittable) {
      XCUIDevice.shared.rotateDigitalCrown(delta: 1, velocity: .default)
      Thread.sleep(forTimeInterval: 6)
    }
    screenshot("smartstack-1-stack")
    XCTAssertTrue(edit.exists && edit.isHittable, "The Smart Stack has no Edit button:\n\(cells)")
    edit.tap()
    Thread.sleep(forTimeInterval: 3)

    var found = false
    for attempt in 1...3 where !found {
      let add = face.cells["Add widget"]
      XCTAssertTrue(add.waitForExistence(timeout: 10), "The editor has no Add widget:\n\(cells)")
      add.tap()
      Thread.sleep(forTimeInterval: 4)
      found = scrollToSalah()
      if !found, attempt < 3 {
        face.buttons["Close"].tap()
        Thread.sleep(forTimeInterval: 20)
      }
    }
    screenshot("smartstack-2-gallery")
    XCTAssertTrue(found, "Salah isn't in the widget gallery:\n\(cells)")
    face.cells["AppGroupCell -- Salah"].tap()
    Thread.sleep(forTimeInterval: 4)

    // Salah's page in the gallery offers its widget, Next prayer; choosing it adds it.
    let widget = face.cells["ComplicationListCell -- Next prayer"]
    screenshot("smartstack-3-salah")
    XCTAssertTrue(widget.waitForExistence(timeout: 10), "Salah's page has no widget:\n\(cells)")
    widget.tap()
    let done = face.buttons["Done"]
    XCTAssertTrue(done.waitForExistence(timeout: 10), "The editor has no Done:\n\(cells)")
    done.tap()
    Thread.sleep(forTimeInterval: 8)

    // The widget in the stack reads the next prayer, its time and the countdown, as VoiceOver
    // would: the timeline came from the settings, not the set-up message.
    let prayers = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    let next = face.descendants(matching: .any).matching(
      NSPredicate(
        format: prayers.map { _ in "label BEGINSWITH %@" }.joined(separator: " OR "),
        argumentArray: prayers.map { $0 + ", " })
    ).firstMatch
    XCTAssertTrue(next.waitForExistence(timeout: 30), "The stack has no next prayer:\n\(cells)")
    screenshot("smartstack-4-widget")
  }
}
