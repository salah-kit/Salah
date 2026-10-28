import SalahCore
import SwiftUI

/// The first page: the next prayer and the rest of its day. While the adhan plays, its hero
/// holds Stop.
struct WatchNowView: View {
  let display: SalahDisplay
  @Environment(WatchAppRuntime.self) private var runtime

  var body: some View {
    let presentation = WatchPrayerPresentation(display: display)
    ScrollView {
      VStack(spacing: WatchMetrics.stackGap) {
        WatchPrayerHero(presentation: presentation) { runtime.stopAdhan() }
        ForEach(presentation.followingRows) { row in
          WatchPrayerRow(row: row, phase: display.phase)
        }
      }
      .padding(.horizontal, WatchMetrics.screenInset)
    }
    .background { WatchSkyBackground(phase: display.phase) }
    .navigationTitle(Text(verbatim: presentation.copy("Salah", "صلاة")))
    .navigationBarTitleDisplayMode(.inline)
    // The page's identifier stays its own; its parts keep theirs.
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("screen.now")
  }
}
