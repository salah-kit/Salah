import XCTest

/// Names the notification volume control in the running app's accessibility tree.
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
