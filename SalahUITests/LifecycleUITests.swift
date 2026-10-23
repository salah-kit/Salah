import AppKit
import XCTest

/// How the real app opens, closes and quits: it lives in the menu bar, and has a Dock icon,
/// a place in ⌘-Tab and its menus only while its window is open, hidden and minimized
/// included. ⌘Q closes the window to the menu bar; Quit Salah quits.
///
/// A Dock icon and a place in ⌘-Tab are what a regular activation policy gives an app, so
/// the tests read the policy from the running app.
final class LifecycleUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// A launch from Finder or Spotlight opens Today, with the Dock icon and Salah's menus.
  @MainActor
  func testLaunchOpensTodayWithTheDockIconAndMenus() throws {
    let app = launch()
    let window = app.salahWindow
    XCTAssertTrue(window.waitForExistence(timeout: 30), app.debugDescription)
    XCTAssertEqual(window.title, "Today")
    XCTAssertTrue(
      wait { Self.policy() == .regular }, "No Dock icon: \(String(describing: Self.policy()))")
    XCTAssertTrue(app.menuBars.menuBarItems["Window"].exists, app.menuBars.debugDescription)
    XCTAssertTrue(app.menuItems["About Salah"].exists, app.menuBars.debugDescription)
    XCTAssertTrue(app.menuItems["Salah Help"].exists, app.menuBars.debugDescription)
  }

  /// Closing the window keeps Salah in the menu bar without the Dock icon; the first time,
  /// the note hangs from the menu bar item. Finder or the Dock opens it again.
  @MainActor
  func testClosingTheWindowKeepsSalahInTheMenuBar() throws {
    let app = launch()
    XCTAssertTrue(app.salahWindow.waitForExistence(timeout: 30), app.debugDescription)
    let pid = try XCTUnwrap(Self.running()?.processIdentifier)

    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(app.salahWindow.waitForNonExistence(timeout: 10), app.debugDescription)
    XCTAssertTrue(wait { Self.policy() == .accessory }, "The Dock icon stayed")
    XCTAssertEqual(Self.running()?.processIdentifier, pid, "Salah must keep running")
    XCTAssertTrue(app.statusItems.firstMatch.exists)
    try dismissNote(in: app)

    try reopen()
    XCTAssertTrue(app.salahWindow.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertEqual(app.salahWindow.title, "Today")
    XCTAssertTrue(wait { Self.policy() == .regular }, "No Dock icon after reopening")
    XCTAssertEqual(Self.running()?.processIdentifier, pid, "Never a second copy of Salah")

    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(app.salahWindow.waitForNonExistence(timeout: 10))
    XCTAssertFalse(
      app.staticTexts["Salah is still running"].waitForExistence(timeout: 3),
      "The note shows only the first time")
  }

  /// ⌘Q closes the window to the menu bar, the last pane comes back, ⌘, opens General, and
  /// Quit Salah on Today quits.
  @MainActor
  func testCommandQClosesTheWindowAndQuitSalahQuits() throws {
    let app = launch()
    let window = app.salahWindow
    XCTAssertTrue(window.waitForExistence(timeout: 30), app.debugDescription)
    window.selectPane("Notifications")
    XCTAssertTrue(wait { window.title == "Notifications" }, window.title)

    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(window.waitForNonExistence(timeout: 10), app.debugDescription)
    XCTAssertTrue(wait { Self.policy() == .accessory })
    XCTAssertNotNil(Self.running(), "⌘Q must keep Salah running")
    try dismissNote(in: app)

    try reopen()
    XCTAssertTrue(window.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertEqual(window.title, "Notifications", "Open Salah shows the last pane")

    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(wait { window.title == "General" }, window.title)

    window.selectPane("Today")
    let quit = window.buttons["Quit Salah"]
    XCTAssertTrue(quit.waitForExistence(timeout: 10), window.debugDescription)
    quit.click()
    XCTAssertTrue(wait(timeout: 10) { Self.running() == nil }, "Quit Salah must quit")
  }

  /// A hidden or minimized window still counts as open: the Dock icon stays, and opening
  /// Salah brings the window back.
  @MainActor
  func testHidingOrMinimizingKeepsTheDockIcon() throws {
    let app = launch()
    let window = app.salahWindow
    XCTAssertTrue(window.waitForExistence(timeout: 30), app.debugDescription)

    XCTAssertTrue(wait { Self.hasWindowOnScreen() }, "The window isn't on screen")
    app.typeKey("m", modifierFlags: .command)
    XCTAssertTrue(wait { !Self.hasWindowOnScreen() }, "Not minimized")
    XCTAssertEqual(Self.policy(), .regular, "Minimized still counts as open")
    try reopen()
    XCTAssertTrue(wait { Self.hasWindowOnScreen() }, "Not restored")

    app.typeKey("h", modifierFlags: .command)
    XCTAssertTrue(wait { Self.running()?.isHidden == true }, "Not hidden")
    XCTAssertEqual(Self.policy(), .regular, "Hidden still counts as open")
    try reopen()
    XCTAssertTrue(wait { Self.running()?.isHidden == false && window.isHittable }, "Not shown")
  }

  /// The dropdown's Open Salah opens the window, and its power button quits Salah.
  @MainActor
  func testDropdownOpensSalahAndQuits() throws {
    let app = launch()
    XCTAssertTrue(app.salahWindow.waitForExistence(timeout: 30), app.debugDescription)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(app.salahWindow.waitForNonExistence(timeout: 10))
    try dismissNote(in: app)

    let status = app.statusItems.firstMatch
    try XCTSkipUnless(
      SalahUITests.canClick(status.frame) && status.isHittable,
      "The menu bar is full: Salah's status item cannot be clicked.")
    status.click()
    let dropdown = app.dialogs.containing(.button, identifier: "Quit Salah").firstMatch
    XCTAssertTrue(dropdown.waitForExistence(timeout: 10), app.debugDescription)
    dropdown.buttons["Open Salah"].click()
    XCTAssertTrue(app.salahWindow.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertTrue(wait { Self.policy() == .regular })

    status.click()
    XCTAssertTrue(dropdown.waitForExistence(timeout: 10), app.debugDescription)
    dropdown.buttons["Quit Salah"].click()
    XCTAssertTrue(wait(timeout: 10) { Self.running() == nil }, "The power button must quit")
  }

  /// A login launch stays in the menu bar: no window, no Dock icon, no change of focus.
  @MainActor
  func testLoginLaunchStaysQuiet() throws {
    let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
      targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID))
    event.setParam(
      NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
      forKeyword: AEKeyword(keyAEPropData))
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = SalahUITests.quietLaunch
    configuration.appleEvent = event
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.promptsUserIfNeeded = false

    let app = XCUIApplication(bundleIdentifier: Self.bundleIdentifier)
    app.terminate()
    let launched = expectation(description: "LaunchServices launches Salah")
    let error = ErrorBox()
    NSWorkspace.shared.openApplication(at: try Self.applicationURL(), configuration: configuration)
    { _, failure in
      error.store(failure.map { String(describing: $0) })
      launched.fulfill()
    }
    wait(for: [launched], timeout: 30)
    XCTAssertNil(error.read())
    addTeardownBlock { @MainActor in app.terminate() }

    XCTAssertTrue(app.statusItems.firstMatch.waitForExistence(timeout: 30), app.debugDescription)
    XCTAssertFalse(app.salahWindow.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(Self.policy(), .accessory, "No Dock icon")
    XCTAssertEqual(
      NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmost, "Focus moved")
  }

  // MARK: - Helpers

  static let bundleIdentifier = "io.github.salah-kit.Salah"

  @MainActor
  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = SalahUITests.quietLaunch
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    return app
  }

  /// Opens Salah as Finder, Spotlight and the Dock do while it runs.
  @MainActor
  private func reopen() throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = false
    configuration.addsToRecentItems = false
    configuration.promptsUserIfNeeded = false
    let opened = expectation(description: "LaunchServices opens Salah")
    NSWorkspace.shared.openApplication(at: try Self.applicationURL(), configuration: configuration)
    { _, _ in opened.fulfill() }
    wait(for: [opened], timeout: 15)
  }

  /// Checks the note that hangs from the menu bar item, and closes it with Got It.
  @MainActor
  private func dismissNote(in app: XCUIApplication) throws {
    let title = app.staticTexts["Salah is still running"]
    XCTAssertTrue(title.waitForExistence(timeout: 10), app.debugDescription)
    app.buttons["Got It"].click()
    XCTAssertTrue(title.waitForNonExistence(timeout: 10), app.debugDescription)
  }

  @MainActor
  private static func running() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
      .first { !$0.isTerminated }
  }

  @MainActor
  private static func policy() -> NSApplication.ActivationPolicy? {
    running()?.activationPolicy
  }

  @MainActor
  private static func applicationURL() throws -> URL {
    if let url = running()?.bundleURL { return url }
    // The app the scheme built, beside the test runner.
    let products = Bundle(for: LifecycleUITests.self).bundleURL
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = products.appending(path: "Salah.app")
    try XCTSkipUnless(
      FileManager.default.fileExists(atPath: url.path), "No Salah.app at \(url.path)")
    return url
  }

  /// Whether Salah has a window on screen: not minimized, hidden or closed. The window
  /// server lists every window; the menu bar's own are thin or off screen.
  @MainActor
  private static func hasWindowOnScreen() -> Bool {
    guard let pid = running()?.processIdentifier,
      let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]]
    else { return false }
    return windows.contains { window in
      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
      return window[kCGWindowOwnerPID as String] as? pid_t == pid
        && window[kCGWindowLayer as String] as? Int == 0 && (bounds["Height"] ?? 0) > 100
    }
  }

  @MainActor
  private func wait(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return condition()
  }
}

extension XCUIApplication {
  /// Salah's one window, whatever pane it shows.
  var salahWindow: XCUIElement { windows["salah.window"] }

  /// Closes the window that a launch opens, so Salah is in the menu bar only, and closes the
  /// note if it shows.
  @MainActor
  func closeWindowToMenuBar() {
    XCTAssertTrue(salahWindow.waitForExistence(timeout: 30), debugDescription)
    typeKey("w", modifierFlags: .command)
    XCTAssertTrue(salahWindow.waitForNonExistence(timeout: 10), debugDescription)
    let gotIt = buttons["Got It"]
    if gotIt.waitForExistence(timeout: 5) { gotIt.click() }
  }
}

extension XCUIElement {
  /// A pane's row in the window's sidebar.
  func paneRow(_ name: String) -> XCUIElement {
    outlines.firstMatch.staticTexts[name].firstMatch
  }

  /// Selects a pane in the window's sidebar. It clicks the row at its name: the row, not
  /// the text, is what a hit test finds there.
  func selectPane(_ name: String) {
    let row = paneRow(name)
    XCTAssertTrue(row.waitForExistence(timeout: 10), debugDescription)
    row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
  }
}

/// NSWorkspace calls back on a concurrent queue; keep only the error's description.
private final class ErrorBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: String?

  func store(_ error: String?) { lock.withLock { value = error } }
  func read() -> String? { lock.withLock { value } }
}
