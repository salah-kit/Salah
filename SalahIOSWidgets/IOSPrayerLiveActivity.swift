import ActivityKit
import AppIntents
import SalahCore
import SalahUI
import SwiftUI
import WidgetKit

struct IOSPrayerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SalahActivityAttributes.self) { context in
      IOSActivityCard(state: context.state, isStale: context.isStale)
        .activityBackgroundTint(.clear)
        .activitySystemActionForegroundColor(.white)
        .widgetURL(IOSSurfaceLink.activity)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          IOSActivityGlyph(state: context.state, side: 34)
            .modifier(IOSActivityEnvironment(state: context.state))
        }
        DynamicIslandExpandedRegion(.center) {
          IOSActivityHeading(state: context.state, isStale: context.isStale, centered: true)
            .padding(.top, 12)
            .modifier(IOSActivityEnvironment(state: context.state))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Group {
            if !context.isStale && context.state.mode != .playing {
              IOSActivityTimer(state: context.state, compact: false)
                .foregroundStyle(activityAccent)
            }
          }
          .modifier(IOSActivityEnvironment(state: context.state))
        }
        DynamicIslandExpandedRegion(.bottom) {
          Group {
            if context.state.mode == .playing && !context.isStale {
              IOSActivityStopButton(state: context.state)
            } else {
              VStack(spacing: 10) {
                IOSActivityProgress(state: context.state, isStale: context.isStale)
                HStack {
                  Text(verbatim: context.state.place).privacySensitive()
                  Spacer()
                  Text(
                    verbatim: localized(
                      context.state.muteSounds ? "Muted" : "Sound on",
                      context.state.muteSounds ? "مكتوم" : "الصوت مفعّل", state: context.state))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              .padding(.horizontal, 4)
            }
          }
          .modifier(IOSActivityEnvironment(state: context.state))
        }
      } compactLeading: {
        IOSActivityGlyph(state: context.state, side: 22)
          .modifier(IOSActivityEnvironment(state: context.state))
      } compactTrailing: {
        Group {
          if context.isStale {
            Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
          } else {
            IOSActivityTimer(state: context.state, compact: true)
              .foregroundStyle(activityAccent)
              .frame(maxWidth: 54)
          }
        }
        .modifier(IOSActivityEnvironment(state: context.state))
      } minimal: {
        IOSActivityGlyph(state: context.state, side: 22)
          .modifier(IOSActivityEnvironment(state: context.state))
      }
      .widgetURL(IOSSurfaceLink.activity)
      .keylineTint(activityAccent)

    }
  }

  private var activityAccent: Color { SalahPalette(isDark: true).accentFill.color }
}

/// Shared state rendering keeps Lock Screen and Dynamic Island descriptions consistent.
struct IOSActivityCard: View {
  let state: SalahActivityAttributes.ContentState
  var isStale = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        IOSActivityGlyph(state: state, side: 36)
        IOSActivityHeading(state: state, isStale: isStale)
        Spacer(minLength: 4)
        if isStale {
          Text("\(localized("Updated", "حُدّث", state: state)) \(state.updatedAt, style: .time)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if state.mode == .playing {
          IOSActivityStopButton(state: state, compact: true)
        } else {
          IOSActivityTimer(state: state, compact: false)
            .foregroundStyle(state.mode == .justStarted ? phase.text.color : Color.white)
        }
      }
      IOSActivityProgress(state: state, isStale: isStale)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
    .background {
      LinearGradient(
        colors: [phase.skyTop.color, phase.skyBottom.color], startPoint: .top, endPoint: .bottom)
    }
    .modifier(IOSActivityEnvironment(state: state))
    .opacity(isStale ? 0.85 : 1)
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
  var isStale = false
  var centered = false

  var body: some View {
    VStack(alignment: centered ? .center : .leading, spacing: 0) {
      Text(
        verbatim: isStale
          ? localized("Update needed", "بحاجة إلى تحديث", state: state) : state.eyebrow
      )
      .font(.caption.weight(.semibold))
      .foregroundStyle(
        state.mode == .justStarted && !isStale
          ? state.phase.colors(isDark: true).text.color
          : SalahPalette(isDark: true).labelSecondary.color)
      Text(
        verbatim: isStale
          ? localized("Refresh in Salah", "حدّث في صلاة", state: state)
          : "\(state.prayerName) · \(state.prayerTimeText)"
      )
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
        HStack(spacing: 0) {
          if state.mode == .justStarted { Text(verbatim: "+") }
          if let pause {
            Text(verbatim: state.clockValue(at: pause))
          } else {
            Text(
              timerInterval: timerRange,
              countsDown: state.mode == .countdown, showsHours: true)
          }
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
    .accessibilityLabel(spokenLabel)
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

  private var spokenLabel: Text {
    if let pause { return Text(verbatim: state.spokenLabel(at: pause)) }
    let timer = Text(
      timerInterval: timerRange, countsDown: state.mode == .countdown, showsHours: true)
    return Text("\(state.prayerName), \(state.eyebrow), \(timer)")
  }
}

private struct IOSActivityProgress: View {
  let state: SalahActivityAttributes.ContentState
  var isStale = false
  @Environment(\.salahTimerPause) private var pause

  var body: some View {
    Group {
      if isStale || pause != nil {
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(SalahPalette(isDark: true).fillSecondary.color)
            Capsule().fill(state.phase.colors(isDark: true).tint.color)
              .frame(width: proxy.size.width * state.progress(at: pause ?? state.updatedAt))
          }
        }
      } else {
        ProgressView(timerInterval: state.progressStart...state.progressEnd, countsDown: false) {
          EmptyView()
        } currentValueLabel: {
          EmptyView()
        }
      }
    }
    .progressViewStyle(.linear)
    .tint(state.phase.colors(isDark: true).tint.color)
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

private func localized(
  _ english: String, _ arabic: String, state: SalahActivityAttributes.ContentState
) -> String {
  IOSL10n.text(english, arabic: arabic, locale: Locale(identifier: state.languageIdentifier))
}

/// Every Live Activity region receives Salah's chosen language, not the host process language.
struct IOSActivityEnvironment: ViewModifier {
  let state: SalahActivityAttributes.ContentState

  func body(content: Content) -> some View {
    content
      .environment(\.colorScheme, .dark)
      .environment(\.locale, Locale(identifier: state.languageIdentifier))
      .environment(\.timeZone, TimeZone(identifier: state.timeZoneIdentifier) ?? .current)
      .environment(\.layoutDirection, state.isRightToLeft ? .rightToLeft : .leftToRight)
  }
}
