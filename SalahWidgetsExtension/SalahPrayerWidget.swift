import AppIntents
import SalahCore
import SalahWidgets
import SwiftUI
import WidgetKit

// MARK: - Timeline

extension SalahWidgetEntry: TimelineEntry {}

/// Builds the widget's timelines in the extension, from the settings the app mirrors
/// into the App Group (`SalahWidgetTimeline`). Nothing depends on the app having run
/// since the last timeline: the extension computes the times itself.
struct SalahPrayerWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> SalahWidgetEntry {
    Self.entry(settings: .sample, at: Date())
  }

  func getSnapshot(
    in context: Context, completion: @escaping @Sendable (SalahWidgetEntry) -> Void
  ) {
    // The gallery shows the user's settings, or sample settings before the app has
    // run; a placed widget with no settings yet gets the setup prompt, never sample
    // times masquerading as real ones.
    let settings = SharedValue.settings.load()
    let now = Date()
    if context.isPreview {
      completion(Self.entry(settings: settings ?? .sample, at: now))
    } else if let settings {
      completion(
        Self.entry(
          settings: settings, playback: SharedValue.playback.load()?.playing(at: now), at: now))
    } else {
      completion(SalahWidgetEntry(date: now, content: .setupNeeded))
    }
  }

  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<SalahWidgetEntry>) -> Void
  ) {
    let timeline = SalahWidgetTimeline.makeForPublication(
      settings: SharedValue.settings.load(), now: Date(),
      loadPlayback: { SharedValue.playback.load() })
    switch timeline.reload {
    case .never:
      completion(Timeline(entries: timeline.entries, policy: .never))
    case .after(let date):
      completion(Timeline(entries: timeline.entries, policy: .after(date)))
    }
  }

  private static func entry(
    settings: SalahSettings, playback: SalahPlayback? = nil, at now: Date
  ) -> SalahWidgetEntry {
    SalahWidgetEntry(
      date: now,
      content: .schedule(
        SalahDisplay(date: now, settings: settings, schedule: settings.schedule, playback: playback)
      ))
  }
}

// MARK: - Widget

struct SalahPrayerWidget: Widget {
  var body: some WidgetConfiguration {
    // StaticConfiguration: the components were chosen to be useful with zero
    // setup, so there is no configuration intent.
    StaticConfiguration(
      kind: SalahWidgetConstants.prayerTimesWidgetKind,
      provider: SalahPrayerWidgetProvider()
    ) { entry in
      SalahPrayerWidgetEntryView(entry: entry)
    }
    .configurationDisplayName(Text("widget.prayerTimes.displayName"))
    .description(Text("widget.prayerTimes.description"))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    // Take over the full widget bounds; each view applies its own padding. The
    // default system content margins double-inset content and were a cause of
    // the large widget's vertical clipping.
    .contentMarginsDisabled()
  }
}

// MARK: - Shell (the only widget-host-dependent layer)

/// The extension shell: it owns everything that needs a widget host - the
/// container background, the deep-link `widgetURL`, and the Stop-intent button -
/// then delegates all rendering to the shared `WidgetUI` content views (which the
/// in-app Appearance preview reuses unchanged).
struct SalahPrayerWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family

  let entry: SalahWidgetEntry

  var body: some View {
    switch entry.content {
    case .setupNeeded:
      // No settings yet, so no language or appearance: the device's, on the neutral sky.
      SalahWidgetShell(phase: .neutral) {
        WidgetMessageContent(systemImage: "moon.stars", message: Text("widget.openToSetUp"))
          .widgetURL(SalahWidgetConstants.settingsDeepLinkURL)
      }
    case .expired(let settings):
      // The timeline ran out before WidgetKit asked for another: no countdown that
      // would be stale. Opening the app asks WidgetKit for a new timeline.
      SalahWidgetShell(settings: settings, phase: .neutral) {
        WidgetMessageContent(
          systemImage: "arrow.clockwise",
          message: Text(verbatim: settings.labels.openToUpdate)
        )
        .widgetURL(SalahWidgetConstants.settingsDeepLinkURL)
      }
    case .schedule(let display):
      SalahWidgetShell(settings: display.settings, phase: display.phase) {
        switch display.widgetFace {
        case .stop:
          // While audio plays, the entire widget is the Stop control, even when
          // the surrounding schedule is incomplete. It has no link.
          if let stop = WidgetStopContent(display: display, size: size) {
            Button(intent: StopSalahAudioIntent()) { stop }
              .buttonStyle(.plain)
              .invalidatableContent()
          }
        case .unavailable:
          // The schedule knows nothing usable at this moment.
          WidgetMessageContent(
            systemImage: "exclamationmark.triangle.fill",
            message: Text(verbatim: display.labels.timesUnavailable), phase: display.phase
          )
          .widgetURL(SalahWidgetConstants.settingsDeepLinkURL)
        case .schedule:
          WidgetContentView(display: display, size: size)
            .widgetURL(SalahWidgetConstants.settingsDeepLinkURL)
        }
      }
    }
  }

  private var size: SalahWidgetSize { family.salahSize }
}

/// The container around every face: the time of day's sky as the widget's container
/// background, so the system can remove it in accented and vibrant rendering; the locale
/// and layout direction; and the appearance the settings choose.
private struct SalahWidgetShell<Content: View>: View {
  var settings: SalahSettings?
  let phase: SalahPhase
  @ViewBuilder let content: () -> Content

  init(
    settings: SalahSettings? = nil, phase: SalahPhase, @ViewBuilder content: @escaping () -> Content
  ) {
    self.settings = settings
    self.phase = phase
    self.content = content
  }

  var body: some View {
    localized(content())
      .salahColorScheme(settings?.appearance.colorScheme)
      .containerBackground(for: .widget) {
        WidgetSky(phase: phase)
          .salahColorScheme(settings?.appearance.colorScheme)
      }
  }

  /// The face in the user's language and direction; the setup face keeps the device's.
  @ViewBuilder
  private func localized(_ view: Content) -> some View {
    if let settings {
      view
        .environment(\.locale, settings.locale)
        .environment(
          \.layoutDirection,
          settings.locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
    } else {
      view
    }
  }
}

extension WidgetFamily {
  /// Maps the WidgetKit family to the app-defined size the shared content uses.
  fileprivate var salahSize: SalahWidgetSize {
    switch self {
    case .systemSmall: .small
    case .systemMedium: .medium
    case .systemLarge: .large
    case .systemExtraLarge: .extraLarge
    default: .small
    }
  }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
  SalahPrayerWidget()
} timeline: {
  SalahPrayerWidgetProvider.previewEntry
}

#Preview("Medium", as: .systemMedium) {
  SalahPrayerWidget()
} timeline: {
  SalahPrayerWidgetProvider.previewEntry
}

#Preview("Large", as: .systemLarge) {
  SalahPrayerWidget()
} timeline: {
  SalahPrayerWidgetProvider.previewEntry
}

#Preview("Extra Large", as: .systemExtraLarge) {
  SalahPrayerWidget()
} timeline: {
  SalahPrayerWidgetProvider.previewEntry
}

extension SalahPrayerWidgetProvider {
  /// The sample settings now, for Xcode's previews.
  fileprivate static var previewEntry: SalahWidgetEntry {
    entry(settings: .sample, at: .now)
  }
}
