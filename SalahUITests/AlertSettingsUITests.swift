import AppKit
import SalahCore
import XCTest

/// A prayer's alert turned on or off in the running app's Settings replans it: the
/// adhan plays at the prayer's time, or doesn't.
///
/// Each test moves a prayer about two minutes ahead with Salah's own adjustments
/// (`PlacedPrayer`), launches the app with the launch arguments the real-app tests use
/// (`Launch`: Makkah, muted, English, no consent prompt), changes the prayer's alert in
/// Settings → Notifications, and waits past its minute. The runner is sandboxed in Salah's
/// App Group, so it reads what the app publishes there the way the widget does: the
/// settings mirror (`SalahSettings.v1`) and what's playing (`SalahPlayback.v1`).
///
/// The launch keeps the app's preferences in a scratch suite
/// (`-salah.debug.scratchPreferences`), so the moved prayer and the changed alert never
/// reach this Mac's own Salah preferences (CONTRIBUTING.md).
final class AlertSettingsUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// The alert, off at launch with the Alafasy adhan as its sound, is turned on in
  /// Settings; the app plays it at the prayer's minute.
  ///
  /// This is also the positive control for the App Group reader that
  /// ``testAnAlertTurnedOffInSettingsStaysSilent()`` relies on to see nothing playing.
  @MainActor
  func testAnAlertTurnedOnInSettingsPlaysAtItsTime() throws {
    let placed = try PlacedPrayer.soon(lead: 120)
    let app = try launchIntoSettings(alerts: [placed.kind: Launch.adhanOff], placed: placed)
    let toggle = alertToggle(of: placed.kind, in: app)
    XCTAssertEqual(Self.isOn(toggle), false, toggle.debugDescription)
    XCTAssertTrue(
      Self.wait(timeout: 10) { AppGroup.alertIsOn(for: placed.kind) == false },
      "The mirror shows the alert off before the change")

    toggle.click()
    XCTAssertTrue(Self.wait(timeout: 5) { Self.isOn(toggle) == true }, toggle.debugDescription)
    XCTAssertTrue(
      Self.wait(timeout: 10) { AppGroup.alertIsOn(for: placed.kind) == true },
      "The app saved the change and published it to its mirror")
    XCTAssertLessThan(Date(), placed.time, "The alert was turned on before its minute")
    XCTAssertNil(AppGroup.playback, "Nothing plays before the prayer's minute")

    let playing = Self.wait(until: placed.time.addingTimeInterval(20)) {
      AppGroup.playback.flatMap { $0.matches(placed) ? $0 : nil }
    }
    let playback = try XCTUnwrap(
      playing,
      "No adhan for \(placed.kind) at \(placed.time): \(String(describing: AppGroup.playback))")
    XCTAssertEqual(playback.slot, "alert")
    XCTAssertFalse(playback.isDua)
    XCTAssertGreaterThanOrEqual(Date(), placed.time.addingTimeInterval(-1))
  }

  /// The alert, on at launch with the Alafasy adhan, is turned off in Settings; nothing
  /// plays through the prayer's minute.
  ///
  /// So that it can't pass by seeing nothing at all, the test first sees the app publish
  /// the alert on, then off, through the same App Group reader, and the app is still
  /// running at the end. ``testAnAlertTurnedOnInSettingsPlaysAtItsTime()`` shows the reader
  /// sees playback when there is some; the real-app tests (`SalahRoundTripTests`) show
  /// that this launch, left alone, plays the adhan.
  @MainActor
  func testAnAlertTurnedOffInSettingsStaysSilent() throws {
    let placed = try PlacedPrayer.soon(lead: 120)
    let app = try launchIntoSettings(alerts: [placed.kind: Launch.adhan], placed: placed)
    let toggle = alertToggle(of: placed.kind, in: app)
    XCTAssertEqual(Self.isOn(toggle), true, toggle.debugDescription)
    XCTAssertTrue(
      Self.wait(timeout: 10) { AppGroup.alertIsOn(for: placed.kind) == true },
      "The mirror shows the alert on before the change")

    toggle.click()
    XCTAssertTrue(Self.wait(timeout: 5) { Self.isOn(toggle) == false }, toggle.debugDescription)
    XCTAssertTrue(
      Self.wait(timeout: 10) { AppGroup.alertIsOn(for: placed.kind) == false },
      "The app saved the change and published it to its mirror")
    XCTAssertLessThan(
      Date(), placed.time.addingTimeInterval(-10), "The alert was turned off before its minute")

    let played = Self.wait(until: placed.time.addingTimeInterval(20)) { AppGroup.playback }
    XCTAssertNil(played, "Something played after the alert was turned off")
    XCTAssertGreaterThanOrEqual(Date(), placed.time.addingTimeInterval(20))
    XCTAssertTrue(
      [.runningForeground, .runningBackground].contains(app.state), "The app is still running")
  }

  // MARK: - Driving the app

  /// Launches the app as `Launch` sets it up, straight into Settings, and quits it at the
  /// end of the test.
  ///
  /// The link is the launch: for a running app, `XCUIApplication.open(_:)` starts a second
  /// Salah, whose settings would be the ones changed while the first one still alerts, and
  /// a sandboxed runner can't hand the link to the running app through LaunchServices.
  @MainActor
  private func launchIntoSettings(alerts: [PrayerKind: [String: Any]], placed: PlacedPrayer)
    throws -> XCUIApplication
  {
    let app = XCUIApplication()
    app.launchArguments = Launch.arguments(alerts: alerts, placed: placed)
    app.open(try XCTUnwrap(URL(string: "salah://settings")))
    addTeardownBlock { @MainActor in app.terminate() }
    XCTAssertTrue(app.statusItems.firstMatch.waitForExistence(timeout: 30))
    XCTAssertTrue(
      app.windows["Salah Settings"].waitForExistence(timeout: 30), app.windows.debugDescription)
    XCTAssertEqual(
      NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.salah-kit.Salah")
        .count, 1, "Only the launched app runs, so only its settings can alert")
    return app
  }

  /// Opens the Notifications pane of the Settings window on `kind`, and returns its alert's
  /// toggle.
  @MainActor
  private func alertToggle(of kind: PrayerKind, in app: XCUIApplication) -> XCUIElement {
    let settings = app.windows["Salah Settings"]
    settings.buttons["Notifications"].click()

    let name = PrayerNames(locale: Locale(identifier: "en")).name(of: kind)
    let segment = settings.radioGroups["Prayer"].radioButtons[name]
    XCTAssertTrue(segment.waitForExistence(timeout: 10), settings.debugDescription)
    segment.click()
    XCTAssertTrue(Self.wait(timeout: 5) { Self.isOn(segment) == true }, segment.debugDescription)

    // The form's switch has no label of its own: the row's text is its sibling.
    let label = NSPredicate(
      format: "elementType == %lu AND value == %@", XCUIElement.ElementType.staticText.rawValue,
      "Play at prayer time")
    let toggle = settings.groups.containing(label).children(matching: .switch).firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 10), settings.debugDescription)
    return toggle
  }

  /// A switch's or a segment's state, which XCUITest reports as 0 or 1.
  @MainActor
  private static func isOn(_ toggle: XCUIElement) -> Bool? {
    switch toggle.value {
    case let number as NSNumber: number.boolValue
    case let text as String: text == "1"
    default: nil
    }
  }

  /// Polls `condition` until it holds; whether it did within `timeout` seconds.
  @MainActor
  private static func wait(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    wait(until: Date().addingTimeInterval(timeout)) { condition() ? true : nil } ?? false
  }

  /// Polls `value` until it isn't `nil`, and returns it; `nil` if it stayed `nil` until
  /// `deadline`.
  @MainActor
  private static func wait<Value>(until deadline: Date, _ value: () -> Value?) -> Value? {
    repeat {
      if let found = value() { return found }
      Thread.sleep(forTimeInterval: 0.5)
    } while Date() < deadline
    return value()
  }
}

/// What Salah publishes in its App Group, read as the widget extension reads it: the
/// group's own storage, the JSON `SharedValue` saves. Only the fields the tests need.
nonisolated enum AppGroup {
  static let identifier = "group.io.github.salah-kit.Salah"

  /// What's playing (`SalahPlayback` in Shared/SalahPlayback.swift).
  struct Playback: Decodable, Sendable {
    var event: PrayerEvent
    var slot: String
    var isDua: Bool

    /// Whether it's the placed prayer's sound, the prayer that starts at `placed.time`.
    func matches(_ placed: PlacedPrayer) -> Bool {
      event.kind == placed.kind && abs(event.time.timeIntervalSince(placed.time)) < 60
    }
  }

  /// The settings mirror's alerts (`SalahSettings` in Shared/SalahSettings.swift).
  struct Settings: Decodable, Sendable {
    struct Alerts: Decodable, Sendable {
      var alert: Bool
    }
    var alerts: [PrayerKind: Alerts]
  }

  static var playback: Playback? { load("SalahPlayback.v1") }

  /// Whether the mirror shows `kind`'s at-time alert on; `nil` without a mirror.
  static func alertIsOn(for kind: PrayerKind) -> Bool? {
    let settings: Settings? = load("SalahSettings.v1")
    return settings.map { $0.alerts[kind]?.alert ?? false }
  }

  /// The value under `key`, from the group's own storage only, as `SharedValue.load()`
  /// reads it.
  private static func load<Value: Decodable>(_ key: String) -> Value? {
    let defaults = UserDefaults(suiteName: identifier)
    guard let data = defaults?.persistentDomain(forName: identifier)?[key] as? Data else {
      return nil
    }
    return try? JSONDecoder().decode(Value.self, from: data)
  }
}
