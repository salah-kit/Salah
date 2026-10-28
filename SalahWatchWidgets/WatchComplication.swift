import Foundation
import OSLog
import SalahCore
import SalahUI
import SalahWidgets
import SwiftUI
import WidgetKit

extension SalahWidgetEntry: TimelineEntry {
  /// The Smart Stack raises the complication from 15 minutes before a prayer until 15 minutes
  /// after it begins.
  var relevance: TimelineEntryRelevance? {
    guard case .schedule(let display) = content, let state = display.prayerState else {
      return nil
    }
    let near = state.isApproaching || display.focus?.isCountUp == true
    return TimelineEntryRelevance(score: near ? 100 : 1)
  }
}

/// The complications calculate their own schedule from the settings the watch app mirrors
/// into its App Group, so they keep counting down while the watch app and the iPhone are away.
struct WatchComplicationProvider: TimelineProvider {
  func placeholder(in context: Context) -> SalahWidgetEntry { Self.sampleEntry(at: .now) }

  func getSnapshot(
    in context: Context, completion: @escaping @Sendable (SalahWidgetEntry) -> Void
  ) {
    let now = Date()
    guard let settings = SharedValue.settings.load() else {
      completion(
        context.isPreview ? Self.sampleEntry(at: now) : .init(date: now, content: .setupNeeded))
      return
    }
    completion(
      .init(
        date: now,
        content: .schedule(
          SalahDisplay(date: now, settings: settings, schedule: settings.schedule))))
  }

  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<SalahWidgetEntry>) -> Void
  ) {
    let timeline = SalahWidgetTimeline.make(
      settings: SharedValue.settings.load(), playback: nil, now: Date())
    Self.log.notice(
      "Timeline in \(context.family.description, privacy: .public): \(timeline.entries.count, privacy: .public) entries, first \(Self.state(of: timeline.entries.first), privacy: .public)"
    )
    let policy: TimelineReloadPolicy
    switch timeline.reload {
    case .never: policy = .never
    case .after(let date): policy = .after(date)
    }
    completion(Timeline(entries: timeline.entries, policy: policy))
  }

  /// When WidgetKit asked for a timeline and what it got, without the place: diagnostics, and
  /// the evidence the Smart Stack journey reads.
  static let log = Logger(
    subsystem: "io.github.salah-kit.Salah.iOS.watchkitapp.Widgets", category: "Timeline")

  static func state(of entry: SalahWidgetEntry?) -> String {
    switch entry?.content {
    case .setupNeeded?: "setup"
    case .expired?: "expired"
    case .schedule?: "schedule"
    case nil: "none"
    }
  }

  /// The gallery alone may show example data: Makkah, in the watch's language. A placed
  /// complication never invents a place.
  static func sampleEntry(at date: Date) -> SalahWidgetEntry {
    let settings = SalahSettings.sample
    return .init(
      date: date,
      content: .schedule(SalahDisplay(date: date, settings: settings, schedule: settings.schedule)))
  }
}

struct WatchPrayerComplication: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WatchComplicationKind.prayer, provider: WatchComplicationProvider()) {
      entry in
      WatchComplicationView(entry: entry)
    }
    .configurationDisplayName("Next prayer")
    .description("The next prayer and its countdown.")
    .supportedFamilies([
      .accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner,
    ])
  }
}

/// One complication in its family: the next prayer's glyph, name, time and live countdown, or
/// why there's none. In the watch face's tinted rendering the countdown and the progress keep
/// the face's accent.
struct WatchComplicationView: View {
  let entry: SalahWidgetEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.locale) private var locale

  private var settings: SalahSettings? {
    switch entry.content {
    case .setupNeeded: nil
    case .expired(let settings): settings
    case .schedule(let display): display.settings
    }
  }

  var body: some View {
    let locale = settings?.locale ?? locale
    content
      .environment(\.locale, locale)
      .environment(
        \.layoutDirection,
        locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
      )
      .widgetURL(URL(string: "salah://now"))
      .containerBackground(for: .widget) {}
  }

  @ViewBuilder
  private var content: some View {
    switch entry.content {
    case .setupNeeded:
      message(
        WatchComplicationCopy.setUp(locale: settings?.locale ?? locale), systemImage: "iphone")
    case .expired(let settings):
      message(WatchComplicationCopy.refresh(locale: settings.locale), systemImage: "moon.stars")
    case .schedule(let display):
      if let focus = display.focus {
        WatchAccessoryFace(display: display, focus: focus, family: family)
      } else {
        message(display.labels.nextUnknown, systemImage: "moon.stars")
      }
    }
  }

  @ViewBuilder
  private func message(_ text: String, systemImage: String) -> some View {
    switch family {
    case .accessoryInline:
      Label(text, systemImage: systemImage)
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: systemImage).font(.title3)
      }
      .accessibilityLabel(Text(verbatim: text))
    case .accessoryCorner:
      Image(systemName: systemImage)
        .font(.title3)
        .widgetLabel { Text(verbatim: text) }
        .accessibilityLabel(Text(verbatim: text))
    default:
      HStack(spacing: 6) {
        Image(systemName: systemImage).accessibilityHidden(true)
        Text(verbatim: text)
          .font(.headline)
          .lineLimit(3)
          .minimumScaleFactor(0.8)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// The complications' own wording: what to do when they can't count down.
nonisolated enum WatchComplicationCopy {
  static func setUp(locale: Locale) -> String {
    WatchCopy(locale: locale)("Set up Salah on your iPhone", "أعدّ صلاة على جهاز iPhone")
  }

  static func refresh(locale: Locale) -> String {
    WatchCopy(locale: locale)("Open Salah to refresh the times", "افتح صلاة لتحديث الأوقات")
  }

  /// The share of the time from the previous prayer to the next that has passed, for the
  /// gauges and the progress bar.
  static func progress(display: SalahDisplay) -> Double {
    guard let state = display.prayerState, let next = state.next else { return 0 }
    let start = state.previous?.time ?? display.date
    let interval = next.time.timeIntervalSince(start)
    guard interval > 0 else { return 0 }
    return min(1, max(0, display.date.timeIntervalSince(start) / interval))
  }

  /// The inline family's short form when the countdown doesn't fit: "Asr 3:35 PM".
  static func shortInline(display: SalahDisplay, focus: SalahDisplay.Focus) -> String {
    display.name(of: focus.event) + " " + display.timeText(of: focus.event)
  }
}

/// The focus in each accessory family, as the iPhone's Lock Screen draws it, and the watch's
/// corner.
struct WatchAccessoryFace: View {
  let display: SalahDisplay
  let focus: SalahDisplay.Focus
  let family: WidgetFamily
  @Environment(\.salahTimerPause) private var pause
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.colorSchemeContrast) private var contrast

  private var progress: Double { WatchComplicationCopy.progress(display: display) }
  private var name: String { display.name(of: focus.event) }
  /// Gold in full color; the face's own accent when the face is tinted.
  private var accent: Color {
    renderingMode == .fullColor ? WatchTheme(contrast: contrast).accentText : .primary
  }

  var body: some View {
    switch family {
    case .accessoryInline:
      ViewThatFits {
        IOSAccessoryCopy.inlineText(display: display, pause: pause, bundle: AppResources.bundle)
        Text(verbatim: WatchComplicationCopy.shortInline(display: display, focus: focus))
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel)
    case .accessoryCircular:
      Gauge(value: progress) {
        glyph
      } currentValueLabel: {
        VStack(spacing: 1) {
          glyph.font(.caption)
          timer.font(.caption2.weight(.semibold))
        }
      }
      .gaugeStyle(.accessoryCircularCapacity)
      .tint(accent)
      .accessibilityLabel(accessibilityLabel)
    case .accessoryCorner:
      glyph
        .font(.title3)
        .widgetAccentable()
        .widgetLabel {
          Gauge(value: progress) {
            Text(verbatim: name)
          } currentValueLabel: {
            timerText
          } minimumValueLabel: {
            Text(verbatim: name)
          } maximumValueLabel: {
            timerText
          }
          .tint(accent)
        }
        .accessibilityLabel(accessibilityLabel)
    default:
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 5) {
          glyph.font(.headline).accessibilityHidden(true)
          Text(verbatim: name).font(.headline)
          Spacer(minLength: 2)
          Text(verbatim: display.timeText(of: focus.event))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        IOSAccessoryCopy.clockText(
          display: display, focus: focus, pause: pause, bundle: AppResources.bundle
        )
        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
        .foregroundStyle(accent)
        .widgetAccentable()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        ProgressView(value: progress)
          .tint(accent)
          .widgetAccentable()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel)
    }
  }

  /// Custom prayer symbols never mirror.
  private var glyph: some View {
    Image(focus.event.glyphName, bundle: AppResources.bundle)
      .symbolRenderingMode(.hierarchical)
      .environment(\.layoutDirection, .leftToRight)
  }

  /// WidgetKit advances the timer itself, without asking for another entry.
  private var timerText: Text {
    IOSAccessoryCopy.timer(display: display, focus: focus, pause: pause).monospacedDigit()
  }

  private var timer: some View {
    timerText
      .lineLimit(1)
      .minimumScaleFactor(0.6)
  }

  private var accessibilityLabel: Text {
    IOSAccessoryCopy.accessibilityLabel(display: display, pause: pause)
  }
}
