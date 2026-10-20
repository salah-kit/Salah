import XCTest

/// Checks Settings controls and the Appearance preview in the running app's accessibility
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

  @MainActor
  func testAppearancePreviewUsesMeasuredDesktopHeightsInEnglish() throws {
    try assertAppearancePreviewSizes(
      language: "english", code: "en", pane: "Appearance", sizeLabel: "Size",
      names: ["Small", "Medium", "Large"])
  }

  @MainActor
  func testAppearancePreviewUsesMeasuredDesktopHeightsInArabic() throws {
    try assertAppearancePreviewSizes(
      language: "arabic", code: "ar", pane: "المظهر", sizeLabel: "الحجم",
      names: ["صغير", "متوسط", "كبير"])
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

  @MainActor
  func testDropdownDurationHasEnglishTextSemantics() throws {
    try assertDurationTextSemantics(language: VoiceOverSpeechUITests.english)
  }

  @MainActor
  func testDropdownDurationHasArabicTextSemantics() throws {
    try assertDurationTextSemantics(language: VoiceOverSpeechUITests.arabic)
  }

  /// Uses only the existing pure schedule/language fixtures. It never creates a
  /// speech service or changes screen-reader state.
  @MainActor
  private func assertDurationTextSemantics(language: VoiceOverSpeechUITests.Language) throws {
    let app = XCUIApplication()
    app.launchArguments = VoiceOverSpeechUITests.launch([
      "-salah.appLanguage": language.setting,
      "-AppleLanguages": "(\(language.code))",
    ])
    let start = Date()
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    let status = app.statusItems.firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 30))
    try XCTSkipUnless(
      SalahUITests.canClick(status.frame) && status.isHittable,
      "The menu bar is full: Salah's status item cannot be clicked.")

    var issues: [String] = []
    for opening in 1...2 {
      status.click()
      let dropdown = app.dialogs.containing(.button, identifier: language.quit).firstMatch
      XCTAssertTrue(dropdown.waitForExistence(timeout: 10), app.debugDescription)
      let query = dropdown.descendants(matching: .any).matching(identifier: "menu.hero.duration")
      XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 10), dropdown.debugDescription)
      XCTAssertEqual(query.count, 1, dropdown.debugDescription)
      let duration = query.firstMatch
      XCTAssertEqual(duration.elementType, .staticText, duration.debugDescription)
      XCTAssertEqual(dropdown.staticTexts.matching(identifier: "menu.hero.duration").count, 1)
      XCTAssertEqual(duration.descendants(matching: .any).count, 0)
      // AppKit exposes a static text element's content as AXValue.
      let text = try XCTUnwrap(duration.value as? String, duration.debugDescription)
      let expected = VoiceOverSpeechUITests.countdowns(
        from: start.addingTimeInterval(-60), to: Date(), in: language)
      XCTAssertTrue(expected.contains(text), "\(text)\nExpected: \(expected)")
      // The duration still follows the focus name visually; its element remains
      // in the hero rather than moving to the bottom of the dialog.
      let prayer = try XCTUnwrap(text.components(separatedBy: " · ").first)
      let name = dropdown.staticTexts[prayer].firstMatch
      XCTAssertTrue(name.exists, dropdown.debugDescription)
      XCTAssertGreaterThanOrEqual(duration.frame.minY, name.frame.maxY - 1)
      XCTAssertLessThan(duration.frame.maxY, dropdown.buttons[language.quit].frame.minY)
      let elements = dropdown.descendants(matching: .any).allElementsBoundByAccessibilityElement
      let nameIndex = try XCTUnwrap(
        elements.firstIndex { $0.elementType == .staticText && $0.value as? String == prayer })
      let durationIndex = try XCTUnwrap(
        elements.firstIndex { $0.identifier == "menu.hero.duration" })
      let quitIndex = try XCTUnwrap(
        elements.firstIndex { $0.elementType == .button && $0.label == language.quit })
      XCTAssertLessThan(nameIndex, durationIndex)
      XCTAssertLessThan(durationIndex, quitIndex)
      let attachment = XCTAttachment(string: dropdown.debugDescription)
      attachment.name = "Dropdown text semantics \(language.code), opening \(opening)"
      attachment.lifetime = .keepAlways
      add(attachment)
      let screenshot = XCTAttachment(screenshot: dropdown.screenshot())
      screenshot.name = "Dropdown \(language.code), opening \(opening)"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      issues += try audit(app, in: "dropdown \(language.code)", window: dropdown, preview: nil)
      status.click()
      XCTAssertTrue(
        dropdown.waitForNonExistence(timeout: 5), "Closing the dropdown must remove its duration")
    }
    report(issues)
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

  /// Switches the running Appearance pane through all three sizes. The preview's
  /// accessibility container fills the form's width; only its height is the widget's
  /// measured height. The rendered regression checks the exact widget width separately.
  @MainActor
  private func assertAppearancePreviewSizes(
    language: String, code: String, pane: String, sizeLabel: String, names: [String]
  ) throws {
    let app = XCUIApplication()
    var arguments = SalahUITests.quietLaunch
    let languageIndex = try XCTUnwrap(arguments.firstIndex(of: "-salah.appLanguage"))
    let systemLanguageIndex = try XCTUnwrap(arguments.firstIndex(of: "-AppleLanguages"))
    arguments[languageIndex + 1] = language
    arguments[systemLanguageIndex + 1] = "(\(code))"
    app.launchArguments = arguments + ["-salah.debug.withoutSystemPrompts", "YES"]
    app.open(try XCTUnwrap(URL(string: "salah://settings")))
    addTeardownBlock { @MainActor in app.terminate() }

    let settings = app.windows.firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 30), app.windows.debugDescription)
    let appearance = settings.buttons[pane]
    XCTAssertTrue(appearance.waitForExistence(timeout: 10), settings.debugDescription)
    appearance.click()

    let sizes = settings.radioGroups[sizeLabel]
    XCTAssertTrue(sizes.waitForExistence(timeout: 10), settings.debugDescription)
    XCTAssertEqual(sizes.radioButtons.count, 3, sizes.debugDescription)
    let preview = settings.descendants(matching: .any)["appearance.preview"]
    XCTAssertTrue(preview.waitForExistence(timeout: 10), settings.debugDescription)
    XCTAssertEqual(Self.isSelected(sizes.radioButtons[names[1]]), true)
    let initialTextCount = preview.staticTexts.count
    XCTAssertGreaterThan(initialTextCount, 0, preview.debugDescription)

    var smallTextCount = 0
    for (index, name) in names.enumerated() {
      let segment = sizes.radioButtons[name]
      XCTAssertTrue(segment.isEnabled, segment.debugDescription)
      XCTAssertTrue(segment.isHittable, segment.debugDescription)
      segment.click()
      let height: CGFloat = index == 2 ? 344 : 164
      let updated = Self.waitForAppearanceUpdate {
        guard Self.isSelected(segment) == true, abs(preview.frame.height - height) <= 0.5
        else { return false }
        switch index {
        case 0: return preview.staticTexts.count < initialTextCount
        case 1: return preview.staticTexts.count > smallTextCount
        default: return true
        }
      }
      attachAppearancePreview(settings: settings, preview: preview, code: code, size: name)
      XCTAssertTrue(updated, "The \(name) selection must update the preview's content and height")
      XCTAssertEqual(preview.frame.height, height, accuracy: 0.5, preview.debugDescription)
      for (otherIndex, otherName) in names.enumerated() {
        XCTAssertEqual(
          Self.isSelected(sizes.radioButtons[otherName]), otherIndex == index,
          sizes.debugDescription)
      }

      let windowBounds = settings.frame.insetBy(dx: -0.5, dy: -0.5)
      let previewBounds = preview.frame.insetBy(dx: -0.5, dy: -0.5)
      XCTAssertTrue(windowBounds.contains(preview.frame), settings.debugDescription)
      XCTAssertTrue(windowBounds.contains(sizes.frame), sizes.debugDescription)
      let texts = preview.staticTexts.allElementsBoundByIndex
      XCTAssertFalse(texts.isEmpty, preview.debugDescription)
      for text in texts {
        let frame = text.frame
        XCTAssertGreaterThan(frame.width, 0, text.debugDescription)
        XCTAssertGreaterThan(frame.height, 0, text.debugDescription)
        XCTAssertTrue(previewBounds.contains(frame), text.debugDescription)
        XCTAssertTrue(windowBounds.contains(frame), text.debugDescription)
      }
      if index == 0 { smallTextCount = texts.count }
    }
  }

  @MainActor
  private func attachAppearancePreview(
    settings: XCUIElement, preview: XCUIElement, code: String, size: String
  ) {
    let screenshot = XCTAttachment(screenshot: settings.screenshot())
    screenshot.name = "Appearance preview: \(code), \(size)"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    let tree = XCTAttachment(string: settings.debugDescription + "\n\n" + preview.debugDescription)
    tree.name = "Appearance accessibility: \(code), \(size)"
    tree.lifetime = .keepAlways
    add(tree)
  }

  /// Native segmented controls report selection as either a number or its string form.
  @MainActor
  private static func isSelected(_ segment: XCUIElement) -> Bool? {
    switch segment.value {
    case let number as NSNumber: return number.boolValue
    case let text as String:
      switch text {
      case "1": return true
      case "0": return false
      default: return nil
      }
    default: return nil
    }
  }

  @MainActor
  private static func waitForAppearanceUpdate(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    repeat {
      if condition() { return true }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return condition()
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
