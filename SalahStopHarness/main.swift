import Foundation
import SalahCore
import SalahWidgets

// A stand-in for the widget extension in the real-app tests (`SalahRoundTripTests`): a
// background-only app signed like the extension, sandboxed in the same App Group, that
// runs the Stop intent's own code and reads back what the app stored. It prints one JSON
// report on standard output.
//
//   SalahStopHarness stop     the intent's `perform()`: clear what's playing, post the signal
//   SalahStopHarness signal   post the signal alone, leaving the stored value
//   SalahStopHarness read     only read

/// What the harness did and what the App Group holds afterwards.
struct Report: Encodable {
  /// The widget's first timeline entry, built by the extension's own code from what the
  /// App Group holds.
  struct Widget: Encodable {
    /// `setupNeeded`, `schedule`, `unavailable` or `expired`.
    var firstEntry: String
    /// Whether the entry draws the Stop control.
    var showsStop: Bool
  }

  var command: String
  var signalAccepted: Bool?
  var hasSettings: Bool
  var playback: SalahPlayback?
  var widget: Widget?
}

let command = CommandLine.arguments.dropFirst().first ?? "read"
var report = Report(command: command, hasSettings: false)
switch command {
case "stop":
  _ = try await StopSalahAudioIntent().perform()
case "signal":
  report.signalAccepted = DarwinSignal.stopAudio.post()
case "read":
  break
default:
  FileHandle.standardError.write(Data("usage: SalahStopHarness stop|signal|read\n".utf8))
  exit(2)
}

let settings = SharedValue.settings.load()
report.hasSettings = settings != nil
report.playback = SharedValue.playback.load()
let timeline = SalahWidgetTimeline.make(
  settings: settings, playback: report.playback, now: Date())
if let entry = timeline.entries.first {
  switch entry.content {
  case .setupNeeded:
    report.widget = Report.Widget(firstEntry: "setupNeeded", showsStop: false)
  case .expired:
    report.widget = Report.Widget(firstEntry: "expired", showsStop: false)
  case .schedule(let display):
    // Use the extension and preview's face decision, including playback in a gap.
    report.widget = Report.Widget(
      firstEntry: display.widgetFace == .unavailable ? "unavailable" : "schedule",
      showsStop: display.widgetFace == .stop)
  }
}
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.sortedKeys]
print(String(decoding: try encoder.encode(report), as: UTF8.self))
