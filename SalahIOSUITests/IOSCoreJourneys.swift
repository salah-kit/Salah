import XCTest

/// Core iPhone construction, navigation, saved preferences and accessibility in the
/// installed app. Prayer arithmetic and notification planning have focused unit tests.
nonisolated final class IOSCoreJourneys: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  func testCityAndCalculationChoicesSurviveRelaunch() {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    require("today.nextPrayer", in: app)
    XCTAssertFalse(require("today.name", in: app).label.isEmpty)
    XCTAssertFalse(value("today.countdown", in: app).isEmpty)
    XCTAssertTrue(require("today.location", in: app).label.contains("Makkah"))
    capture("iPhone-English-Today", in: app)

    tap("tab.settings", in: app)
    tap("settings.location", in: app)
    selectCity("London, United Kingdom", matching: "London", in: app)
    back(in: app)
    tap("settings.method", in: app)
    setSwitch("method.automatic", to: false, in: app)
    tap("method.muslimWorldLeague", in: app)
    capture("iPhone-English-Calculation", in: app)
    back(in: app)

    journey.relaunch()
    XCTAssertTrue(require("today.location", in: app).label.contains("London"))
    tap("tab.settings", in: app)
    XCTAssertTrue(require("settings.method", in: app).label.contains("Muslim World League"))
    tap("settings.method", in: app)
    XCTAssertEqual(switchValue("method.automatic", in: app), false)
    let selectedMethod = require("method.muslimWorldLeague", in: app)
    XCTAssertTrue(
      selectedMethod.isSelected || (selectedMethod.value as? String) == "Selected",
      "The persisted calculation method must be selected when the screen is reconstructed")
    capture("iPhone-English-Calculation-Persisted", in: app)
  }

  @MainActor
  func testCitySearchRemainsSelectableAfterBackgroundAndReturn() {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    tap("tab.settings", in: app)
    tap("settings.location", in: app)
    let query = "London, United Kingdom"
    searchCity(query, matching: "London", in: app)
    XCTAssertEqual(value("location.searchField", in: app), query)
    func processIdentifier() -> Int? {
      let description = app.debugDescription
      guard let range = description.range(of: #"\bpid: [0-9]+"#, options: .regularExpression) else {
        return nil
      }
      return description[range].split(separator: " ").last.flatMap { Int($0) }
    }
    let originalProcess = processIdentifier()
    let beforeHome = app.state.rawValue
    XCUIDevice.shared.press(.home)
    let immediatelyAfterHome = app.state.rawValue
    // Application state is passively monitored. XCTest's waiter services its
    // updates; a main-thread sleep loop can keep returning the cached foreground state.
    let background = XCTNSPredicateExpectation(
      predicate: NSPredicate(
        format: "state == %lu OR state == %lu",
        XCUIApplication.State.runningBackground.rawValue,
        XCUIApplication.State.runningBackgroundSuspended.rawValue),
      object: app)
    let backgroundResult = XCTWaiter.wait(for: [background], timeout: 10)
    XCTAssertEqual(
      backgroundResult, .completed,
      "Expected live background state; raw state before Home=\(beforeHome), immediately after=\(immediatelyAfterHome), after wait=\(app.state.rawValue)"
    )
    captureSystem("iPhone-Home-City-Search-In-Background")
    app.activate()
    let returnedProcess = processIdentifier()
    // activate() preserves an already running app by its documented contract.
    // Compare observed PIDs when available without making the diagnostic text
    // format itself a requirement of the app or this journey.
    if let originalProcess, let returnedProcess {
      XCTAssertEqual(returnedProcess, originalProcess, "Returning must reactivate the same process")
    }
    XCTContext.runActivity(named: "Background round-trip process identity") { activity in
      let attachment = XCTAttachment(
        string:
          "Observed PID before=\(String(describing: originalProcess)), after=\(String(describing: returnedProcess)); state after activation=\(app.state.rawValue)"
      )
      attachment.lifetime = .keepAlways
      activity.add(attachment)
    }
    XCTAssertEqual(value("location.searchField", in: app), query)
    requireCityResult("London", in: app).tap()
    tap("tab.today", in: app)
    XCTAssertTrue(require("today.location", in: app).label.contains("London"))
    require("today.nextPrayer", in: app)
    capture("iPhone-English-City-Selected-After-Background", in: app)
  }

  @MainActor
  func testIndependentBeforeAfterFridayAndMutePreferencesSurviveRelaunch() {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    tap("tab.settings", in: app)
    tap("settings.alerts", in: app)
    tap("alerts.fajr", in: app)
    setSwitch("alert.fajr.before.enabled", to: true, in: app)
    increment("alert.fajr.before.minutes", in: app)
    let beforeMinutes = value("alert.fajr.before.minutes", in: app)
    tap("alert.fajr.before.sound", in: app)
    tap("sound.option.softTone", in: app)
    back(in: app)
    let beforeSound = require("alert.fajr.before.sound", in: app).label
    setSwitch("alert.fajr.after.enabled", to: true, in: app)
    increment("alert.fajr.after.minutes", in: app)
    let afterMinutes = value("alert.fajr.after.minutes", in: app)
    tap("alert.fajr.after.sound", in: app)
    tap("sound.option.none", in: app)
    back(in: app)
    let afterSound = require("alert.fajr.after.sound", in: app).label
    XCTAssertNotEqual(beforeMinutes, afterMinutes, "Before and after own independent offsets")
    XCTAssertNotEqual(beforeSound, afterSound, "Each alert slot owns its own sound")
    capture("iPhone-English-Fajr-Before-After", in: app)
    back(in: app)

    tap("alerts.jumuah", in: app)
    setSwitch("alert.fridayOverride", to: true, in: app)
    setSwitch("alert.jumuah.before.enabled", to: true, in: app)
    capture("iPhone-English-Friday-Override", in: app)
    back(in: app)
    back(in: app)
    tap("settings.sound", in: app)
    setSwitch("sound.mute", to: true, in: app)
    XCTAssertFalse(require("sound.dua", in: app).isEnabled)
    XCTAssertFalse(require("sound.volume", in: app).isEnabled)
    capture("iPhone-English-Muted-Sound", in: app)

    journey.relaunch()
    tap("tab.settings", in: app)
    tap("settings.sound", in: app)
    XCTAssertEqual(switchValue("sound.mute", in: app), true)
    back(in: app)
    tap("settings.alerts", in: app)
    tap("alerts.fajr", in: app)
    XCTAssertEqual(switchValue("alert.fajr.before.enabled", in: app), true)
    XCTAssertEqual(switchValue("alert.fajr.after.enabled", in: app), true)
    XCTAssertEqual(value("alert.fajr.before.minutes", in: app), beforeMinutes)
    XCTAssertEqual(value("alert.fajr.after.minutes", in: app), afterMinutes)
    XCTAssertEqual(require("alert.fajr.before.sound", in: app).label, beforeSound)
    XCTAssertEqual(require("alert.fajr.after.sound", in: app).label, afterSound)
    back(in: app)
    tap("alerts.jumuah", in: app)
    XCTAssertEqual(switchValue("alert.fridayOverride", in: app), true)
    XCTAssertEqual(switchValue("alert.jumuah.before.enabled", in: app), true)
  }

  @MainActor
  func testDayWeekNavigationAndQiblaUseTheSelectedLocation() {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    tap("tab.times", in: app)
    let initialDate = value("times.date", in: app)
    tap("times.next", in: app)
    XCTAssertTrue(waitUntil { self.value("times.date", in: app) != initialDate })
    tap("times.previous", in: app)
    XCTAssertEqual(value("times.date", in: app), initialDate)
    capture("iPhone-English-Times-Day", in: app)
    tap("times.week", in: app)
    require("times.weekTable", in: app)
    capture("iPhone-English-Times-Week", in: app)
    tap("times.day.2026-06-04", in: app)
    require("times.dayList", in: app)
    XCTAssertNotEqual(value("times.date", in: app), initialDate)

    tap("tab.qibla", in: app)
    let heading = require("qibla.heading", in: app)
    XCTAssertFalse(heading.label.isEmpty)
    XCTAssertFalse(element("qibla.chooseCity", in: app).exists)
    capture("iPhone-English-Qibla", in: app)
  }

  @MainActor
  func testMissingLocationRecoverySelectsACityAndRestoresQibla() {
    let journey = IOSJourneyApp(fixture: false)
    journey.app.resetAuthorizationStatus(for: .location)
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    tap("tab.qibla", in: app)
    require("qibla.chooseCity", in: app)
    require("qibla.placeholder", in: app)
    XCTAssertFalse(element("qibla.heading", in: app).exists)
    let allowLocation = require("qibla.allowLocation", in: app)
    XCTAssertTrue(allowLocation.isHittable)
    XCTAssertEqual(
      allowLocation.frame.width, app.windows.firstMatch.frame.width - 32, accuracy: 1,
      "The primary location action fills the content width with 16-point side insets")
    XCTAssertGreaterThanOrEqual(allowLocation.frame.height, 44)
    capture("iPhone-English-Qibla-First-Location-Permission", in: app)
    allowLocation.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
    let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
    XCTAssertTrue(
      permission.exists || permission.waitForExistence(timeout: 15),
      "Tapping the action near its trailing edge must request real location permission")
    captureSystem("System-Qibla-First-Location-Permission")
    let deny = permission.buttons.matching(
      NSPredicate(format: "label BEGINSWITH[c] %@ AND label CONTAINS[c] %@", "Don", "Allow")
    ).firstMatch
    XCTAssertTrue(deny.exists, permission.debugDescription)
    deny.tap()
    XCTAssertTrue(permission.waitForNonExistence(timeout: 10))
    require("qibla.openSettings", in: app)
    capture("iPhone-English-Qibla-Location-Recovery", in: app)
    tap("qibla.chooseCity", in: app)
    selectCity("Makkah, Saudi Arabia", matching: "Makkah", in: app)
    tap("tab.qibla", in: app)
    require("qibla.heading", in: app)
    XCTAssertFalse(element("qibla.chooseCity", in: app).exists)
    journey.relaunch()
    tap("tab.qibla", in: app)
    require("qibla.heading", in: app)
  }

  @MainActor
  func testExplicitPrayerPlaybackStartsAndStopsInToday() {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    require("today.nextPrayer", in: app)
    XCTAssertFalse(element("today.stopAudio", in: app).exists)
    let fajr = require("prayer.row.fajr", in: app)
    reveal(fajr, in: app)
    fajr.press(forDuration: 1)
    let play = app.buttons["Play prayer sound"].firstMatch
    XCTAssertTrue(play.waitForExistence(timeout: 5))
    play.tap()
    let stop = element("today.stopAudio", in: app)
    if !stop.isHittable { app.swipeDown() }
    require("today.stopAudio", in: app)
    let oldPrayer = require("prayer.row.fajr", in: app)
    XCTAssertFalse(
      oldPrayer.label.components(separatedBy: CharacterSet.letters.inverted).contains("Now"),
      "Playing an earlier prayer must not claim that its prayer time has just started")
    XCTAssertFalse(
      oldPrayer.descendants(matching: .staticText).matching(
        NSPredicate(format: "label == %@", "Now")
      ).firstMatch.exists)
    capture("iPhone-English-Today-Explicit-Playback", in: app)
    tap("today.stopAudio", in: app)
    XCTAssertTrue(waitUntil { !stop.exists })
    require("today.countdown", in: app)
  }

  @MainActor
  func testArabicDarkModeAndLargeTextRemainNavigable() throws {
    let journey = IOSJourneyApp(extraArguments: [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ])
    journey.launch()
    let app = journey.app
    defer { app.terminate() }

    tap("tab.settings", in: app)
    tap("settings.appearance", in: app)
    tap("appearance.dark", in: app)
    back(in: app)
    tap("settings.language", in: app)
    tap("language.arabic", in: app)
    back(in: app)
    tap("tab.today", in: app)

    let today = require("tab.today", in: app)
    let settings = require("tab.settings", in: app)
    XCTAssertTrue(today.isHittable)
    XCTAssertTrue(settings.isHittable)
    XCTAssertGreaterThan(today.frame.midX, settings.frame.midX, "Arabic reverses tab order")
    let nextPrayer = require("today.name", in: app)
    XCTAssertTrue(
      nextPrayer.label.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) },
      "The prayer summary is localized into Arabic")
    capture("iPhone-Arabic-Dark-Accessibility-Today", in: app)
    try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription])

    tap("tab.settings", in: app)
    tap("settings.sound", in: app)
    XCTAssertTrue(require("sound.mute", in: app).isHittable)
    capture("iPhone-Arabic-Dark-Accessibility-Sound", in: app)
  }
}
