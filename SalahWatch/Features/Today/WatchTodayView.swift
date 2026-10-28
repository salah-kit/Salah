import SalahCore
import SwiftUI

/// Today's prayers, sunrise included: the next on the gold wash, the one that just started on
/// the time of day's.
struct WatchTodayView: View {
  let display: SalahDisplay
  @Environment(\.colorSchemeContrast) private var contrast
  private var theme: WatchTheme { WatchTheme(contrast: contrast) }

  var body: some View {
    let presentation = WatchPrayerPresentation(display: display)
    ScrollView {
      VStack(spacing: WatchMetrics.stackGap) {
        if presentation.todayRows.isEmpty {
          Text(verbatim: presentation.heroTime)
            .font(.footnote)
            .foregroundStyle(theme.labelSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        ForEach(presentation.todayRows) { row in
          WatchPrayerRow(row: row, phase: display.phase)
        }
      }
      .padding(.horizontal, WatchMetrics.screenInset)
    }
    .background { WatchSkyBackground(phase: display.phase) }
    .navigationTitle(Text(verbatim: presentation.copy("Today", "اليوم")))
    .navigationBarTitleDisplayMode(.inline)
    // The page's identifier stays its own; its parts keep theirs.
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("screen.today")
  }
}
