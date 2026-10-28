import AppIntents
import Foundation
import SalahCore
import SalahUI
import SalahWidgets
import SwiftUI
import WidgetKit

extension SalahWidgetEntry: TimelineEntry {}

/// The extension computes the schedule itself from canonical mirrored settings.
struct IOSPrayerWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> SalahWidgetEntry { sampleEntry() }

  func getSnapshot(
    in context: Context, completion: @escaping @Sendable (SalahWidgetEntry) -> Void
  ) {
    let now = Date()
    guard let settings = SharedValue.settings.load() else {
      completion(context.isPreview ? sampleEntry() : .init(date: now, content: .setupNeeded))
      return
    }
    completion(
      .init(
        date: now,
        content: .schedule(
          SalahDisplay(
            date: now, settings: settings, schedule: settings.schedule,
            playback: SharedValue<IOSPlaybackSession>.iosPlayback.load()?.playing(at: now)))))
  }

  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<SalahWidgetEntry>) -> Void
  ) {
    let timeline = IOSSurfaceTimeline.makeForPublication(
      settings: SharedValue.settings.load(), now: Date(),
      loadSession: { SharedValue<IOSPlaybackSession>.iosPlayback.load() })
    let policy: TimelineReloadPolicy
    switch timeline.reload {
    case .never: policy = .never
    case .after(let date): policy = .after(date)
    }
    completion(Timeline(entries: timeline.entries, policy: policy))
  }

  private func sampleEntry() -> SalahWidgetEntry {
    var preferences = IOSPreferences()
    preferences.location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262,
      timeZone: TimeZone(identifier: "Asia/Riyadh") ?? .gmt, countryCode: "SA", name: "Makkah")
    // The gallery alone may show example data. Placed widgets never invent a location.
    guard let settings = preferences.mirror else {
      return .init(date: .now, content: .setupNeeded)
    }
    return .init(
      date: .now,
      content: .schedule(SalahDisplay(date: .now, settings: settings, schedule: settings.schedule)))
  }
}

struct IOSPrayerWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: SalahWidgetConstants.prayerTimesWidgetKind, provider: IOSPrayerWidgetProvider()
    ) { entry in
      IOSPrayerWidgetView(entry: entry)
    }
    .configurationDisplayName("Prayer times")
    .description("Your next prayer and today's times, with a sky that follows the day.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
      .accessoryInline, .accessoryCircular, .accessoryRectangular,
    ])
    .contentMarginsDisabled()
  }
}

struct IOSPrayerWidgetView: View {
  let entry: SalahWidgetEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.locale) private var locale

  private var isAccessory: Bool {
    [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(family)
  }

  var body: some View {
    switch entry.content {
    case .setupNeeded:
      shell(settings: nil, phase: .fajr) {
        message(
          title: IOSL10n.text(
            "Open Salah to set up prayer times",
            arabic: "افتح صلاة لإعداد أوقات الصلاة", locale: locale)
        )
        .widgetURL(IOSSurfaceLink.location)
      }
    case .expired(let settings):
      shell(settings: settings, phase: .fajr) {
        message(
          title: IOSL10n.text(
            "Times need updating.\nOpen Salah to refresh.",
            arabic: "يلزم تحديث الأوقات.\nافتح صلاة للتحديث.", locale: settings.locale)
        )
        .widgetURL(IOSSurfaceLink.today)
      }
    case .schedule(let display):
      shell(settings: display.settings, phase: messagePhase(for: display)) {
        if isAccessory {
          IOSAccessoryFace(display: display, family: family)
            .widgetURL(IOSSurfaceLink.today)
        } else {
          homeFace(display)
        }
      }
    }
  }

  /// Recovery uses the design's quiet dawn backdrop without implying a prayer time.
  private func messagePhase(for display: SalahDisplay) -> SalahPhase {
    if case .unavailable = display.widgetFace { return .fajr }
    return display.phase
  }

  @ViewBuilder
  private func homeFace(_ display: SalahDisplay) -> some View {
    switch display.widgetFace {
    case .stop:
      if let stop = WidgetStopContent(display: display, size: family.salahSize) {
        Button(intent: IOSStopAudioIntent()) { stop }
          .buttonStyle(.plain)
          .invalidatableContent()
      }
    case .unavailable:
      message(
        title: IOSL10n.text(
          "Times unavailable.\nOpen Salah to retry.",
          arabic: "الأوقات غير متاحة.\nافتح صلاة للمحاولة.", locale: display.locale)
      )
      .widgetURL(IOSSurfaceLink.location)
    case .schedule:
      WidgetContentView(display: display, size: family.salahSize)
        .widgetURL(IOSSurfaceLink.today)
    }
  }

  @ViewBuilder
  private func message(title: String) -> some View {
    if isAccessory {
      if family == .accessoryInline {
        Label(title, systemImage: "moon.stars")
      } else {
        VStack(spacing: 3) {
          Image(systemName: "moon.stars").accessibilityHidden(true)
          Text(verbatim: title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
        }
        .padding(4)
        .accessibilityElement(children: .combine)
      }
    } else {
      WidgetMessageContent(systemImage: "moon.stars", message: Text(verbatim: title))
    }
  }

  private func shell<Content: View>(
    settings: SalahSettings?, phase: SalahPhase, @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .environment(\.locale, settings?.locale ?? locale)
      .environment(
        \.layoutDirection,
        (settings?.locale ?? locale).language.characterDirection == .rightToLeft
          ? .rightToLeft : .leftToRight
      )
      .salahColorScheme(settings?.appearance.colorScheme)
      .containerBackground(for: .widget) {
        if !isAccessory {
          WidgetSky(phase: phase).salahColorScheme(settings?.appearance.colorScheme)
        }
      }
  }
}

extension WidgetFamily {
  fileprivate var salahSize: SalahWidgetSize {
    switch self {
    case .systemMedium: .medium
    case .systemLarge: .large
    case .systemExtraLarge: .extraLarge
    default: .small
    }
  }
}

/// Accessories remain legible in system-vibrant rendering and never expose a compact Stop action.
private struct IOSAccessoryFace: View {
  let display: SalahDisplay
  let family: WidgetFamily
  @Environment(\.salahTimerPause) private var pause

  var body: some View {
    if let focus = display.focus {
      let name = display.name(of: focus.event)
      switch family {
      case .accessoryInline:
        IOSAccessoryCopy.inlineText(display: display, pause: pause)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(accessibilityLabel)
      case .accessoryCircular:
        Gauge(value: progress) {
          PrayerGlyph(kind: focus.event.kind, observance: focus.event.observance)
        } currentValueLabel: {
          VStack(spacing: 1) {
            PrayerGlyph(kind: focus.event.kind, observance: focus.event.observance).font(.caption)
            IOSAccessoryTimer(display: display, focus: focus)
              .font(.caption2.weight(.semibold))
              .minimumScaleFactor(0.7)
          }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityLabel(accessibilityLabel)
      default:
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            PrayerGlyph(kind: focus.event.kind, observance: focus.event.observance).font(.caption)
              .accessibilityHidden(true)
            Text(verbatim: name).font(.headline)
            Spacer(minLength: 2)
            Text(verbatim: display.timeText(of: focus.event)).font(.caption2)
          }
          IOSAccessoryCopy.clockText(display: display, focus: focus, pause: pause)
            .font(.title3.weight(.medium)).monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
          ProgressView(value: progress).tint(.primary)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
      }
    } else {
      Text(verbatim: display.labels.nextUnknown).font(.caption)
    }
  }

  private var accessibilityLabel: Text {
    IOSAccessoryCopy.accessibilityLabel(display: display, pause: pause)
  }

  private var progress: Double {
    guard let state = display.prayerState, let next = state.next else { return 0 }
    let start = state.previous?.time ?? display.date
    let interval = next.time.timeIntervalSince(start)
    guard interval > 0 else { return 0 }
    return min(1, max(0, display.date.timeIntervalSince(start) / interval))
  }
}

/// WidgetKit advances timer text even when it has not requested another timeline entry.
private struct IOSAccessoryTimer: View {
  let display: SalahDisplay
  let focus: SalahDisplay.Focus
  @Environment(\.salahTimerPause) private var pause

  var body: some View {
    IOSAccessoryCopy.timer(display: display, focus: focus, pause: pause)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.6)
  }
}
