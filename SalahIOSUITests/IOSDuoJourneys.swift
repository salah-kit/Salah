import XCTest

/// Run on iPhone Duo, closed. The outer display's side bar holds the tabs and the screens' icon
/// controls, Back included, beside the content, in either language. `IOSDuoPoseJourneys`
/// covers the poses that need Device Hub.
nonisolated final class IOSDuoJourneys: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  func testSideBarHoldsTheTabsAndIconControlsBesideTheContent() {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    let bar = sideBar(in: app)
    expect(require("today.nextPrayer", in: app), isBeside: bar)
    expect(require("today.dayList", in: app), isBeside: bar)
    capture("Duo-English-Outer-Today", in: app)

    tap("tab.times", in: app)
    expect(require("times.dayList", in: app), isBeside: bar)
    expect(require("times.calendar", in: app), isIn: bar)
    tap("times.calendar", in: app)
    // The sheet's icon action moves to the bar too; its text action stays in the sheet.
    expect(require("times.calendar.done", in: app), isIn: bar)
    let day = app.buttons["Thursday, June 4"].firstMatch
    XCTAssertTrue(day.waitForExistence(timeout: 5), app.debugDescription)
    day.tap()
    capture("Duo-English-Outer-Calendar", in: app)
    tap("times.calendar.done", in: app)
    XCTAssertTrue(waitUntil { self.value("times.date", in: app).contains("June 4") })

    tap("tab.settings", in: app)
    tap("settings.method", in: app)
    expect(require("method.automatic", in: app), isBeside: bar)
    expect(require("BackButton", in: app), isIn: bar)
    capture("Duo-English-Outer-Calculation", in: app)
    back(in: app)
    XCTAssertTrue(require("settings.method", in: app).isHittable)
  }

  @MainActor
  func testArabicKeepsTheSideBarAtTheDisplaysEdge() {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    let englishTab = require("tab.today", in: app).frame
    tap("tab.settings", in: app)
    tap("settings.language", in: app)
    tap("language.arabic", in: app)
    back(in: app)
    tap("tab.today", in: app)
    XCTAssertTrue(
      require("today.name", in: app).label.unicodeScalars.contains {
        (0x0600...0x06FF).contains(Int($0.value))
      }, "Today is in Arabic")
    let bar = sideBar(in: app)
    // The bar belongs to the display, not the reading direction.
    XCTAssertEqual(require("tab.today", in: app).frame.midX, englishTab.midX, accuracy: 1)
    expect(require("today.nextPrayer", in: app), isBeside: bar)
    capture("Duo-Arabic-Outer-Today", in: app)

    tap("tab.times", in: app)
    expect(require("times.calendar", in: app), isIn: bar)
    tap("tab.settings", in: app)
    tap("settings.method", in: app)
    expect(require("BackButton", in: app), isIn: bar)
    capture("Duo-Arabic-Outer-Calculation", in: app)
    back(in: app)
    XCTAssertTrue(require("settings.method", in: app).isHittable)
  }

  /// The side bar, found from the tabs it holds one above another: it runs from the display's
  /// edge past them, and it's at least 84 points wide.
  @MainActor
  private func sideBar(
    in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) -> CGRect {
    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 15), file: file, line: line)
    let tabs = ["tab.today", "tab.times", "tab.qibla", "tab.settings"].map {
      require($0, in: app, file: file, line: line).frame
    }
    for (upper, lower) in zip(tabs, tabs.dropFirst()) {
      XCTAssertEqual(
        upper.midX, lower.midX, accuracy: 1, "Run IOSDuoJourneys on iPhone Duo, closed",
        file: file, line: line)
      XCTAssertLessThan(upper.midY, lower.midY, file: file, line: line)
    }
    let column = tabs.dropFirst().reduce(tabs[0]) { $0.union($1) }
    XCTAssertGreaterThan(
      column.minX, window.frame.midX, "The bar is at the display's right edge", file: file,
      line: line)
    let edge = min(column.minX, window.frame.maxX - 84)
    return CGRect(
      x: edge, y: window.frame.minY, width: window.frame.maxX - edge,
      height: window.frame.height)
  }

  @MainActor
  private func expect(
    _ content: XCUIElement, isBeside bar: CGRect, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertLessThanOrEqual(
      content.frame.maxX, bar.minX, "\(content.identifier) reaches into the side bar",
      file: file, line: line)
    XCTAssertGreaterThanOrEqual(
      content.frame.minX, 16, "\(content.identifier) has no margin", file: file, line: line)
  }

  @MainActor
  private func expect(
    _ control: XCUIElement, isIn bar: CGRect, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(
      (bar.minX...bar.maxX).contains(control.frame.midX),
      "\(control.identifier) is not in the side bar", file: file, line: line)
  }
}
