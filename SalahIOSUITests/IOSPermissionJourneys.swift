import XCTest

/// Run each permission journey on a fresh app installation. iOS provides no XCTest
/// reset for notification authorization; resetting preferences does not reset consent.
nonisolated final class IOSPermissionJourneys: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  func testNotificationDeniedKeepsManualCityAndCompletesSetup() {
    let journey = IOSJourneyApp(fixture: false, skipOnboarding: false)
    journey.app.resetAuthorizationStatus(for: .location)
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    require("onboarding.continue", in: app)
    capture("iPhone-English-Onboarding-Welcome", in: app)
    tap("onboarding.continue", in: app)
    tap("onboarding.location.allow", in: app)
    answerPermission(allow: false, resource: .location)
    selectCity("Makkah, Saudi Arabia", matching: "Makkah", in: app)
    tap("onboarding.notification.allow", in: app)
    answerPermission(allow: false, resource: .notification)
    require("onboarding.notification.continueWithout", in: app)
    capture("iPhone-English-Onboarding-Notifications-Denied", in: app)
    tap("onboarding.notification.continueWithout", in: app)
    tap("onboarding.calculation.continue", in: app)
    tap("onboarding.ready.start", in: app)
    XCTAssertTrue(cityMatches("Makkah", label: require("today.location", in: app).label))
    require("today.nextPrayer", in: app)

    journey.relaunch()
    XCTAssertFalse(element("onboarding.continue", in: app).exists)
    XCTAssertTrue(cityMatches("Makkah", label: require("today.location", in: app).label))
    require("today.nextPrayer", in: app)
  }

  @MainActor
  func testLocationAndNotificationsAllowCompleteSetup() {
    let journey = IOSJourneyApp(fixture: false, skipOnboarding: false)
    journey.app.resetAuthorizationStatus(for: .location)
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    require("onboarding.continue", in: app)
    capture("iPhone-English-Onboarding-Welcome", in: app)
    tap("onboarding.continue", in: app)
    capture("iPhone-English-Onboarding-Location", in: app)
    tap("onboarding.location.allow", in: app)
    answerPermission(allow: true, resource: .location)
    require("onboarding.notification.allow", in: app, timeout: 60)
    capture("iPhone-English-Onboarding-Notifications", in: app)
    tap("onboarding.notification.allow", in: app)
    answerPermission(allow: true, resource: .notification)
    require("onboarding.calculation.continue", in: app)
    XCTAssertFalse(element("onboarding.notification.continueWithout", in: app).exists)
    capture("iPhone-English-Onboarding-Calculation", in: app)
    tap("onboarding.calculation.continue", in: app)
    capture("iPhone-English-Onboarding-Ready", in: app)
    tap("onboarding.ready.start", in: app)
    XCTAssertFalse(require("today.location", in: app).label.isEmpty)
    require("today.nextPrayer", in: app)
    capture("iPhone-English-Onboarding-Complete", in: app)

    tap("tab.settings", in: app)
    tap("settings.alerts", in: app)
    assertNativeAlertsAreScheduled(in: app)

    journey.relaunch()
    XCTAssertFalse(element("onboarding.continue", in: app).exists)
    require("today.nextPrayer", in: app)
  }

  /// A settings grant does not change any saved preference. Scheduling therefore
  /// has to react to the real authorization transition itself, in this process.
  @MainActor
  func testSettingsPermissionGrantSchedulesSavedAlertsImmediately() {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    require("today.nextPrayer", in: app)
    tap("tab.settings", in: app)
    tap("settings.alerts", in: app)
    require("alerts.permission", in: app)
    XCTAssertFalse(element("alerts.scheduledCount", in: app).exists)
    tap("alerts.permission", in: app)
    answerPermission(allow: true, resource: .notification)
    assertNativeAlertsAreScheduled(in: app)
    XCTAssertFalse(element("alerts.permission", in: app).exists)
    capture("iPhone-English-Notifications-Scheduled-After-Settings-Grant", in: app)
  }

  @MainActor
  func testDeniedNotificationsRecoverFromSystemSettings() {
    let journey = IOSJourneyApp(fixture: false, skipOnboarding: false)
    journey.launch()
    let app = journey.app
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    defer {
      app.terminate()
      settings.terminate()
    }

    tap("onboarding.continue", in: app)
    tap("onboarding.location.chooseCity", in: app)
    selectCity("Makkah, Saudi Arabia", matching: "Makkah", in: app)
    tap("onboarding.notification.allow", in: app)
    answerPermission(allow: false, resource: .notification)
    require("onboarding.notification.openSettings", in: app)
    tap("onboarding.notification.openSettings", in: app)
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15))

    let allow = settings.switches.matching(
      NSPredicate(
        format: "identifier == %@ OR label == %@", "ALLOW_NOTIFICATIONS_ID", "Allow Notifications")
    ).firstMatch
    if !allow.exists && !allow.waitForExistence(timeout: 4) {
      // iOS 27 Simulator can leave a public Settings URL pending at its root.
      // Follow the measured Settings → Apps → exact Salah bundle route; this
      // journey proves real authorization and reconciliation on returning.
      let appSettings = settings.navigationBars["Salah"].firstMatch
      if !appSettings.exists {
        let appsPage = settings.navigationBars["Apps"].firstMatch
        if !appsPage.exists {
          let root = settings.navigationBars["Settings"].firstMatch
          XCTAssertTrue(
            root.exists || root.waitForExistence(timeout: 10),
            "Expected the Settings root or its retained Apps list.\n\(settings.debugDescription)")
          captureSystem("System-Settings-Root-Pending-Destination")
          tap("com.apple.settings.apps", in: settings)
        }
        XCTAssertTrue(
          appsPage.exists || appsPage.waitForExistence(timeout: 10),
          "The measured fallback must reach the Apps list.\n\(settings.debugDescription)")
        captureSystem("System-Settings-Apps-List-For-Salah")
        tap("io.github.salah-kit.Salah.iOS", in: settings)
      }
      XCTAssertTrue(
        appSettings.exists || appSettings.waitForExistence(timeout: 10),
        "The selected app settings must belong to Salah.\n\(settings.debugDescription)"
      )
      captureSystem("System-Settings-Salah-App-Selected")
      let identifiedNotifications = settings.buttons["NOTIFICATIONS"].firstMatch
      let notificationsButton =
        identifiedNotifications.exists
        ? identifiedNotifications : settings.buttons["Notifications"].firstMatch
      let notifications =
        notificationsButton.exists
        ? notificationsButton
        : settings.cells.containing(.staticText, identifier: "Notifications").firstMatch
      XCTAssertTrue(
        notifications.exists || notifications.waitForExistence(timeout: 10),
        settings.debugDescription)
      notifications.tap()
    }
    XCTAssertTrue(allow.exists || allow.waitForExistence(timeout: 10), settings.debugDescription)
    if (allow.value as? String) != "1" {
      let thumb = allow.switches.firstMatch
      (thumb.exists ? thumb : allow).tap()
    }
    XCTAssertTrue(waitUntil { (allow.value as? String) == "1" })
    captureSystem("System-Settings-Notifications-Enabled-After-Denial")

    app.activate()
    require("onboarding.calculation.continue", in: app)
    XCTAssertFalse(element("onboarding.notification.continueWithout", in: app).exists)
    capture("iPhone-English-Onboarding-Recovered-From-System-Settings", in: app)
    tap("onboarding.calculation.continue", in: app)
    tap("onboarding.ready.start", in: app)
    XCTAssertTrue(cityMatches("Makkah", label: require("today.location", in: app).label))
    require("today.nextPrayer", in: app)
  }

  @MainActor
  private func assertNativeAlertsAreScheduled(in app: XCUIApplication) {
    let count = element("alerts.scheduledCount", in: app)
    reveal(count, in: app)
    XCTAssertTrue(
      count.waitForExistence(timeout: 30),
      "The native scheduling read-back must finish after authorization")
    XCTAssertTrue(
      waitUntil(timeout: 30) { (Int(count.value as? String ?? "") ?? 0) > 0 },
      "Saved alerts must be confirmed in UNUserNotificationCenter without relaunching the app")
  }

  private enum Resource { case location, notification }

  @MainActor
  private func answerPermission(allow: Bool, resource: Resource) {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let alert = springboard.alerts.firstMatch
    XCTAssertTrue(
      alert.waitForExistence(timeout: 15),
      "Expected a real \(resource) permission alert. Run this journey after a fresh installation.")
    captureSystem("System-\(resource)-\(allow ? "Allow" : "Deny")")
    let button: XCUIElement
    if !allow {
      button =
        alert.buttons.matching(
          NSPredicate(format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] %@", "Don", "Allow")
        ).firstMatch
    } else if resource == .location {
      button =
        alert.buttons.matching(
          NSPredicate(format: "label CONTAINS[c] %@", "While Using")
        ).firstMatch
    } else {
      button = alert.buttons["Allow"].firstMatch
    }
    XCTAssertTrue(button.exists, alert.debugDescription)
    button.tap()
    XCTAssertTrue(waitUntil { !alert.exists }, "The system permission alert must close")
  }
}
