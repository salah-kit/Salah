import AppKit
import XCTest

/// Drives the real app on this Mac under its own identity: its status item, its menu-bar
/// dropdown, its window, and the `salah://settings` link the widget opens when tapped.
///
/// The app opens its App Group container at launch, so it must be signed with a team (see
/// CONTRIBUTING.md); run it with the `SalahUITests` scheme. CI only builds this target.
final class SalahUITests: XCTestCase {
  /// The day's names as Salah shows them in Makkah, its default place: on Friday, Dhuhr is
  /// Jumu’ah.
  static var prayerNames: [String] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Riyadh") ?? .current
    let isFriday = calendar.component(.weekday, from: Date()) == 6
    return ["Fajr", "Sunrise", isFriday ? "Jumu’ah" : "Dhuhr", "Asr", "Maghrib", "Isha"]
  }

  /// Every prayer's alert off, as the JSON the app stores, in the property-list form a
  /// launch argument takes (`<hex>` is data).
  static var alertsOff: String {
    let prayers = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
    let settings = Dictionary(uniqueKeysWithValues: prayers.map { ($0, ["alertEnabled": false]) })
    let json = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
    return "<" + (json ?? Data()).map { String(format: "%02x", $0) }.joined() + ">"
  }

  /// A launch that asks for nothing: no automatic location (no location prompt) and every
  /// alert off (no notification prompt), in English, with the default menu-bar format
  /// (icon, full prayer name, time until it) whatever this Mac's Salah is set to, in a
  /// scratch preferences suite and with a notification center of the app's own (Debug
  /// builds), so none of it reaches this Mac's own Salah preferences or notifications.
  static var quietLaunch: [String] {
    [
      "-salah.autoLocation", "NO",
      "-salah.debug.scratchPreferences", "YES",
      "-salah.debug.withoutSystemNotifications", "YES",
      "-salah.onboardingCompleted", "YES",
      "-salah.notificationSettings", alertsOff,
      "-salah.appLanguage", "english",
      "-AppleLanguages", "(en)",
      "-salah.displayIcon", "YES",
      "-salah.displayNextPrayer", "YES",
      "-salah.displayNextPrayerName", "0",
      "-salah.displayNextPrayerType", "0",
    ]
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  private func launchQuietly() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = Self.quietLaunch
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    return app
  }

  /// On a Mac with a camera housing, the menu bar shows status items only beside it; an
  /// item that doesn't fit sits behind it, where a click reaches nothing. (`isHittable`
  /// covers the other way a full menu bar hides an item: in macOS's overflow, where the
  /// item's place is the overflow's control.)
  @MainActor
  static func canClick(_ frame: CGRect) -> Bool {
    guard let screen = NSScreen.screens.first,
      let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea
    else { return true }
    let housing = (left.maxX - screen.frame.minX)...(right.minX - screen.frame.minX)
    return frame.maxX <= housing.lowerBound || frame.minX >= housing.upperBound
  }

  /// The status item names Salah and the next prayer's full name, as the default menu-bar
  /// format shows it: "Salah, Asr in 2 hours, 16 minutes".
  @MainActor
  func testStatusItemShowsTheNextPrayer() {
    let app = launchQuietly()
    let statusItem = app.statusItems.firstMatch
    XCTAssertTrue(statusItem.waitForExistence(timeout: 30))
    let title = statusItem.title
    XCTAssertTrue(Self.prayerNames.contains { title.hasPrefix("Salah, \($0) ") }, title)
  }

  /// The status item opens the dropdown with the day's six prayers and Salah's controls.
  /// The window closes first, so only the dropdown can answer.
  @MainActor
  func testMenuBarDropdownShowsTheDay() throws {
    let app = launchQuietly()
    app.closeWindowToMenuBar()
    let statusItem = app.statusItems.firstMatch
    XCTAssertTrue(statusItem.waitForExistence(timeout: 30))
    try XCTSkipUnless(
      Self.canClick(statusItem.frame),
      "The menu bar is full: macOS put Salah's status item behind the camera housing.")
    try XCTSkipUnless(
      statusItem.isHittable,
      "The menu bar is full: macOS put Salah's status item in its overflow.")
    let screenshot = XCTAttachment(screenshot: statusItem.screenshot())
    screenshot.name = "Dropdown menu bar item"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    statusItem.click()

    let dropdown = app.dialogs.containing(.button, identifier: "Quit Salah").firstMatch
    XCTAssertTrue(dropdown.waitForExistence(timeout: 10), app.debugDescription)
    for prayer in Self.prayerNames {
      XCTAssertTrue(
        dropdown.staticTexts[prayer].firstMatch.waitForExistence(timeout: 10),
        "\(prayer)\n\(dropdown.debugDescription)")
    }
    XCTAssertTrue(dropdown.buttons["Open Salah"].exists, dropdown.debugDescription)
  }

  /// The dropdown's measured surface still routes each action exactly once.
  @MainActor
  func testDropdownActionsRemainOperable() throws {
    let app = XCUIApplication()
    app.launchArguments =
      Self.quietLaunch + [
        "-salah.debug.withoutSystemPrompts", "YES",
        "-salah.silentMode", "NO",
      ]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    // ⌘, with the window closed and the dropdown open: the dropdown's shortcut and the
    // app menu's Settings… both open General, so this checks what the person sees, not
    // which one answers.
    app.closeWindowToMenuBar()
    let status = app.statusItems.firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 30))
    try XCTSkipUnless(
      Self.canClick(status.frame) && status.isHittable,
      "The menu bar is full: Salah's status item cannot be clicked.")
    status.click()
    let dropdown = app.dialogs.containing(.button, identifier: "Quit Salah").firstMatch
    XCTAssertTrue(dropdown.waitForExistence(timeout: 10), app.debugDescription)
    let silent = dropdown.buttons["Mute sounds"]
    XCTAssertEqual(dropdown.buttons.matching(identifier: "Mute sounds").count, 1)
    XCTAssertFalse(silent.isSelected)
    silent.click()
    XCTAssertTrue(silent.isSelected)
    silent.click()
    XCTAssertFalse(silent.isSelected)

    let alert = dropdown.buttons["Alert for Fajr"]
    XCTAssertEqual(dropdown.buttons.matching(identifier: "Alert for Fajr").count, 1)
    XCTAssertEqual(alert.value as? String, "off")
    alert.click()
    XCTAssertEqual(alert.value as? String, "on")
    alert.click()
    XCTAssertEqual(alert.value as? String, "off")

    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(app.salahWindow.waitForExistence(timeout: 10), app.debugDescription)
    XCTAssertEqual(app.salahWindow.title, "General")
  }

  /// The link a widget tap opens brings up Salah's window in the running app, with Salah's
  /// own About and Help in its menus.
  @MainActor
  func testSettingsLinkOpensSalahsWindow() throws {
    let app = launchQuietly()
    let link = try XCTUnwrap(URL(string: "salah://settings"))
    let running = NSRunningApplication.runningApplications(
      withBundleIdentifier: "io.github.salah-kit.Salah"
    )
    .filter { !$0.isTerminated }
    XCTAssertEqual(running.count, 1)
    let original = try XCTUnwrap(running.first)
    let originalPID = original.processIdentifier
    let applicationURL = try XCTUnwrap(original.bundleURL)

    // Check the processed app bundle, not just the source plist. XCUIApplication.open
    // launches the app directly and does not prove that LaunchServices accepts its scheme.
    let bundle = try XCTUnwrap(Bundle(url: applicationURL))
    XCTAssertEqual(bundle.bundleIdentifier, "io.github.salah-kit.Salah")
    let urlTypes = try XCTUnwrap(
      bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
    let claim = try XCTUnwrap(
      urlTypes.first {
        ($0["CFBundleURLSchemes"] as? [String])?.contains(link.scheme ?? "") == true
      })
    XCTAssertEqual(claim["CFBundleURLName"] as? String, bundle.bundleIdentifier)
    XCTAssertEqual(claim["CFBundleTypeRole"] as? String, "Editor")

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = false
    configuration.allowsRunningApplicationSubstitution = false
    configuration.activates = true
    configuration.addsToRecentItems = false
    configuration.promptsUserIfNeeded = false
    let completed = expectation(description: "LaunchServices opens the Settings link")
    let receipt = SettingsLinkReceiptBox()
    XCTAssertFalse(original.isTerminated)
    NSWorkspace.shared.open([link], withApplicationAt: applicationURL, configuration: configuration)
    {
      opened, error in
      receipt.store(
        SettingsLinkReceipt(
          pid: opened?.processIdentifier, applicationURL: opened?.bundleURL,
          error: error.map { String(describing: $0) }))
      completed.fulfill()
    }
    wait(for: [completed], timeout: 15)
    let result = try XCTUnwrap(receipt.read())
    XCTAssertNil(result.error)
    XCTAssertEqual(try XCTUnwrap(result.pid), originalPID)
    XCTAssertEqual(
      try XCTUnwrap(result.applicationURL).standardizedFileURL.resolvingSymlinksInPath(),
      applicationURL.standardizedFileURL.resolvingSymlinksInPath())
    XCTAssertFalse(original.isTerminated)

    let window = app.salahWindow
    XCTAssertTrue(window.waitForExistence(timeout: 30), app.windows.debugDescription)
    XCTAssertTrue(app.menuItems["Salah Help"].exists, app.menuBars.debugDescription)
    XCTAssertTrue(app.menuItems["About Salah"].exists, app.menuBars.debugDescription)
    XCTAssertFalse(original.isTerminated)
    XCTAssertEqual(
      NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.salah-kit.Salah")
        .filter { !$0.isTerminated }.map(\.processIdentifier), [originalPID])
  }

  /// The About panel names Salah and credits its authors.
  @MainActor
  func testAboutPanelCreditsSalahsAuthors() throws {
    let app = launchQuietly()
    XCTAssertTrue(app.salahWindow.waitForExistence(timeout: 30), app.windows.debugDescription)
    app.menuBars.menuBarItems["Salah"].click()
    app.menuItems["About Salah"].click()

    let name = app.staticTexts["Salah"].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 10), app.windows.debugDescription)
    XCTAssertTrue(app.staticTexts["Version 1.1.2 (4)"].exists, app.windows.debugDescription)
    let credits = app.textViews.firstMatch
    XCTAssertTrue(credits.exists, app.windows.debugDescription)
    let text = credits.value as? String ?? ""
    XCTAssertTrue(text.contains("The Salah Kit Authors"), text)
    XCTAssertFalse(text.contains("Batoul"), text)
  }
}

private struct SettingsLinkReceipt: Sendable {
  let pid: pid_t?
  let applicationURL: URL?
  let error: String?
}

/// NSWorkspace invokes its completion on a concurrent queue; keep only value observations.
private final class SettingsLinkReceiptBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: SettingsLinkReceipt?

  func store(_ receipt: SettingsLinkReceipt) { lock.withLock { value = receipt } }
  func read() -> SettingsLinkReceipt? { lock.withLock { value } }
}
