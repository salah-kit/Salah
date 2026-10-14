import AppKit
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
  /// The process that logged it: the app under test, or another Salah running on this Mac.
  var processID: Int32
  var category: String
  var message: String
  var description: String { "[\(processID) \(category)] \(message)" }
}

/// Records the app's log from `log stream`, which shows the messages of Salah's subsystem
/// that the app logs at notice level or above. The tests read only the lines of the
/// process they launched, so a Salah already running on this Mac can't answer for it.
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
            date: Date(), processID: (object["processID"] as? NSNumber)?.int32Value ?? 0,
            category: object["category"] as? String ?? "", message: message))
      }
    }
  }

  var all: [LogLine] { lock.withLock { lines } }

  /// The lines of the process `processID`, from the `start`th line recorded on, whose
  /// message contains `fragment`.
  func lines(containing fragment: String, from processID: Int32, after start: Int = 0)
    -> [LogLine]
  {
    all.dropFirst(start).filter { $0.processID == processID && $0.message.contains(fragment) }
  }

  /// Waits until a line of the process `processID` contains `fragment`, and returns it;
  /// `nil` after the timeout.
  func wait(
    for fragment: String, from processID: Int32, after start: Int = 0, timeout: TimeInterval
  ) async -> LogLine? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if let line = lines(containing: fragment, from: processID, after: start).first {
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

  /// Quits every Salah already running, then launches this one.
  init(arguments: [String]) throws {
    Self.quitOthers()
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

  /// Quits every Salah already running, as the UI tests do, and waits until they're gone:
  /// the app under test is then the only one that alerts and publishes to the App Group.
  /// A signal, as `quit()` sends, needs no Apple Event and so no consent.
  static func quitOthers() {
    let running = NSRunningApplication.runningApplications(
      withBundleIdentifier: "io.github.salah-kit.Salah"
    ).map(\.processIdentifier)
    // A Salah an earlier run left frozen (SIGSTOP) must run again to take the signal.
    for pid in running {
      kill(pid, SIGCONT)
      kill(pid, SIGTERM)
    }
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline, running.contains(where: { kill($0, 0) == 0 }) {
      Thread.sleep(forTimeInterval: 0.1)
    }
  }

  /// The app's process, whose log lines the tests read.
  var processID: Int32 { process.processIdentifier }

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
