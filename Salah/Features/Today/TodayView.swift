import SalahCore
import SalahUI
import SwiftUI

/// Today, the window's first pane: the date and the place, the next prayer with the day's
/// timeline beneath it, today's prayers, and that Salah keeps running in the menu bar, with
/// Quit Salah. Rendered from the running app's schedule at each minute, like the dropdown.
struct TodayView: View {
  var prayerManager: PrayerManager

  var body: some View {
    TimelineView(.everyMinute) { context in
      TodayContent(
        display: prayerManager.display(at: AppClock.shifted(context.date)),
        onToggleAlert: { prayerManager.preferences.toggleAlert(for: $0) },
        onStop: { prayerManager.audioPlaybackController.stop() },
        onQuit: { prayerManager.quitSalah() })
    }
  }
}

/// The rendered Today for a display: the previewable core of `TodayView`. Its next-prayer
/// card, timeline and rows are the dropdown's.
struct TodayContent: View {
  let display: SalahDisplay
  var onToggleAlert: (PrayerEvent) -> Void = { _ in }
  var onStop: () -> Void = {}
  var onQuit: () -> Void = {}

  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let colors = SalahColors(phase: display.phase, scheme: scheme, contrast: contrast)
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        MenuHeader(display: display, colors: colors)
        TodayColumns(spacing: 20, inset: Self.prayersInset) {
          VStack(spacing: 12) {
            MenuHero(display: display, colors: colors, onStop: onStop)
            if let day = display.listedDay {
              SalahDayTimeline(
                day: day, date: display.date,
                followsTimeOfDay: display.settings.followsTimeOfDay)
            }
          }
          .frame(maxWidth: .infinity)
          prayers(colors: colors)
            .frame(maxWidth: .infinity)
        }
        menuBar(colors: colors)
      }
      .padding(.horizontal, 24)
      .padding(.top, 4)
      .padding(.bottom, 24)
    }
    .environment(\.locale, display.locale)
  }

  /// The prayers card's inset around its rows.
  private static let prayersInset: CGFloat = 6

  // MARK: - Prayers

  @ViewBuilder
  private func prayers(colors: SalahColors) -> some View {
    if case .available(let day, let coverage) = display.day {
      let missing: [PrayerKind: ScheduleGapReason] = {
        if case .partial(let missing) = coverage { return missing }
        return [:]
      }()
      VStack(spacing: 2) {
        PrayerTimesList(
          day: day, state: display.prayerState, names: display.names, countdown: .staticText,
          missing: missing
        ).rows
      }
      .prayerRowStyle(
        MenuRowStyle(
          display: display, colors: colors, isLastKnown: false, onToggleAlert: onToggleAlert)
      )
      .padding(Self.prayersInset)
      .background(colors.palette.formGroup.color, in: RoundedRectangle(cornerRadius: 12))
    } else {
      Label {
        Text(verbatim: display.labels.timesUnavailable)
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "clock.badge.questionmark")
      }
      .font(.callout)
      .foregroundStyle(colors.palette.labelSecondary.color)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(colors.palette.formGroup.color, in: RoundedRectangle(cornerRadius: 12))
    }
  }

  // MARK: - Menu bar

  private func menuBar(colors: SalahColors) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("settings.general.menubar")
        .font(.headline)
        .padding(.leading, 10)
        .accessibilityAddTraits(.isHeader)
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("today.keepsRunning.title")
            .font(.body)
          Text("today.keepsRunning.detail")
            .font(.subheadline)
            .foregroundStyle(colors.palette.labelSecondary.color)
        }
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        // A plain capsule push button: the window's gold tint is for its controls, not this
        // one.
        Button(action: onQuit) {
          Text(verbatim: localizedString("menu.quit", locale: display.locale))
            .fontWeight(.medium)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.primary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .frame(minHeight: 50)
      .background(colors.palette.formGroup.color, in: RoundedRectangle(cornerRadius: 12))
    }
  }
}

/// Today's two columns: the next prayer and the prayers card. The next prayer is as wide as
/// the card's rows, so the card is wider by its inset on each side; both fill the width.
/// The leading column is the first subview, so the order mirrors right to left.
struct TodayColumns: Layout {
  var spacing: CGFloat
  /// The second column's inset on each side.
  var inset: CGFloat

  /// The columns' widths in `width`.
  func widths(_ width: CGFloat) -> (first: CGFloat, second: CGFloat) {
    let first = max(0, (width - spacing - 2 * inset) / 2)
    return (first, first + 2 * inset)
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard subviews.count == 2 else { return .zero }
    let width = proposal.width ?? 600
    let (first, second) = widths(width)
    let height = max(
      subviews[0].sizeThatFits(ProposedViewSize(width: first, height: proposal.height)).height,
      subviews[1].sizeThatFits(ProposedViewSize(width: second, height: proposal.height)).height)
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard subviews.count == 2 else { return }
    let (first, second) = widths(bounds.width)
    subviews[0].place(
      at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
      proposal: ProposedViewSize(width: first, height: bounds.height))
    subviews[1].place(
      at: CGPoint(x: bounds.maxX - second, y: bounds.minY), anchor: .topLeading,
      proposal: ProposedViewSize(width: second, height: bounds.height))
  }
}
