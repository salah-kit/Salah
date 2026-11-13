import ActivityKit
import AppIntents
import SalahCore
import SalahUI
import SwiftUI
import WidgetKit

struct IOSPrayerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SalahActivityAttributes.self) { context in
      IOSActivityCard(state: context.shown)
        .activityBackgroundTint(.clear)
        .activitySystemActionForegroundColor(.white)
        .widgetURL(IOSSurfaceLink.activity)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          IOSActivityGlyph(state: context.shown, side: 34)
            .modifier(IOSActivityEnvironment(state: context.shown))
        }
        DynamicIslandExpandedRegion(.center) {
          IOSActivityHeading(state: context.shown, centered: true)
            .padding(.top, 12)
            .modifier(IOSActivityEnvironment(state: context.shown))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Group {
            if context.shown.showsTimer {
              IOSActivityTimer(state: context.shown, compact: false)
                .foregroundStyle(activityAccent)
            }
          }
          .modifier(IOSActivityEnvironment(state: context.shown))
        }
        DynamicIslandExpandedRegion(.bottom) {
          Group {
            if context.shown.mode == .playing {
              IOSActivityStopButton(state: context.shown)
            } else {
              VStack(spacing: 10) {
                IOSActivityProgress(state: context.shown)
                HStack {
                  Text(verbatim: context.shown.place).privacySensitive()
                  Spacer()
                  Text(
                    verbatim: localized(
                      context.shown.muteSounds ? "Muted" : "Sound on",
                      context.shown.muteSounds ? "الصوت مكتوم" : "الصوت مفعّل", state: context.shown)
                  )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .padding(.horizontal, 4)
            }
          }
          .modifier(IOSActivityEnvironment(state: context.shown))
        }
      } compactLeading: {
        IOSActivityIslandWidthReader { isLimitedInWidth in
          if isLimitedInWidth {
            IOSActivityLimitedIsland(state: context.shown)
          } else {
            IOSActivityGlyph(state: context.shown, side: 22)
          }
        }
        .modifier(IOSActivityEnvironment(state: context.shown))
      } compactTrailing: {
        IOSActivityIslandWidthReader { isLimitedInWidth in
          IOSActivityCompactTrailing(state: context.shown, isLimitedInWidth: isLimitedInWidth)
        }
        .modifier(IOSActivityEnvironment(state: context.shown))
      } minimal: {
        IOSActivityIslandWidthReader { isLimitedInWidth in
          if isLimitedInWidth {
            IOSActivityLimitedIsland(state: context.shown)
          } else {
            IOSActivityGlyph(state: context.shown, side: 22)
          }
        }
        .modifier(IOSActivityEnvironment(state: context.shown))
      }
      .widgetURL(IOSSurfaceLink.activity)
      .keylineTint(activityAccent)

    }
  }

  private var activityAccent: Color { SalahPalette(isDark: true).accentFill.color }
}

extension ActivityViewContext<SalahActivityAttributes> {
  /// The state to draw: the published one, or what stays true of it once it is stale.
  fileprivate var shown: SalahActivityAttributes.ContentState { isStale ? state.stale : state }
}

/// Shared state rendering keeps Lock Screen and Dynamic Island descriptions consistent.
struct IOSActivityCard: View {
  let state: SalahActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        IOSActivityGlyph(state: state, side: 36)
        IOSActivityHeading(state: state)
        Spacer(minLength: 4)
        if state.mode == .playing {
          IOSActivityStopButton(state: state, compact: true)
        } else if state.showsTimer {
          IOSActivityTimer(state: state, compact: false)
            .foregroundStyle(state.mode == .justStarted ? phase.text.color : Color.white)
        }
      }
      IOSActivityProgress(state: state)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
    .background {
      LinearGradient(
        colors: [phase.skyTop.color, phase.skyBottom.color], startPoint: .top, endPoint: .bottom)
    }
    .modifier(IOSActivityEnvironment(state: state))
  }

  private var phase: SalahPhase.Colors { state.phase.colors(isDark: true) }
}

private struct IOSActivityGlyph: View {
  let state: SalahActivityAttributes.ContentState
  let side: CGFloat

  var body: some View {
    PrayerGlyph(kind: state.prayerKind, observance: state.prayerObservance)
      .font(.system(size: side * 0.585))
      .frame(width: side, height: side)
      .foregroundStyle(state.phase.colors(isDark: true).tint.color)
      .accessibilityHidden(true)
  }
}

private struct IOSActivityHeading: View {
  let state: SalahActivityAttributes.ContentState
  var centered = false

  var body: some View {
    VStack(alignment: centered ? .center : .leading, spacing: 0) {
      Text(verbatim: state.eyebrow)
        // A stale activity names its place here.
        .privacySensitive(state.eyebrow == state.place)
        .font(.caption.weight(.semibold))
        .foregroundStyle(
          state.mode == .justStarted
            ? state.phase.colors(isDark: true).text.color
            : SalahPalette(isDark: true).labelSecondary.color)
      Text(verbatim: "\(state.prayerName) · \(state.prayerTimeText)")
        .font(.headline)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct IOSActivityTimer: View {
  let state: SalahActivityAttributes.ContentState
  var compact = false
  @Environment(\.salahTimerPause) private var pause

  var body: some View {
    Group {
      if compact {
        // Compact has room for minute accuracy and is status-only; never show a Stop glyph.
        if let pause {
          Text(verbatim: compactValue(at: pause))
        } else if state.mode == .playing {
          Text(.durationOffset(to: state.progressStart), format: elapsedUnits)
        } else {
          Text(
            timerInterval: timerRange,
            countsDown: state.mode == .countdown, showsHours: true)
        }
      } else {
        let reading =
          pause.map { Text(verbatim: state.clockValue(at: $0)) }
          ?? Text(
            timerInterval: timerRange, countsDown: state.mode == .countdown, showsHours: true)
        if state.mode == .justStarted {
          // One run, read left to right, so the sign stays before its digits in Arabic.
          Text("\u{2066}+\(reading)\u{2069}")
        } else {
          reading
        }
      }
    }
    .font(
      compact
        ? .system(.caption, design: .rounded).weight(.semibold).monospacedDigit()
        : .system(.title, design: .rounded).weight(.semibold).monospacedDigit()
    )
    .lineLimit(1)
    .minimumScaleFactor(0.65)
    .accessibilityLabel(spokenTimer(state, pause: pause))
  }

  private var timerRange: ClosedRange<Date> { state.timerInterval }

  private func compactValue(at date: Date) -> String {
    let seconds = state.timerSeconds(at: date)
    if state.mode == .playing { return elapsedUnits.format(.seconds(seconds)) }
    return SalahText(locale: Locale(identifier: state.languageIdentifier), timeZone: .gmt)
      .duration(seconds, direction: state.mode == .countdown ? .remaining : .elapsed)
  }

  private var elapsedUnits: Duration.UnitsFormatStyle {
    Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .narrow)
      .locale(Locale(identifier: state.languageIdentifier))
  }
}

private struct IOSActivityProgress: View {
  let state: SalahActivityAttributes.ContentState
  @Environment(\.salahTimerPause) private var pause

  var body: some View {
    Group {
      if let pause {
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(SalahPalette(isDark: true).fillSecondary.color)
            Capsule().fill(state.phase.colors(isDark: true).tint.color)
              .frame(width: proxy.size.width * state.progress(at: pause))
          }
        }
      } else {
        IOSRunningProgress(
          span: state.progressStart...state.progressEnd,
          tint: AnyShapeStyle(state.phase.colors(isDark: true).tint.color))
      }
    }
    .frame(height: 4)
    .accessibilityHidden(true)
  }
}

private struct IOSActivityStopButton: View {
  let state: SalahActivityAttributes.ContentState
  var compact = false

  var body: some View {
    Button(intent: IOSStopAudioIntent()) {
      Label {
        Text(verbatim: localized("Stop", "إيقاف", state: state))
      } icon: {
        Image(systemName: "stop.fill")
      }
      .font(compact ? .subheadline.weight(.semibold) : .headline)
      .frame(maxWidth: compact ? nil : .infinity)
      .padding(.vertical, compact ? 8 : 10)
      .padding(.horizontal, compact ? 14 : 0)
      .background(SalahPalette(isDark: true).accentFill.color, in: Capsule())
      .foregroundStyle(SalahPalette(isDark: true).labelOnAccent.color)
    }
    .buttonStyle(.plain)
  }
}

private func spokenTimer(_ state: SalahActivityAttributes.ContentState, pause: Date?) -> Text {
  if let pause { return Text(verbatim: state.spokenLabel(at: pause)) }
  guard state.showsTimer || state.mode == .playing else {
    return Text(verbatim: state.spokenLabel(at: state.updatedAt))
  }
  let timer = Text(
    timerInterval: state.timerInterval, countsDown: state.mode == .countdown, showsHours: true)
  let comma = localized(", ", "، ", state: state)
  return Text("\(state.prayerName)\(comma)\(state.eyebrow)\(comma)\(timer)")
}

private func localized(
  _ english: String, _ arabic: String, state: SalahActivityAttributes.ContentState
) -> String {
  IOSL10n.text(english, arabic: arabic, locale: Locale(identifier: state.languageIdentifier))
}

/// Every Live Activity region receives Salah's chosen language, not the host process language.
struct IOSActivityEnvironment: ViewModifier {
  let state: SalahActivityAttributes.ContentState
  /// The device's direction, which the activity replaces with its language's.
  @Environment(\.layoutDirection) private var hostDirection

  func body(content: Content) -> some View {
    content
      .environment(\.hostLayoutDirection, hostDirection)
      .environment(\.colorScheme, .dark)
      .environment(\.locale, Locale(identifier: state.languageIdentifier))
      .environment(\.timeZone, TimeZone(identifier: state.timeZoneIdentifier) ?? .current)
      .environment(\.layoutDirection, state.isRightToLeft ? .rightToLeft : .leftToRight)
  }
}

/// iPhone Duo's vertical Dynamic Island, like the island on iPhone in landscape, fits compact
/// and minimal presentations in a 28-point circle and shows the leading view alone.
private struct IOSActivityIslandWidthReader<Content: View>: View {
  @ViewBuilder let content: (Bool) -> Content

  var body: some View {
    if #available(iOS 27.0, *) {
      IOSActivityIslandWidth(content: content)
    } else {
      content(false)
    }
  }
}

@available(iOS 27.0, *)
private struct IOSActivityIslandWidth<Content: View>: View {
  let content: (Bool) -> Content
  @Environment(\.isDynamicIslandLimitedInWidth) private var isLimitedInWidth

  var body: some View { content(isLimitedInWidth) }
}

/// The limited-width island's only view: progress toward the prayer, or through the playing
/// sound, around its glyph.
struct IOSActivityLimitedIsland: View {
  let state: SalahActivityAttributes.ContentState
  @Environment(\.salahTimerPause) private var pause

  var body: some View {
    ZStack {
      if let pause {
        Circle().strokeBorder(SalahPalette(isDark: true).fillSecondary.color, lineWidth: 3)
        Circle()
          .inset(by: 1.5)
          .trim(from: 0, to: state.progress(at: pause))
          .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
          .rotationEffect(.degrees(-90))
      } else {
        ProgressView(timerInterval: state.progressStart...state.progressEnd, countsDown: false) {
          EmptyView()
        } currentValueLabel: {
          EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(tint)
      }
      symbol
    }
    .frame(width: 28, height: 28)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spokenTimer(state, pause: pause))
  }

  @ViewBuilder private var symbol: some View {
    if state.mode == .playing {
      Image(systemName: "speaker.wave.2.fill")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(tint)
    } else {
      IOSActivityGlyph(state: state, side: 18)
    }
  }

  private var tint: Color { state.phase.colors(isDark: true).tint.color }
}

/// With limited width only the leading view shows, so the trailing view stays empty.
struct IOSActivityCompactTrailing: View {
  let state: SalahActivityAttributes.ContentState
  let isLimitedInWidth: Bool

  var body: some View {
    if isLimitedInWidth || state.mode == .ended {
      EmptyView()
    } else {
      IOSActivityTimer(state: state, compact: true)
        .foregroundStyle(SalahPalette(isDark: true).accentFill.color)
        .frame(maxWidth: 54)
    }
  }
}
