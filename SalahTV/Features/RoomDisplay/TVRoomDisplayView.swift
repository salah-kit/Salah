import SalahCore
import SalahUI
import SwiftUI

/// The day's times kept on screen for a room: the next prayer, a large clock and a cell per
/// prayer. The screen saver stays off while it's open, and nothing takes focus; Back leaves.
struct TVRoomDisplayView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(TVNavigation.self) private var navigation
  @Environment(TVAppRuntime.self) private var runtime
  @ScaledMetric(relativeTo: .title) private var clockSize = TVNumeral.clock

  var body: some View {
    ZStack(alignment: .topLeading) {
      TVSkyBackground(phase: store.display?.phase ?? .neutral)
      if let display = store.display {
        let presentation = TVPrayerPresentation(display: display, preferences: store.preferences)
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .top, spacing: 80) {
            TVNextPrayerHero(presentation: presentation)
            Spacer(minLength: 0)
            clock(presentation)
          }
          Spacer(minLength: 24)
          HStack(alignment: .top, spacing: TVMetrics.gutter) {
            ForEach(display.slots) { slot in
              switch slot {
              case .event(let event):
                TVBoardCell(event: event, presentation: presentation)
              case .missing(let kind):
                TVMissingCell(name: display.name(of: kind), copy: presentation.copy)
              }
            }
          }
          // The row takes its tallest cell's height, so the free space stays above it.
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityElement(children: .contain)
        }
        .padding(.horizontal, TVMetrics.safeHorizontal)
        .padding(.vertical, TVMetrics.safeVertical)
      } else {
        TVUnavailableView()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .ignoresSafeArea()
    // Nothing on the board takes focus, so the board itself receives Back.
    .focusable()
    .focusEffectDisabled()
    .onExitCommand { navigation.dismissFullScreen() }
    .onAppear { runtime.roomDisplayAppeared() }
    .onDisappear { runtime.roomDisplayDisappeared() }
    .accessibilityElement(children: .contain)
    .accessibilityValue(
      runtime.keepsScreenOn
        ? TVCopy(locale: store.locale)("The screen stays on", "تبقى الشاشة قيد التشغيل") : ""
    )
    .accessibilityIdentifier("room")
  }

  private func clock(_ presentation: TVPrayerPresentation) -> some View {
    let display = presentation.display
    let time = presentation.time
    let source = TVSourceNote(display: display, preferences: store.preferences)
    return VStack(alignment: .trailing, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(verbatim: time.clock(display.date))
          .font(TVNumeral.font(size: clockSize))
        if let period = time.period(display.date) {
          Text(verbatim: period).font(.headline.weight(.medium))
        }
      }
      .foregroundStyle(TVTheme.labelPrimary)
      .lineLimit(1)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(time.time(display.date))
      .accessibilityIdentifier("room.clock")
      Text(
        verbatim:
          "\(display.header.hijriDay) \(display.header.hijriMonth) \(display.header.hijriYear)"
      )
      .font(.headline.bold())
      .foregroundStyle(TVTheme.labelPrimary)
      Text(
        verbatim: [display.header.gregorianDate, source.place].filter { !$0.isEmpty }
          .joined(separator: " · ")
      )
      .font(.callout.weight(.medium))
      .foregroundStyle(TVTheme.labelSecondary)
      VStack(alignment: .trailing, spacing: 6) {
        Text(
          verbatim: "\(TVSettingsCopy(locale: display.locale).methodName(store.preferences)) · "
            + source.calculatedFor
        )
        .foregroundStyle(TVTheme.labelSecondary)
        Text(
          verbatim: presentation.copy(
            "The screen stays on while this is open. Press Back to leave.",
            "تبقى الشاشة قيد التشغيل ما دام هذا مفتوحًا. اضغط رجوع للخروج.")
        )
        .foregroundStyle(TVTheme.labelTertiary)
      }
      .font(.caption.weight(.medium))
      .multilineTextAlignment(.trailing)
      .frame(maxWidth: 820, alignment: .trailing)
      .padding(.top, 18)
    }
    .lineLimit(2)
  }
}

/// A prayer the schedule couldn't give, in place of its cell.
struct TVMissingCell: View {
  let name: String
  let copy: TVCopy

  @ScaledMetric(relativeTo: .title2) private var height: CGFloat = 404

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: name).font(.title3.weight(.medium))
      Text(verbatim: copy("Not available", "غير متاح")).font(.callout)
      Spacer(minLength: 0)
    }
    .foregroundStyle(TVTheme.labelSecondary)
    .padding(24)
    .frame(width: TVMetrics.boardColumn, alignment: .leading)
    .frame(minHeight: height, maxHeight: .infinity, alignment: .top)
    .background(TVTheme.fillQuaternary, in: .rect(cornerRadius: 32))
    .accessibilityElement(children: .combine)
  }
}
