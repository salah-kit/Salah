import AppKit
import XCTest

/// Drives the real app on this Mac under its own identity: its status item, its menu-bar
/// dropdown, and the `salah://settings` link the widget opens when tapped.
///
/// The app opens its App Group container at launch, so it must be signed with a team (see
/// CONTRIBUTING.md); run it with the `SalahUITests` scheme. CI only builds this target.
final class SalahUITests: XCTestCase {
  static let prayerNames = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]

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

  /// The status item shows the next prayer's full name, as the default menu-bar format does.
  @MainActor
  func testStatusItemShowsTheNextPrayer() {
    let app = launchQuietly()
    let statusItem = app.statusItems.firstMatch
    XCTAssertTrue(statusItem.waitForExistence(timeout: 30))
    let title = statusItem.title
    XCTAssertTrue(Self.prayerNames.contains { title.hasPrefix($0 + " ") }, title)
  }

  /// The status item opens the dropdown with the day's six prayers and Salah's controls.
  @MainActor
  func testMenuBarDropdownShowsTheDay() throws {
    let app = launchQuietly()
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

    for prayer in Self.prayerNames {
      XCTAssertTrue(
        app.staticTexts[prayer].firstMatch.waitForExistence(timeout: 10),
        "\(prayer)\n\(app.windows.debugDescription)")
    }
    XCTAssertTrue(app.buttons["Quit Salah"].exists, app.windows.debugDescription)
  }

  /// The link a widget tap opens brings up Settings, which carries Salah's name: the
  /// window title, the sidebar's help and about rows and the version.
  @MainActor
  func testSettingsLinkOpensSalahSettings() throws {
    let app = launchQuietly()
    let link = try XCTUnwrap(URL(string: "salah://settings"))
    app.open(link)

    let settings = app.windows["Salah Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 30), app.windows.debugDescription)
    XCTAssertTrue(settings.buttons["Salah Help"].exists, settings.debugDescription)
    XCTAssertTrue(settings.buttons["About Salah"].exists, settings.debugDescription)
    XCTAssertTrue(settings.staticTexts["Salah 1.1.2"].exists, settings.debugDescription)
  }

  /// The About panel names Salah and credits its authors.
  @MainActor
  func testAboutPanelCreditsSalahsAuthors() throws {
    let app = launchQuietly()
    let link = try XCTUnwrap(URL(string: "salah://settings"))
    app.open(link)
    let settings = app.windows["Salah Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 30), app.windows.debugDescription)
    settings.buttons["About Salah"].click()

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
