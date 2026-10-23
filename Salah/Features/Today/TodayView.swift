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
        HStack(alignment: .top, spacing: 20) {
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
      .padding(6)
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
        // A plain push button: the window's gold tint is for its controls, not this one.
        Button(action: onQuit) {
          Text(verbatim: localizedString("menu.quit", locale: display.locale))
        }
        .tint(.primary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .frame(minHeight: 50)
      .background(colors.palette.formGroup.color, in: RoundedRectangle(cornerRadius: 12))
    }
  }
}
