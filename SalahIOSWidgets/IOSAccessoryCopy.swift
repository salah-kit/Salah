import Foundation
import SalahCore
import SalahUI
import SwiftUI

/// Direction does not identify a language: Persian, Urdu and Arabic use their own catalog copy.
nonisolated enum IOSAccessoryCopy {
  /// The inline host extracts one text value rather than laying out sibling views.
  /// Keep the image and advancing timer inside that same value.
  @MainActor
  static func inlineText(display: SalahDisplay, pause: Date? = nil, bundle: Bundle = .main)
    -> Text
  {
    guard let focus = display.focus else { return Text(verbatim: display.labels.nextUnknown) }
    let glyph = Image(
      PrayerGlyph(kind: focus.event.kind, observance: focus.event.observance).assetName,
      bundle: AppResources.bundle
    ).symbolRenderingMode(.hierarchical)
    let clock = clockText(display: display, focus: focus, pause: pause, bundle: bundle)
    return Text("\(glyph) \(display.name(of: focus.event)) \(clock)")
  }

  /// A single run keeps the prefix and digits on the same baseline and scaling factor.
  @MainActor
  static func clockText(
    display: SalahDisplay, focus: SalahDisplay.Focus, pause: Date? = nil, bundle: Bundle = .main
  ) -> Text {
    let duration = timer(display: display, focus: focus, pause: pause)
    if focus.isCountUp { return Text("+\(duration)") }
    let prefix = countdownPrefix(locale: display.locale, bundle: bundle)
    return Text("\(prefix) \(duration)")
  }

  @MainActor
  static func timer(display: SalahDisplay, focus: SalahDisplay.Focus, pause: Date? = nil) -> Text {
    if let pause {
      return Text(
        verbatim: display.text.duration(
          abs(focus.event.time.timeIntervalSince(pause)),
          direction: focus.isCountUp ? .elapsed : .remaining))
    }
    return liveTimer(display: display, focus: focus)
  }

  /// Visible and spoken values use the same native timer, which WidgetKit advances itself.
  @MainActor
  static func liveTimer(display: SalahDisplay, focus: SalahDisplay.Focus) -> Text {
    let interval =
      focus.isCountUp
      ? focus.event.time...focus.event.time.addingTimeInterval(15 * 60)
      : display.date...max(display.date, focus.event.time)
    return Text(timerInterval: interval, countsDown: !focus.isCountUp, showsHours: true)
  }

  @MainActor
  static func accessibilityLabel(display: SalahDisplay, pause: Date? = nil) -> Text {
    guard let focus = display.focus else { return Text(verbatim: display.labels.nextUnknown) }
    let duration: Text
    if let pause {
      let seconds =
        focus.isCountUp
        ? pause.timeIntervalSince(focus.event.time) : focus.event.time.timeIntervalSince(pause)
      duration = Text(
        verbatim: PrayerDurationFormat.string(
          max(0, seconds), direction: focus.isCountUp ? .elapsed : .remaining,
          width: .spoken, locale: display.locale))
    } else {
      duration = liveTimer(display: display, focus: focus)
    }
    return Text(
      "\(display.name(of: focus.event)), \(display.timeText(of: focus.event)), \(duration)")
  }

  static func countdownPrefix(locale: Locale, bundle: Bundle = .main) -> String {
    IOSL10n.text("in", locale: locale, bundle: bundle)
  }
}
