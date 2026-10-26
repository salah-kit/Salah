import XCTest

/// Launches the real app with an isolated, durable preferences suite. Only the first launch
/// resets it, so relaunch assertions exercise the app's own persistence.
@MainActor
struct TVJourneyApp {
  let app = XCUIApplication()
  let suite = "journey-" + UUID().uuidString
  var fixture: String? = "makkah"
  var skipOnboarding = true
  var now: String? = "2026-06-02T13:19:00+03:00"
  var frozen = true
  var language = "en"
  var route: String?
  var extraArguments: [String] = []

  func launch(reset: Bool = true) {
    var arguments = [
      "-salah.tv.testSuite", suite, "-salah.tv.reset", reset ? "true" : "false",
      "-salah.tv.skipOnboarding", skipOnboarding ? "true" : "false",
      "-salah.tv.frozen", frozen ? "true" : "false", "-salah.tv.language", language,
      "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ar" ? "ar_SA" : "en_US",
    ]
    if let fixture { arguments += ["-salah.tv.fixture", fixture] }
    if let now { arguments += ["-salah.tv.now", now] }
    if let route { arguments += ["-salah.tv.route", route] }
    app.launchArguments = arguments + extraArguments
    app.launch()
  }

  func relaunch() {
    app.terminate()
    launch(reset: false)
  }
}

extension XCTestCase {
  var remote: XCUIRemote { XCUIRemote.shared }

  @MainActor
  func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @MainActor
  @discardableResult
  func require(
    _ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 10,
    file: StaticString = #filePath, line: UInt = #line
  ) -> XCUIElement {
    let target = element(identifier, in: app)
    // Waiting polls once a second, so look first.
    XCTAssertTrue(
      target.exists || target.waitForExistence(timeout: timeout),
      "Missing \(identifier).\n\(app.debugDescription)", file: file, line: line)
    return target
  }

  /// The element that has focus now.
  @MainActor
  func focused(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
  }

  /// Whether `target` has focus. A List row's focus belongs to its cell, so a row inside the
  /// focused cell counts.
  @MainActor
  func hasFocus(_ target: XCUIElement, in app: XCUIApplication) -> Bool {
    guard target.exists else { return false }
    if target.hasFocus { return true }
    let cell = focused(in: app)
    guard cell.exists, cell.elementType == .cell else { return false }
    let inside =
      target.identifier.isEmpty
      ? cell.descendants(matching: target.elementType)
        .matching(NSPredicate(format: "label == %@", target.label))
      : cell.descendants(matching: .any).matching(identifier: target.identifier)
    return inside.firstMatch.exists
  }

  /// Presses `direction` until `target` has focus, as a person would with the remote.
  @MainActor
  func moveFocus(
    _ direction: XCUIRemote.Button, to target: XCUIElement, in app: XCUIApplication,
    maximumPresses: Int = 12, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(
      target.exists || target.waitForExistence(timeout: 10),
      "Missing \(target).\n\(app.debugDescription)", file: file, line: line)
    for _ in 0..<maximumPresses where !hasFocus(target, in: app) {
      remote.press(direction)
      _ = waitUntil(timeout: 1) { self.hasFocus(target, in: app) }
    }
    let focused = focused(in: app)
    XCTAssertTrue(
      hasFocus(target, in: app),
      "Focus didn't reach \(target); it's on "
        + (focused.exists ? String(focused.debugDescription.prefix(400)) : "nothing"),
      file: file, line: line)
  }

  /// Presses `direction` until `condition` holds, for a target a list or a scroll view only
  /// shows once focus comes near it. Returns whether it held.
  @MainActor
  @discardableResult
  func press(
    _ direction: XCUIRemote.Button, until condition: @MainActor () -> Bool,
    maximumPresses: Int = 24
  ) -> Bool {
    for _ in 0..<maximumPresses where !condition() {
      remote.press(direction)
      _ = waitUntil(timeout: 1, condition)
    }
    return condition()
  }

  /// Waits out a full-screen presentation; tvOS drops remote presses while it animates.
  @MainActor
  func settle() {
    _ = waitUntil(timeout: 1) { false }
  }

  /// Moves up to the tab bar, then along it to `title`, which selects that tab.
  @MainActor
  func openTab(
    _ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) {
    let tabs = app.tabBars.buttons
    let current = tabs.matching(NSPredicate(format: "hasFocus == true")).firstMatch
    for _ in 0..<12 where !current.exists {
      remote.press(.up)
      _ = waitUntil(timeout: 1) { current.exists }
    }
    XCTAssertTrue(current.exists, "Focus didn't reach the tab bar", file: file, line: line)
    let tab = tabs.matching(NSPredicate(format: "label == %@", title)).firstMatch
    let direction: XCUIRemote.Button = tab.frame.minX < current.frame.minX ? .left : .right
    moveFocus(direction, to: tab, in: app, maximumPresses: 4, file: file, line: line)
  }

  /// Types a city into the search on screen, then moves down to a match and chooses it, as a
  /// person would with the remote. The search uses Apple Maps, so it needs the network.
  @MainActor
  func chooseCity(
    _ query: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
  ) {
    let field = app.searchFields.firstMatch
    XCTAssertTrue(
      field.exists || field.waitForExistence(timeout: 10),
      "No search field.\n\(app.debugDescription)",
      file: file, line: line)
    field.typeText(query)
    let names = cityNames(query).map { NSPredicate(format: "label CONTAINS[c] %@", $0) }
    let result = app.buttons.matching(
      NSCompoundPredicate(andPredicateWithSubpredicates: [
        NSPredicate(format: "identifier BEGINSWITH %@", "location.result."),
        NSCompoundPredicate(orPredicateWithSubpredicates: names),
      ])
    ).firstMatch
    XCTAssertTrue(
      result.waitForExistence(timeout: 30), "No city matched \(query).\n\(app.debugDescription)",
      file: file, line: line)
    moveFocus(.down, to: result, in: app, maximumPresses: 10, file: file, line: line)
    remote.press(.select)
  }

  /// Apple Maps names Makkah in English either way.
  func cityMatches(_ city: String, label: String) -> Bool {
    cityNames(city).contains { label.localizedCaseInsensitiveContains($0) }
  }

  private func cityNames(_ city: String) -> [String] {
    city == "Makkah" ? ["Makkah", "Mecca"] : [city]
  }

  @MainActor
  func capture(_ name: String, in app: XCUIApplication) {
    attach(app.screenshot(), named: name)
  }

  /// The whole screen, for what the system shows over Salah.
  @MainActor
  func captureScreen(_ name: String) {
    attach(XCUIScreen.main.screenshot(), named: name)
  }

  @MainActor
  private func attach(_ screenshot: XCUIScreenshot, named name: String) {
    XCTContext.runActivity(named: name) { activity in
      let attachment = XCTAttachment(screenshot: screenshot)
      attachment.name = name
      attachment.lifetime = .keepAlways
      activity.add(attachment)
    }
  }
}

/// Polls `condition` while the run loop turns, until it holds or `timeout` passes.
@MainActor
func waitUntil(timeout: TimeInterval = 10, _ condition: @MainActor () -> Bool) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  repeat {
    if condition() { return true }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  } while Date() < deadline
  return condition()
}

/// The location alert tvOS shows over Salah. PineBoard presents it, and the remote answers
/// it: focus starts on its message, above the three buttons.
@MainActor
enum TVLocationAlert {
  static let allowOnce = NSPredicate(format: "label == %@", "Allow Once")
  static let dontAllow = NSPredicate(
    format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Don", "Allow")

  static var alert: XCUIElement {
    XCUIApplication(bundleIdentifier: "com.apple.PineBoard").alerts.firstMatch
  }

  /// Moves focus to the button `answer` matches, as a person would, and chooses it. Returns
  /// whether the alert closed.
  @discardableResult
  static func choose(_ answer: NSPredicate) -> Bool {
    let alert = alert
    let choice = alert.buttons.matching(answer).firstMatch
    guard alert.exists, choice.exists else { return false }
    let focus = NSPredicate(format: "hasFocus == true")
    let chosen = alert.buttons.matching(
      NSCompoundPredicate(andPredicateWithSubpredicates: [answer, focus])
    ).firstMatch
    let current = alert.descendants(matching: .any).matching(focus).firstMatch
    for _ in 0..<6 where !chosen.exists {
      let above = current.exists && current.frame.midY > choice.frame.midY
      XCUIRemote.shared.press(above ? .up : .down)
      _ = waitUntil(timeout: 1) { chosen.exists }
    }
    guard chosen.exists else { return false }
    XCUIRemote.shared.press(.select)
    return waitUntil { !alert.exists }
  }

  /// Answers an alert a failed journey left open; it would keep focus from later journeys.
  static func dismissLeftover() {
    if alert.exists { choose(dontAllow) }
  }
}
