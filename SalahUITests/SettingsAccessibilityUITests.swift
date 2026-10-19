import XCTest

/// Names the notification volume and time-zone controls in the running app's accessibility
/// tree, and runs Xcode's accessibility audit on Settings and the menu-bar dropdown.
final class SettingsAccessibilityUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testNotificationVolumeHasEnglishAccessibleName() throws {
    try assertVolumeName(language: "english", code: "en", pane: "Notifications", name: "Volume")
  }

  @MainActor
  func testNotificationVolumeHasArabicAccessibleName() throws {
    try assertVolumeName(
      language: "arabic", code: "ar", pane: "التنبيهات", name: "مستوى الصوت")
  }

  /// Xcode's accessibility audit finds nothing in what each Settings pane shows when it opens:
  /// every control there has a description and can be found and hit, and its text has enough
  /// contrast. `isSetAside` lists, with reasons, what the test doesn't hold the panes to.
  @MainActor
  func testEverySettingsPanePassesTheAccessibilityAudit() throws {
    let app = XCUIApplication()
    app.launchArguments = SalahUITests.quietLaunch + ["-salah.debug.withoutSystemPrompts", "YES"]
    app.open(try XCTUnwrap(URL(string: "salah://settings")))
    addTeardownBlock { @MainActor in app.terminate() }

    let settings = app.windows["Salah Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 30), app.windows.debugDescription)
    var issues: [String] = []
    for pane in Self.panes {
      let tab = settings.buttons[pane]
      XCTAssertTrue(tab.waitForExistence(timeout: 10), settings.debugDescription)
      tab.click()
      let preview = settings.descendants(matching: .any)["appearance.preview"]
      let previewFrame =
        pane == "Appearance" && preview.waitForExistence(timeout: 5)
        ? preview.frame : nil
      issues += try audit(app, in: pane, window: settings, preview: previewFrame)
    }
    report(issues)
  }

  /// The time zone's pop-up, which shows only the zone, has its name for VoiceOver.
  @MainActor
  func testTheTimeZonePickerHasItsName() throws {
    let app = XCUIApplication()
    app.launchArguments = SalahUITests.quietLaunch + ["-salah.debug.withoutSystemPrompts", "YES"]
    app.open(try XCTUnwrap(URL(string: "salah://settings")))
    addTeardownBlock { @MainActor in app.terminate() }

    let settings = app.windows["Salah Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 30), app.windows.debugDescription)
    settings.buttons["Location"].click()
    let picker = settings.popUpButtons["Time zone"]
    XCTAssertTrue(picker.waitForExistence(timeout: 10), settings.debugDescription)
  }

  /// Xcode's accessibility audit finds nothing in the menu-bar dropdown, apart from what
  /// `isSetAside` lists.
  @MainActor
  func testMenuBarDropdownPassesTheAccessibilityAudit() throws {
    let app = XCUIApplication()
    app.launchArguments = SalahUITests.quietLaunch + ["-salah.debug.withoutSystemPrompts", "YES"]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }

    let statusItem = app.statusItems.firstMatch
    XCTAssertTrue(statusItem.waitForExistence(timeout: 30))
    try XCTSkipUnless(
      SalahUITests.canClick(statusItem.frame),
      "The menu bar is full: macOS put Salah's status item behind the camera housing.")
    try XCTSkipUnless(
      statusItem.isHittable,
      "The menu bar is full: macOS put Salah's status item in its overflow.")
    statusItem.click()
    XCTAssertTrue(
      app.buttons["Quit Salah"].waitForExistence(timeout: 10), app.windows.debugDescription)
    // SwiftUI exposes the MenuBarExtra's panel as a dialog, without a Window node.
    let dropdown = app.dialogs.containing(.button, identifier: "Quit Salah").firstMatch
    XCTAssertTrue(dropdown.waitForExistence(timeout: 10), app.dialogs.debugDescription)
    XCTAssertEqual(dropdown.title, "Salah")
    report(try audit(app, in: "the menu-bar dropdown", window: dropdown, preview: nil))
  }

  /// The Settings panes, by their English names.
  static let panes = [
    "General", "Location", "Calculation", "Adjustments", "Notifications", "Appearance",
  ]

  /// Runs every audit on what the app shows now, and describes each issue it finds, except
  /// those `isSetAside` lists.
  @MainActor
  private func audit(
    _ app: XCUIApplication, in place: String, window: XCUIElement?, preview: CGRect?
  ) throws -> [String] {
    var issues: [String] = []
    let windowFrame = window?.frame
    let windowTitle = window?.title
    try app.performAccessibilityAudit { issue in
      if Self.isSetAside(
        issue, windowFrame: windowFrame, windowTitle: windowTitle, preview: preview)
      {
        return true
      }
      issues.append(
        "\(place): \(issue.compactDescription). \(issue.detailedDescription)\n"
          + (issue.element?.debugDescription ?? "no element"))
      return true
    }
    return issues
  }

  /// What the test sets aside:
  /// - parts Salah doesn't draw: the system's Touch Bar element, the window's title, which
  ///   macOS draws, and the window's own content group, which has the window's frame;
  /// - the missing press action the audit reports for SwiftUI's own pop-up and disclosure
  ///   controls, and the description it wants for a slider's knob. Whether VoiceOver
  ///   operates those controls is a step in #17;
  /// - contrast of text the window's edge or scrolling cuts off, which the audit measures
  ///   against whatever covers it. The test doesn't scroll, so rows below a pane's first
  ///   screen aren't measured;
  /// - contrast of the text in the Appearance preview, which draws the widget on its themed
  ///   gradient and glows. The audit reports every text element of the preview, upcoming rows
  ///   included, so the test can't tell a real failure there from one it would report anyway.
  ///   `WidgetInkContrastTests` (SalahTests) covers that text instead: it draws the same views
  ///   in every widget state and size, for every preset and for custom themes, in light and
  ///   dark, and measures each ink against the pixels under its glyphs. It holds text to
  ///   4.5:1, glyphs to 3:1, and passed rows, which dim by design, to the 1.9:1 floor
  ///   `Design/README.md` (Widgets) documents.
  @MainActor
  private static func isSetAside(
    _ issue: XCUIAccessibilityAuditIssue, windowFrame: CGRect?, windowTitle: String?,
    preview: CGRect?
  ) -> Bool {
    guard let element = issue.element else { return false }
    let type = element.elementType
    let frame = element.frame
    if type == .touchBar { return true }
    if issue.auditType == .sufficientElementDescription, type == .group, frame == windowFrame {
      return true
    }
    if issue.auditType == .action, type == .popUpButton || type == .disclosureTriangle {
      return true
    }
    if issue.auditType == .sufficientElementDescription, type == .valueIndicator { return true }
    guard issue.auditType == .contrast else { return false }
    if let windowFrame, !windowFrame.contains(frame) { return true }
    if let windowTitle, !windowTitle.isEmpty, let windowFrame,
      element.value as? String == windowTitle,
      frame.minY < windowFrame.minY + 40
    {
      return true
    }
    if let preview, type == .staticText, preview.contains(frame) { return true }
    return false
  }

  /// Attaches the issues, and fails if there are any.
  @MainActor
  private func report(_ issues: [String]) {
    let attachment = XCTAttachment(
      string: issues.isEmpty ? "No issues" : issues.joined(separator: "\n\n"))
    attachment.name = "Accessibility audit"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n\n"))
  }

  @MainActor
  private func assertVolumeName(language: String, code: String, pane: String, name: String)
    throws
  {
    let app = XCUIApplication()
    var arguments = SalahUITests.quietLaunch
    let languageIndex = try XCTUnwrap(arguments.firstIndex(of: "-salah.appLanguage"))
    let systemLanguageIndex = try XCTUnwrap(arguments.firstIndex(of: "-AppleLanguages"))
    arguments[languageIndex + 1] = language
    arguments[systemLanguageIndex + 1] = "(\(code))"
    app.launchArguments =
      arguments + [
        "-salah.debug.withoutSystemPrompts", "YES",
        "-salah.alertVolume", "50", "-salah.silentMode", "NO",
      ]
    app.open(try XCTUnwrap(URL(string: "salah://settings")))
    addTeardownBlock { @MainActor in app.terminate() }

    let settings = app.windows.firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 30), app.windows.debugDescription)
    let notifications = settings.buttons[pane]
    XCTAssertTrue(notifications.waitForExistence(timeout: 10), settings.debugDescription)
    notifications.click()

    let volume = settings.sliders.firstMatch
    XCTAssertTrue(volume.waitForExistence(timeout: 10), settings.debugDescription)
    XCTAssertEqual(settings.sliders.count, 1, "The Notifications pane has one volume slider")
    XCTAssertEqual(volume.label, name, volume.debugDescription)
    XCTAssertTrue(volume.isEnabled)

    let attachment = XCTAttachment(string: volume.debugDescription)
    attachment.name = "Notification volume accessibility: \(code)"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
