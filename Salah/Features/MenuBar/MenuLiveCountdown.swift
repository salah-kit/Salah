import SalahCore
import SwiftUI

/// The hero countdown / count-up, refined for the in-process menu bar. Like the
/// widget's (private) `RelativeTime` it stays calm at minute resolution - a static
/// `PrayerDurationFormat` string advanced by the dropdown's minute timeline -
/// and drops to Apple's per-second system timer text inside the final minute (and
/// a count-up's first minute), which ticks on its own off the system clock with no
/// re-render of the schedule. Mirrors `RelativeTime` (which is file-private to the
/// widget) using SalahCore's `PrayerDurationFormat`, with one menu-bar tweak:
/// the threshold is `<= 60`, so the minute-aligned timeline entry that lands one
/// minute out already shows the live-ticking final minute instead of a static "1m".
struct MenuLiveCountdown: View {
  /// The prayer time - in the future for a count-down, in the past for a count-up.
  let target: Date
  /// "Now": the dropdown's timeline date, advanced each minute.
  let reference: Date
  let font: Font
  var bold: Bool = false
  var countingUp: Bool = false

  @Environment(\.locale) private var locale

  var body: some View {
    let magnitude = abs(target.timeIntervalSince(reference))
    Group {
      if magnitude <= 60 {
        // Final minute: Apple's system timer text, the one primitive that ticks
        // per-second on its own. `countsDown` is explicit so direction is exact.
        // The system's timer counts against the real clock (`AppClock`).
        let start = AppClock.unshifted(countingUp ? target : reference)
        let end = AppClock.unshifted(countingUp ? target.addingTimeInterval(3600) : target)
        if countingUp {
          HStack(spacing: 0) {
            Text(verbatim: "+")
            Text(timerInterval: start...end, countsDown: false, showsHours: false)
          }
        } else {
          Text(timerInterval: start...max(start, end), countsDown: true, showsHours: false)
        }
      } else {
        // A minute or more out: the calm, static, timeline-advanced string.
        Text(verbatim: MenuDuration.string(magnitude, countingUp: countingUp, locale: locale))
      }
    }
    .font(bold ? font.weight(.bold) : font)
    .monospacedDigit()
    .lineLimit(1)
    .minimumScaleFactor(0.6)
  }
}

/// The dropdown's durations: hours and minutes from an hour on ("2:16"), minutes in words
/// under an hour ("10 min"), with a "+" while a prayer counts up.
enum MenuDuration {
  static func string(_ seconds: TimeInterval, countingUp: Bool = false, locale: Locale) -> String {
    let magnitude = abs(seconds)
    guard magnitude < 3_600 else {
      return PrayerDurationFormat.string(
        magnitude, direction: countingUp ? .elapsed : .remaining, locale: locale)
    }
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .short
    formatter.allowedUnits = [.minute]
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    formatter.calendar = calendar
    let minutes = formatter.string(from: max(60, (magnitude / 60).rounded(.down) * 60)) ?? ""
    return countingUp ? "+\(minutes)" : minutes
  }

  /// A reminder's lead: "10 min", "1 hr, 30 min", in the locale's words and digits.
  static func lead(minutes: Int, locale: Locale) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .short
    formatter.allowedUnits = [.hour, .minute]
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    formatter.calendar = calendar
    return formatter.string(from: TimeInterval(minutes * 60)) ?? ""
  }
}
