import XCTest

/// Launches the real watch app with an isolated, durable preferences suite. A fixture stands
/// for preferences the iPhone sent; only the first launch resets the suite and seeds it, so a
/// relaunch reads what the watch kept.
@MainActor
struct WatchJourneyApp {
  let app = XCUIApplication()
  let suite = "journey-" + UUID().uuidString
  var fixture: String? = "london"
  /// Monday 12 October 2026 in London: Asr at 3:37 PM, Maghrib at 6:14 PM.
  var now: String? = "2026-10-12T12:19:00Z"
  var frozen = true
  var language = "en"
  var tab: String?
  var heading: String?
  var extraArguments: [String] = []

  func launch(reset: Bool = true) {
    var arguments = [
      "-salah.watch.testSuite", suite, "-salah.watch.reset", reset ? "true" : "false",
      "-salah.watch.frozen", frozen ? "true" : "false", "-salah.watch.language", language,
      "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ar" ? "ar_SA" : "en_GB",
    ]
    if let fixture { arguments += ["-salah.watch.fixture", fixture] }
    if let now { arguments += ["-salah.watch.now", now] }
    if let tab { arguments += ["-salah.watch.tab", tab] }
    if let heading { arguments += ["-salah.watch.heading", heading] }
    app.launchArguments = arguments + extraArguments
    app.launch()
  }

  /// Launches again on the same suite, without the fixture, which would otherwise seed an
  /// empty suite again.
  func relaunch() {
    app.terminate()
    var again = self
    again.fixture = nil
    again.launch(reset: false)
  }
}

extension XCTestCase {
  @MainActor
  func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  @MainActor
  @discardableResult
  func require(
    _ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 15,
    file: StaticString = #filePath, line: UInt = #line
  ) -> XCUIElement {
    let target = element(identifier, in: app)
    // Waiting polls once a second, so look first.
    XCTAssertTrue(
      target.exists || target.waitForExistence(timeout: timeout),
      "Missing \(identifier).\n\(app.debugDescription)", file: file, line: line)
    return target
  }

  /// Waits until the element exists and its label, as people read it, contains `text`, as a
  /// live screen updates it.
  @MainActor
  func waitForLabel(
    _ identifier: String, containing text: String, in app: XCUIApplication,
    timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line
  ) {
    let target = require(identifier, in: app, timeout: timeout, file: file, line: line)
    let deadline = Date().addingTimeInterval(timeout)
    var label = plain(target.label)
    while !label.contains(text), Date() < deadline {
      Thread.sleep(forTimeInterval: 0.5)
      label = target.exists ? plain(target.label) : ""
    }
    XCTAssertTrue(
      label.contains(text), "\(identifier) never said “\(text)”: “\(label)”", file: file,
      line: line)
  }

  /// Keeps a screenshot of the watch with the result bundle.
  @MainActor
  func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

/// Text as people read it: without the bidi isolates around times, and with ordinary spaces
/// for the narrow ones between a time and its day period.
func plain(_ text: String) -> String {
  text.replacingOccurrences(of: "\u{2068}", with: "")
    .replacingOccurrences(of: "\u{2069}", with: "")
    .replacingOccurrences(of: "\u{202F}", with: " ")
    .replacingOccurrences(of: "\u{00A0}", with: " ")
}
