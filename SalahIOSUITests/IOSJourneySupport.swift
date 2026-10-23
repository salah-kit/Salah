import XCTest

/// Launches the real app with an isolated, durable preferences suite. Only the first
/// launch resets it: relaunch assertions therefore exercise production persistence.
@MainActor
struct IOSJourneyApp {
  let app = XCUIApplication()
  let suite = "journey-" + UUID().uuidString
  let fixture: Bool
  let skipOnboarding: Bool
  var extraArguments: [String] = []

  init(fixture: Bool = true, skipOnboarding: Bool = true, extraArguments: [String] = []) {
    self.fixture = fixture
    self.skipOnboarding = skipOnboarding
    self.extraArguments = extraArguments
  }

  func launch(reset: Bool = true) {
    app.launchArguments =
      [
        "-salah.ios.testSuite", suite,
        "-salah.ios.fixture", fixture ? "true" : "false",
        "-salah.ios.skipOnboarding", skipOnboarding ? "true" : "false",
        "-salah.ios.reset", reset ? "true" : "false",
        "-salah.ios.now", "2026-06-02T13:19:00+03:00",
        "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
      ] + extraArguments
    app.launch()
  }

  func relaunch() {
    app.terminate()
    launch(reset: false)
  }
}

extension XCTestCase {
  @MainActor
  func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    // SwiftUI's native TabView does not carry the label's custom identifier to
    // UIKit's tab button. Query that real system control by its localized label.
    let tabLabels: [String: [String]] = [
      "tab.today": ["Today", "اليوم"],
      "tab.times": ["Times", "المواقيت", "الأوقات"],
      "tab.qibla": ["Qibla", "القبلة"],
      "tab.settings": ["Settings", "الإعدادات"],
    ]
    if let labels = tabLabels[identifier] {
      let predicate = NSPredicate(format: "label IN %@", labels)
      let tab = app.tabBars.buttons.matching(predicate).firstMatch
      if tab.exists { return tab }
      // The regular-width native TabView can present the same destinations in
      // its sidebar instead of a tab bar.
      return app.buttons.matching(predicate).firstMatch
    }
    return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @MainActor
  @discardableResult
  func require(
    _ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 10,
    file: StaticString = #filePath, line: UInt = #line
  ) -> XCUIElement {
    let target = element(identifier, in: app)
    XCTAssertTrue(
      target.exists || target.waitForExistence(timeout: timeout),
      "Missing \(identifier).\n\(app.debugDescription)",
      file: file, line: line)
    return target
  }

  @MainActor
  func tap(
    _ identifier: String, in app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let target = element(identifier, in: app)
    if !target.exists && !target.waitForExistence(timeout: 2) { reveal(target, in: app) }
    require(identifier, in: app, file: file, line: line)
    reveal(target, in: app)
    XCTAssertTrue(target.isHittable, "\(identifier) is not reachable", file: file, line: line)
    target.tap()
  }

  @MainActor
  func reveal(_ target: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<5 where !target.isHittable {
      app.swipeUp()
    }
  }

  @MainActor
  func back(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let button = app.navigationBars.buttons.firstMatch
    XCTAssertTrue(
      button.exists || button.waitForExistence(timeout: 5), "Missing Back", file: file, line: line)
    button.tap()
  }

  @MainActor
  func switchValue(_ identifier: String, in app: XCUIApplication) -> Bool? {
    let target = app.switches.matching(identifier: identifier).firstMatch
    XCTAssertTrue(target.exists || target.waitForExistence(timeout: 10), "Missing \(identifier)")
    if let number = target.value as? NSNumber { return number.boolValue }
    switch target.value as? String {
    case "1": return true
    case "0": return false
    default: return nil
    }
  }

  @MainActor
  func setSwitch(
    _ identifier: String, to desired: Bool, in app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let target = app.switches.matching(identifier: identifier).firstMatch
    if !target.exists && !target.waitForExistence(timeout: 2) { reveal(target, in: app) }
    XCTAssertTrue(
      target.exists || target.waitForExistence(timeout: 10), "Missing \(identifier)",
      file: file, line: line)
    reveal(target, in: app)
    XCTAssertNotNil(
      switchValue(identifier, in: app), "Missing switch value", file: file, line: line)
    if switchValue(identifier, in: app) != desired {
      // In a native Form, iOS exposes a full-row switch containing the actual
      // UISwitch thumb. Its row midpoint is outside that control's hit region.
      let thumb = target.switches.firstMatch
      (thumb.exists ? thumb : target).tap()
    }
    XCTAssertTrue(
      waitUntil { self.switchValue(identifier, in: app) == desired },
      "\(identifier) did not change", file: file, line: line)
  }

  @MainActor
  func increment(_ identifier: String, in app: XCUIApplication) {
    let stepper = element(identifier, in: app)
    if !stepper.exists && !stepper.waitForExistence(timeout: 2) { reveal(stepper, in: app) }
    require(identifier, in: app)
    reveal(stepper, in: app)
    let identifiedIncrease = stepper.buttons[identifier + "-Increment"].firstMatch
    let increase =
      identifiedIncrease.exists ? identifiedIncrease : stepper.buttons["Increment"].firstMatch
    XCTAssertTrue(
      increase.exists || increase.waitForExistence(timeout: 5),
      "No increment control in \(identifier).\n\(stepper.debugDescription)")
    let previous = value(identifier, in: app)
    increase.tap()
    XCTAssertTrue(
      waitUntil { self.value(identifier, in: app) != previous },
      "\(identifier) must change when its native Increment control is tapped")
  }

  @MainActor
  func value(_ identifier: String, in app: XCUIApplication) -> String {
    let target = require(identifier, in: app)
    if let value = target.value as? String, !value.isEmpty { return value }
    return target.label
  }

  @MainActor
  func selectCity(_ query: String, matching cityName: String, in app: XCUIApplication) {
    searchCity(query, matching: cityName, in: app).tap()
  }

  @MainActor
  @discardableResult
  func searchCity(_ query: String, matching cityName: String, in app: XCUIApplication)
    -> XCUIElement
  {
    let search = require("location.searchField", in: app)
    reveal(search, in: app)
    search.tap()
    search.typeText(query)
    return requireCityResult(cityName, in: app)
  }

  @MainActor
  @discardableResult
  func requireCityResult(_ cityName: String, in app: XCUIApplication) -> XCUIElement {
    let labels = cityNames(cityName).map { NSPredicate(format: "label CONTAINS[c] %@", $0) }
    let result = app.buttons.matching(
      NSCompoundPredicate(andPredicateWithSubpredicates: [
        NSPredicate(format: "identifier BEGINSWITH %@", "location.result."),
        NSCompoundPredicate(orPredicateWithSubpredicates: labels),
      ])
    ).firstMatch
    XCTAssertTrue(
      result.exists || result.waitForExistence(timeout: 45),
      "The real city search did not return \(cityName).\n\(app.debugDescription)")
    return result
  }

  /// Apple Maps returns the city's English exonym, Mecca, for a Makkah query.
  /// Both names identify the same result; arbitrary first results remain rejected.
  @MainActor
  func cityMatches(_ cityName: String, label: String) -> Bool {
    cityNames(cityName).contains { label.localizedCaseInsensitiveContains($0) }
  }

  @MainActor
  private func cityNames(_ cityName: String) -> [String] {
    cityName == "Makkah" ? ["Makkah", "Mecca"] : [cityName]
  }

  @MainActor
  func waitUntil(timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if condition() { return true }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return condition()
  }

  @MainActor
  func capture(_ name: String, in app: XCUIApplication) {
    XCTContext.runActivity(named: name) { activity in
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = name
      attachment.lifetime = .keepAlways
      activity.add(attachment)
    }
  }

  @MainActor
  func captureSystem(_ name: String) {
    XCTContext.runActivity(named: name) { activity in
      let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      attachment.name = name
      attachment.lifetime = .keepAlways
      activity.add(attachment)
    }
  }
}
