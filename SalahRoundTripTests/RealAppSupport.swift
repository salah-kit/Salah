import Darwin
import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

/// Where the scheme's build put the app and the harness: beside this test bundle.
enum Products {
  static var directory: URL {
    Bundle(for: LogRecorder.self).bundleURL.deletingLastPathComponent()
  }
  static var app: URL { directory.appending(path: "Salah.app/Contents/MacOS/Salah") }
  static var harness: URL {
    directory.appending(path: "SalahStopHarness.app/Contents/MacOS/SalahStopHarness")
  }
}

/// One line of the app's log: `log stream`'s JSON for a message of Salah's subsystem.
nonisolated struct LogLine: Sendable, CustomStringConvertible {
  var date: Date
  var category: String
  var message: String
  var description: String { "[\(category)] \(message)" }
}

/// Records the app's log from `log stream`, which shows the messages of Salah's subsystem
/// that the app logs at notice level or above.
nonisolated final class LogRecorder: @unchecked Sendable {
  // Lock-protected: the pipe's handler appends on its own queue, the test reads.
  private let lock = NSLock()
  private var lines: [LogLine] = []
  private var buffer = Data()
  private let process = Process()
  private let pipe = Pipe()

  /// Starts recording, and waits a moment for `log stream` to attach, so the app's first
  /// lines aren't missed.
  static func start() async throws -> LogRecorder {
    let recorder = try LogRecorder()
    try await Task.sleep(for: .seconds(2))
    return recorder
  }

  private init() throws {
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = [
      "stream", "--style", "ndjson", "--level", "info", "--predicate",
      #"subsystem == "io.github.salah-kit.Salah""#,
    ]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.append(handle.availableData)
    }
    try process.run()
  }

  deinit { stop() }

  func stop() {
    pipe.fileHandleForReading.readabilityHandler = nil
    if process.isRunning { process.terminate() }
  }

  private func append(_ data: Data) {
    lock.withLock {
      buffer.append(data)
      while let newline = buffer.firstIndex(of: 0x0A) {
        let line = buffer[buffer.startIndex..<newline]
        buffer.removeSubrange(buffer.startIndex...newline)
        guard
          let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
          let message = object["eventMessage"] as? String
        else { continue }
        lines.append(
          LogLine(
            date: Date(), category: object["category"] as? String ?? "", message: message))
      }
    }
  }

  var all: [LogLine] { lock.withLock { lines } }

  /// The lines whose message contains `fragment`.
  func lines(containing fragment: String) -> [LogLine] {
    all.filter { $0.message.contains(fragment) }
  }

  /// Waits until a line contains `fragment`, and returns it; `nil` after the timeout.
  func wait(for fragment: String, after start: Int = 0, timeout: TimeInterval) async -> LogLine? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if let line = all.dropFirst(start).first(where: { $0.message.contains(fragment) }) {
        return line
      }
      try? await Task.sleep(for: .milliseconds(200))
    }
    return nil
  }
}

/// The real, signed Salah running as a separate process, launched by its executable.
///
/// Its environment is a plain user session's: XCTest's variables would make the launched
/// app behave as a test host.
final class RunningApp {
  let process = Process()

  init(arguments: [String]) throws {
    process.executableURL = Products.app
    process.arguments = arguments
    let inherited = ProcessInfo.processInfo.environment
    process.environment = inherited.filter {
      ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "SHELL"].contains($0.key)
    }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
  }

  var isRunning: Bool { process.isRunning }

  /// Freezes the app, as the Mac's sleep does: no timer fires while time passes.
  func suspend() { kill(process.processIdentifier, SIGSTOP) }

  /// Lets the app run again, late for everything that came due meanwhile.
  func resume() { kill(process.processIdentifier, SIGCONT) }

  func quit() {
    resume()
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }
  }
}

/// The stop harness's report (`SalahStopHarness/main.swift`).
nonisolated struct HarnessReport: Decodable, Sendable {
  struct Widget: Decodable, Sendable {
    var firstEntry: String
    var showsStop: Bool
  }
  /// What's playing, as far as the report needs it.
  struct Playback: Decodable, Sendable {
    var slot: String
    var isDua: Bool
  }

  var command: String
  var signalAccepted: Bool?
  var hasSettings: Bool
  var playback: Playback?
  var widget: Widget?
}

enum Harness {
  /// Runs the harness once and decodes its report.
  static func run(_ command: String) throws -> HarnessReport {
    let process = Process()
    process.executableURL = Products.harness
    process.arguments = [command]
    process.environment = ProcessInfo.processInfo.environment.filter {
      ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "SHELL"].contains($0.key)
    }
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    return try JSONDecoder().decode(HarnessReport.self, from: data)
  }
}

/// A prayer moved to start at a whole minute a little ahead, through Salah's own minute
/// adjustments, so a test can wait for a real alert.
nonisolated struct PlacedPrayer: Sendable {
  /// The prayer moved.
  var kind: PrayerKind
  /// The adjustment, in minutes, that puts it at `time`.
  var adjustment: Int
  /// When it starts now.
  var time: Date

  /// The preference key of the kind's adjustment.
  var adjustmentKey: String {
    switch kind {
    case .fajr: "salah.adjustmentFajr"
    case .sunrise: "salah.adjustmentShuruq"
    case .dhuhr: "salah.adjustmentDhuhr"
    case .asr: "salah.adjustmentAsr"
    case .maghrib: "salah.adjustmentMaghrib"
    case .isha: "salah.adjustmentIsha"
    }
  }

  /// Makkah with Salah's default calculation, the app's launch location.
  static var schedule: PrayerSchedule {
    var parameters = CalculationMethod.ummAlQura.parameters
    parameters.highLatitudeRule = .middleOfTheNight
    parameters.ramadanIsha = .interval(minutes: 120, hijriDayOffset: 0)
    let zone = TimeZone(identifier: "Asia/Riyadh") ?? .gmt
    return PrayerSchedule(
      source: CalculationSource(CalculationSettings(parameters: parameters)),
      location: PrayerLocation(latitude: 21.4167, longitude: 39.8167, timeZone: zone))
  }

  /// A prayer starting at the first whole minute at least `lead` from now. Between the
  /// two events around that minute, it moves the earlier one later if it's a prayer,
  /// otherwise the later one earlier, so the day keeps its order.
  static func soon(lead: TimeInterval, now: Date = Date()) throws -> PlacedPrayer {
    let target = Date(
      timeIntervalSinceReferenceDate: (now.addingTimeInterval(lead).timeIntervalSinceReferenceDate
        / 60).rounded(.up) * 60)
    let events = schedule.events(
      from: target.addingTimeInterval(-2 * 86_400), through: target.addingTimeInterval(2 * 86_400)
    ).events
    let before = try #require(events.last { $0.time <= target })
    let after = try #require(events.first { $0.time > target })
    let moved = before.kind.isPrayer ? before : after
    let minutes = Int((target.timeIntervalSince(moved.time) / 60).rounded())
    return PlacedPrayer(kind: moved.kind, adjustment: minutes, time: target)
  }
}

/// Launch arguments: Makkah with Salah's default calculation and no adjustment but the
/// given one, no automatic location, no consent prompt of any kind, English, muted, and
/// every alert off but the given ones.
///
/// The app saves the preferences it launched with, so every launch sets each one the
/// tests depend on, rather than inherit an earlier test's.
enum Launch {
  static func arguments(alerts: [PrayerKind: [String: Any]] = [:], placed: PlacedPrayer? = nil)
    -> [String]
  {
    var adjustments: [String] = []
    for kind in PrayerKind.allCases {
      let key = PlacedPrayer(kind: kind, adjustment: 0, time: Date()).adjustmentKey
      let minutes = placed?.kind == kind ? placed?.adjustment ?? 0 : 0
      // In property-list form: a bare "-106" would read as the next key.
      adjustments += ["-\(key)", "<integer>\(minutes)</integer>"]
    }
    var settings: [String: [String: Any]] = [:]
    for kind in PrayerKind.allCases {
      settings[kind.rawValue] = alerts[kind] ?? ["alertEnabled": false]
    }
    let json =
      (try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]))
      ?? Data()
    let hex = "<" + json.map { String(format: "%02x", $0) }.joined() + ">"
    return [
      "-salah.autoLocation", "NO",
      "-salah.debug.withoutSystemPrompts", "YES",
      "-salah.notificationSettings", hex,
      "-salah.appLanguage", "english",
      "-AppleLanguages", "(en)",
      "-salah.alertVolume", "0",
      "-salah.duaEnabled", "NO",
      "-salah.silentMode", "NO",
      "-salah.latitude", "21.4167", "-salah.longitude", "39.8167",
      "-salah.timeZone", "Asia/Riyadh", "-salah.city", "Makkah", "-salah.country", "SA",
      "-salah.autoDetectMethod", "NO", "-salah.method", "4", "-salah.madhab", "0",
      "-salah.autoDetectHighLatitudeRule", "NO", "-salah.highLatitudeRule", "0",
      "-salah.delayedIshaInRamadan", "YES", "-salah.hijriOffset", "0",
      "-salah.jumuahOverrideEnabled", "NO",
    ] + adjustments
  }

  /// An at-time alert with an adhan the app plays, Alafasy's.
  static let adhan: [String: Any] = [
    "alertEnabled": true, "alertSound": ["kind": "builtIn", "builtIn": "Adhan-Alafasy"],
  ]
}
