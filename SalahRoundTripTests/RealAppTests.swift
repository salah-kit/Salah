import Darwin
import Foundation
import SalahCore
import Testing

/// The real app, its widget's Stop code, a simulated sleep and a settings change, run as
/// separate processes on this Mac.
///
/// These tests have no host app: they run in `xctest`, outside any sandbox, so they can
/// start the signed app and the stop harness, suspend the app, and read the app's log.
/// The harness stands in for the widget extension: it's sandboxed in the same App Group
/// and runs the Stop intent's own code. Each test moves a prayer a minute or two ahead
/// through Salah's own adjustments, so a real alert comes due; the app is muted and never
/// asks macOS for anything (`-salah.debug.withoutSystemPrompts`). Run them with the
/// `SalahRoundTripTests` scheme and a signing team (CONTRIBUTING.md); CI only builds them.
@Suite("Real app", .serialized)
struct RealAppTests {
  /// Launches the app with `alerts` for a prayer placed `lead` seconds ahead, and waits
  /// until it has planned.
  static func launch(
    log: LogRecorder, lead: TimeInterval, alert: (PlacedPrayer) -> [String: Any]
  ) async throws -> (RunningApp, PlacedPrayer) {
    let placed = try PlacedPrayer.soon(lead: lead)
    let app = try RunningApp(
      arguments: Launch.arguments(alerts: [placed.kind: alert(placed)], placed: placed))
    let planned = await log.wait(for: "planned alerts=", timeout: 30)
    #expect(planned != nil, "the app didn't plan: \(log.all)")
    return (app, placed)
  }

  /// Waits until `date`.
  static func sleep(until date: Date) async throws {
    let seconds = date.timeIntervalSinceNow
    if seconds > 0 { try await Task.sleep(for: .milliseconds(Int(seconds * 1_000))) }
  }

  // MARK: - The stop round trip (proposal §7.3, Live state)

  /// The widget's Stop code, run in a separate sandboxed process, stops the running app's
  /// adhan; the app confirms by publishing again, and the widget's timeline, built by the
  /// extension's code from what's stored, drops the Stop control.
  @Test func theWidgetsStopCodeStopsTheRunningApp() async throws {
    let log = try await LogRecorder.start()
    defer { log.stop() }
    let (app, placed) = try await Self.launch(log: log, lead: 70) { _ in Launch.adhan }
    defer { app.quit() }

    let started = await log.wait(
      for: "playback started source=prayerAlert slot=alert", timeout: 150)
    #expect(started != nil, "nothing played at \(placed.time): \(log.all)")
    try await Task.sleep(for: .seconds(2))
    let playing = try Harness.run("read")
    #expect(playing.playback?.slot == "alert")
    #expect(playing.widget?.showsStop == true)

    let mark = log.all.count
    let stop = try Harness.run("stop")
    #expect(stop.playback == nil, "the intent cleared what's playing")
    #expect(
      await log.wait(for: "stop signal received wasPlaying=true", after: mark, timeout: 10) != nil)
    #expect(await log.wait(for: "playback stopped", after: mark, timeout: 10) != nil)
    #expect(
      await log.wait(for: "published SalahPlayback.v1 value=none", after: mark, timeout: 10) != nil)
    let after = try Harness.run("read")
    #expect(after.playback == nil)
    #expect(after.widget?.firstEntry == "schedule")
    #expect(after.widget?.showsStop == false)
    #expect(app.isRunning)
  }

  /// The intent's cleared value can reach the app later than the signal does. Here the
  /// harness posts only the signal, so the stored value still says the adhan plays: the
  /// app stops anyway, and its republish clears the value.
  @Test func theAppActsOnTheSignalNotOnTheStoredValue() async throws {
    let log = try await LogRecorder.start()
    defer { log.stop() }
    let (app, placed) = try await Self.launch(log: log, lead: 70) { _ in Launch.adhan }
    defer { app.quit() }
    let started = await log.wait(
      for: "playback started source=prayerAlert slot=alert", timeout: 150)
    #expect(started != nil, "nothing played at \(placed.time): \(log.all)")
    try await Task.sleep(for: .seconds(2))
    #expect(try Harness.run("read").playback != nil)

    let mark = log.all.count
    let signal = try Harness.run("signal")
    #expect(signal.signalAccepted == true)
    #expect(
      await log.wait(for: "stop signal received wasPlaying=true", after: mark, timeout: 10) != nil)
    #expect(
      await log.wait(
        for: "published SalahPlayback.v1 value=none changed=true", after: mark, timeout: 10)
        != nil)
    let after = try Harness.run("read")
    #expect(after.playback == nil)
    #expect(after.widget?.showsStop == false)
  }

  // MARK: - Sleep and wake, simulated

  /// The app is frozen through a prayer's start, as during the Mac's sleep, and resumes two
  /// minutes late: the in-process engine catches the adhan up, once.
  @Test func anAlertMissedDuringASleepIsCaughtUpOnce() async throws {
    let log = try await LogRecorder.start()
    defer { log.stop() }
    let (app, placed) = try await Self.launch(log: log, lead: 75) { _ in Launch.adhan }
    defer { app.quit() }
    try await Self.sleep(until: placed.time.addingTimeInterval(-30))
    app.suspend()
    try await Self.sleep(until: placed.time.addingTimeInterval(120))
    let mark = log.all.count
    app.resume()

    let due = await log.wait(for: "due prayers/", after: mark, timeout: 15)
    #expect(due != nil, "nothing came due after the wake: \(log.all)")
    #expect(due?.message.contains("/\(placed.kind.rawValue)/atTime") == true)
    #expect(
      await log.wait(for: "playback started source=prayerAlert", after: mark, timeout: 10) != nil)

    // A second sleep and wake doesn't play it again.
    try await Task.sleep(for: .seconds(2))
    let second = log.all.count
    app.suspend()
    try await Task.sleep(for: .seconds(5))
    app.resume()
    try await Task.sleep(for: .seconds(8))
    #expect(
      log.lines(containing: "due prayers/").count
        == log.all.prefix(second).filter { $0.message.contains("due prayers/") }.count)
  }

  /// A reminder missed by more than its two-minute grace isn't played after the wake.
  @Test func aReminderMissedPastItsGraceIsDropped() async throws {
    let log = try await LogRecorder.start()
    defer { log.stop() }
    // The prayer five minutes after the placed minute, with a five-minute reminder: the
    // reminder falls on the placed minute.
    let (app, placed) = try await Self.launch(log: log, lead: 75 + 5 * 60) { _ in
      [
        "alertEnabled": false, "preReminderEnabled": true, "preReminderOffset": 5,
        "preReminderSound": ["kind": "builtIn", "builtIn": "Adhan-Alafasy"],
      ]
    }
    defer { app.quit() }
    let reminder = placed.time.addingTimeInterval(-5 * 60)
    try await Self.sleep(until: reminder.addingTimeInterval(-30))
    app.suspend()
    try await Self.sleep(until: reminder.addingTimeInterval(150))
    let mark = log.all.count
    app.resume()
    try await Task.sleep(for: .seconds(10))
    #expect(log.all.dropFirst(mark).filter { $0.message.contains("due prayers/") }.isEmpty)
    #expect(log.all.dropFirst(mark).filter { $0.message.contains("playback started") }.isEmpty)
  }

  // MARK: - Notification changes

  /// A changed alert setting replans: with the placed prayer's adhan turned off at the
  /// next launch, the minute passes without an alert, and the plan holds one alert fewer.
  @Test func aChangedAlertSettingReplans() async throws {
    let log = try await LogRecorder.start()
    defer { log.stop() }
    let placed = try PlacedPrayer.soon(lead: 90)
    let on = try RunningApp(
      arguments: Launch.arguments(alerts: [placed.kind: Launch.adhan], placed: placed))
    let first = await log.wait(for: "planned alerts=", timeout: 30)
    on.quit()

    let mark = log.all.count
    let off = try RunningApp(
      arguments: Launch.arguments(alerts: [placed.kind: ["alertEnabled": false]], placed: placed))
    defer { off.quit() }
    let second = await log.wait(for: "planned alerts=", after: mark, timeout: 30)
    #expect(first?.message.hasPrefix("planned alerts=0") == false, "\(String(describing: first))")
    #expect(second?.message.hasPrefix("planned alerts=0") == true, "\(String(describing: second))")
    try await Self.sleep(until: placed.time.addingTimeInterval(20))
    #expect(log.all.dropFirst(mark).filter { $0.message.contains("playback started") }.isEmpty)
  }
}
