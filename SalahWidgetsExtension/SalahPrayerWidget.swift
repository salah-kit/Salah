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
    let timeline = SalahWidgetTimeline.make(
      settings: SharedValue.settings.load(), playback: SharedValue.playback.load(), now: Date())
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
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
      // No settings yet, so no language or theme: the device's language, Nocturne.
      SalahWidgetShell(theme: .nocturne, tone: .normal) { _ in
        WidgetMessageContent(systemImage: "moon.stars", message: Text("widget.openToSetUp"))
          .widgetURL(SalahWidgetConstants.settingsDeepLinkURL)
      }
    case .expired(let settings):
      // The timeline ran out before WidgetKit asked for another: no countdown that
      // would be stale. Opening the app asks WidgetKit for a new timeline.
      SalahWidgetShell(settings: settings) { _ in
        WidgetMessageContent(
          systemImage: "arrow.clockwise",
          message: Text(verbatim: settings.labels.openToUpdate)
        )
        .widgetURL(SalahWidgetConstants.settingsDeepLinkURL)
      }
    case .schedule(let display):
      SalahWidgetShell(display: display) { _ in
        switch display.widgetFace {
        case .stop:
          // While audio plays, the entire widget is the Stop control, even when
          // the surrounding schedule is incomplete. It has no Settings link.
          if let stop = WidgetStopContent(display: display, size: size) {
            Button(intent: StopSalahAudioIntent()) { stop }
              .buttonStyle(.plain)
              .invalidatableContent()
          }
        case .unavailable:
          // The schedule knows nothing usable at this moment.
          WidgetMessageContent(
            systemImage: "exclamationmark.triangle",
            message: Text(verbatim: display.labels.timesUnavailable)
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

/// The container around every face: the themed backdrop as the widget's container
/// background, the locale and layout direction, and a pinned theme appearance.
private struct SalahWidgetShell<Content: View>: View {
  let theme: SalahWidgetTheme
  let tone: SalahWidgetTone
  var locale: Locale?
  var isRightToLeft = false
  @ViewBuilder let content: (SalahWidgetColors) -> Content
  @Environment(\.colorScheme) private var scheme

  init(
    theme: SalahWidgetTheme, tone: SalahWidgetTone, locale: Locale? = nil,
    isRightToLeft: Bool = false, @ViewBuilder content: @escaping (SalahWidgetColors) -> Content
  ) {
    self.theme = theme
    self.tone = tone
    self.locale = locale
    self.isRightToLeft = isRightToLeft
    self.content = content
  }

  init(
    display: SalahDisplay, @ViewBuilder content: @escaping (SalahWidgetColors) -> Content
  ) {
    self.init(
      theme: display.theme, tone: display.backgroundTone, locale: display.locale,
      isRightToLeft: display.isRightToLeft, content: content)
  }

  init(
    settings: SalahSettings, @ViewBuilder content: @escaping (SalahWidgetColors) -> Content
  ) {
    self.init(
      theme: settings.theme, tone: settings.silentMode ? .silent : .normal,
      locale: settings.locale,
      isRightToLeft: settings.locale.language.characterDirection == .rightToLeft,
      content: content)
  }

  var body: some View {
    let colors = theme.colors(for: scheme)
    localized(content(colors))
      .environment(\.salahWidgetBackdrop, SalahWidgetBackdrop(colors: colors, tone: tone))
      // Honor a pinned theme appearance (Always Dark/Light) so the system colors
      // match the themed background; .system passes through unchanged.
      .salahColorScheme(theme.forcedColorScheme)
      .containerBackground(for: .widget) {
        SalahWidgetBackground(tone: tone, colors: colors)
      }
  }

  /// The face in the user's language and direction; the setup face keeps the
  /// device's.
  @ViewBuilder
  private func localized(_ view: Content) -> some View {
    if let locale {
      view
        .environment(\.locale, locale)
        .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
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

extension SalahPrayerWidgetProvider {
  /// The sample settings now, for Xcode's previews.
  fileprivate static var previewEntry: SalahWidgetEntry {
    entry(settings: .sample, at: .now)
  }
}
