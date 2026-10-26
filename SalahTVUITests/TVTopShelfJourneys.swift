import XCTest

/// The Top Shelf on the Home Screen. The system runs Salah's extension, which draws the
/// banners from the settings the app mirrors into the App Group, at the real time; a
/// banner's link opens the app there.
nonisolated final class TVTopShelfJourneys: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  func testTheTopShelfShowsTheDayAndOpensTheRoomDisplay() {
    let journey = TVJourneyApp()
    journey.launch()
    let app = journey.app
    // Salah mirrors Makkah's settings when it shows them.
    require("hero", in: app)
    remote.press(.home)
    XCTAssertTrue(waitUntil { app.state != .runningForeground }, "Home didn't leave Salah")

    let home = XCUIApplication(bundleIdentifier: "com.apple.HeadBoard")
    let icon = home.icons.matching(NSPredicate(format: "label == %@", "Salah")).firstMatch
    XCTAssertTrue(icon.waitForExistence(timeout: 10), home.debugDescription)
    for _ in 0..<6 where !icon.hasFocus {
      let current = focused(in: home)
      remote.press(current.exists && icon.frame.minX < current.frame.minX ? .left : .right)
      _ = waitUntil(timeout: 2) { icon.hasFocus }
    }
    XCTAssertTrue(icon.hasFocus, "Salah's icon didn't take focus.\n\(home.debugDescription)")

    // The next prayer's eyebrow says Tomorrow after Isha, which depends on the real time.
    let banners = home.cells.matching(identifier: "BannerTopShelfCell")
    let next = banners.matching(
      NSPredicate(
        format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Next prayer · Makkah, ",
        "Tomorrow · Makkah, ")
    ).firstMatch
    let today = banners.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Today · Makkah, Today’s prayers, Fajr ")
    ).firstMatch
    let room = banners.matching(
      NSPredicate(format: "label == %@", "Room display, Today’s times, all day")
    ).firstMatch
    XCTAssertTrue(next.waitForExistence(timeout: 20), home.debugDescription)
    XCTAssertTrue(today.exists, home.debugDescription)
    XCTAssertTrue(room.exists, home.debugDescription)
    captureScreen("top-shelf")

    remote.press(.up)
    let inShelf = banners.matching(NSPredicate(format: "hasFocus == true")).firstMatch
    XCTAssertTrue(waitUntil { inShelf.exists }, "Up didn't reach the Top Shelf")
    moveFocus(.right, to: room, in: home, maximumPresses: 3)
    captureScreen("top-shelf-room-display")
    remote.press(.select)
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "The banner didn't open Salah")
    require("room", in: app)
    require("room.cell.isha", in: app)
  }
}
