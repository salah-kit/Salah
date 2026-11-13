import AppIntents
import Foundation
import OSLog
import SalahCore
import SalahUI
import SalahWidgets
import SwiftUI
import WidgetKit

extension SalahWidgetEntry: TimelineEntry {}

/// The example day the widget gallery and the placeholder show: Makkah on 2 June 2026 at
/// 1:19 PM, as the design draws it, in the device's language.
///
/// It's built from constants alone. The gallery asks for it while a person scrolls, so it
/// reads no shared settings, no location and nothing from disk beyond the string catalog.
nonisolated enum IOSWidgetSample {
  /// 2 June 2026, 1:19 PM in Makkah: Asr is next, 2:16 away.
  static let date = Date(timeIntervalSince1970: 1_780_395_540)

  /// The sample's settings: Makkah, Salah's defaults, and the device's language.
  static func settings(language: AppLanguage = .system, bundle: Bundle = .main) -> SalahSettings? {
    var preferences = IOSPreferences()
    preferences.language = language
    let locale = language.locale
    preferences.location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262,
      timeZone: TimeZone(identifier: "Asia/Riyadh") ?? .gmt, countryCode: "SA",
      name: IOSL10n.text("Makkah", arabic: "مكة المكرمة", locale: locale, bundle: bundle))
    return preferences.mirror
  }

  /// The sample entry, with its countdown standing at the sample's moment.
  static func entry(bundle: Bundle = .main) -> SalahWidgetEntry {
    guard let settings = settings(bundle: bundle) else {
      return .init(date: date, content: .setupNeeded)
    }
    return .init(
      date: date,
      content: .schedule(
        SalahDisplay(date: date, settings: settings, schedule: settings.schedule)),
      stillAt: date)
  }
}

/// The extension computes the schedule itself from canonical mirrored settings.
struct IOSPrayerWidgetProvider: TimelineProvider {
  private static let logger = Logger(
    subsystem: "io.github.salah-kit.Salah.iOS.Widgets", category: "provider")

  /// What a redacted widget is drawn from before its first timeline: the sample's layout.
  func placeholder(in context: Context) -> SalahWidgetEntry { IOSWidgetSample.entry() }

  func getSnapshot(
    in context: Context, completion: @escaping @Sendable (SalahWidgetEntry) -> Void
  ) {
    completion(
      Self.snapshot(
        isPreview: context.isPreview, now: Date(),
        loadSettings: { SharedValue.settings.load() },
        loadSession: { SharedValue<IOSPlaybackSession>.iosPlayback.load() }))
  }

  /// The entry for a snapshot request.
  ///
  /// The gallery's preview is the sample day, returned without reading anything: nothing a
  /// person saved can delay it or leave it blank. A placed widget's snapshot is their own
  /// schedule, or the setup face when Salah hasn't saved one. Placed widgets never invent a
  /// location.
  static func snapshot(
    isPreview: Bool, now: Date, loadSettings: () -> SalahSettings?,
    loadSession: () -> IOSPlaybackSession?, bundle: Bundle = .main
  ) -> SalahWidgetEntry {
    if isPreview { return IOSWidgetSample.entry(bundle: bundle) }
    guard let settings = loadSettings() else {
      return .init(date: now, content: .setupNeeded)
    }
    return .init(
      date: now,
      content: .schedule(
        SalahDisplay(
          date: now, settings: settings, schedule: settings.schedule,
          playback: loadSession()?.playing(at: now))))
  }

  /// How often a family's timeline needs a new entry.
  ///
  /// The small, medium and large faces count down and fill their progress bar by themselves,
  /// so they change only with the schedule's state. WidgetKit draws every entry of a timeline
  /// before it shows the first one; a dozen entries reach the Home Screen far sooner than the
  /// four dozen a stepped timeline holds, which left a newly added widget on its placeholder.
  /// The accessories' gauges and the extra-large face's sun arc are drawn for one moment,
  /// so those families keep the steps.
  static func cadence(for family: WidgetFamily) -> SalahWidgetTimeline.Cadence {
    switch family {
    case .systemSmall, .systemMedium, .systemLarge: .stateChanges
    default: .steps
    }
  }

  func getTimeline(
    in context: Context, completion: @escaping @Sendable (Timeline<SalahWidgetEntry>) -> Void
  ) {
    let started = ContinuousClock.now
    let timeline = IOSSurfaceTimeline.makeForPublication(
      settings: SharedValue.settings.load(), now: Date(),
      cadence: Self.cadence(for: context.family),
      loadSession: { SharedValue<IOSPlaybackSession>.iosPlayback.load() })
    let policy: TimelineReloadPolicy
    switch timeline.reload {
    case .never: policy = .never
    case .after(let date): policy = .after(date)
    }
    let family = String(describing: context.family)
    let planning = ContinuousClock.now - started
    Self.logger.info(
      "Planned \(timeline.entries.count, privacy: .public) entries for \(family, privacy: .public) in \(planning, privacy: .public)"
    )
    completion(Timeline(entries: timeline.entries, policy: policy))
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
  /// The device's direction, which the face replaces with its language's.
  @Environment(\.layoutDirection) private var hostDirection

  private var isAccessory: Bool {
    [.accessoryInline, .accessoryCircular, .accessoryRectangular].contains(family)
  }

  var body: some View {
    face.environment(\.salahTimerPause, entry.stillAt)
  }

  @ViewBuilder
  private var face: some View {
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
      .environment(\.hostLayoutDirection, hostDirection)
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
