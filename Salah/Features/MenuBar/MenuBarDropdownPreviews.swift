#if DEBUG
  import SalahCore
  import SwiftUI

  // MARK: - Preview fixtures

  /// Menu-bar dropdown preview displays: the widget's `WidgetPreviewData` scenarios,
  /// anchored to the real `now` (minute offsets) so the live countdown renders
  /// truthfully, so the two surfaces are verified against the same states.
  private enum MenuPreviewData {
    static func idle(rtl: Bool = false) -> SalahDisplay {
      WidgetPreviewData.idle(rtl ? .ar : .en)
    }
    static var silent: SalahDisplay { WidgetPreviewData.silent() }
    static var playing: SalahDisplay { WidgetPreviewData.playing() }
    static var imminent: SalahDisplay { WidgetPreviewData.imminent() }
    static func countUp(rtl: Bool = false) -> SalahDisplay {
      WidgetPreviewData.countUp(rtl ? .ar : .en)
    }
    static var since: SalahDisplay { WidgetPreviewData.since() }
    static var tomorrow: SalahDisplay { WidgetPreviewData.tomorrow() }
  }

  /// One labelled dropdown, clipped like the popover, for side-by-side review.
  private struct MenuDropdownPreview: View {
    let title: String
    let display: SalahDisplay

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(verbatim: title).font(.headline)
        MenuDropdownContent(display: display)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
      }
      .padding(20)
    }
  }

  // MARK: - Previews

  #Preview("Idle · dark") {
    MenuDropdownPreview(title: "Idle", display: MenuPreviewData.idle()).preferredColorScheme(.dark)
  }

  #Preview("Idle · light") {
    MenuDropdownPreview(title: "Idle", display: MenuPreviewData.idle()).preferredColorScheme(
      .light)
  }

  #Preview("Imminent · dark") {
    MenuDropdownPreview(title: "Approaching (<15m)", display: MenuPreviewData.imminent)
      .preferredColorScheme(.dark)
  }

  #Preview("Count-up · dark") {
    MenuDropdownPreview(title: "Count-up “Now”", display: MenuPreviewData.countUp())
      .preferredColorScheme(.dark)
  }

  #Preview("Since previous · dark") {
    MenuDropdownPreview(title: "Since previous prayer", display: MenuPreviewData.since)
      .preferredColorScheme(.dark)
  }

  #Preview("Tomorrow · dark") {
    MenuDropdownPreview(title: "End of day → Tomorrow", display: MenuPreviewData.tomorrow)
      .preferredColorScheme(.dark)
  }

  #Preview("Silent · dark") {
    MenuDropdownPreview(title: "Silent", display: MenuPreviewData.silent).preferredColorScheme(
      .dark)
  }

  #Preview("Playing · dark") {
    MenuDropdownPreview(title: "Playing adhan (Stop)", display: MenuPreviewData.playing)
      .preferredColorScheme(.dark)
  }

  #Preview("Arabic idle · dark") {
    MenuDropdownPreview(title: "Arabic (RTL)", display: MenuPreviewData.idle(rtl: true))
      .preferredColorScheme(.dark)
  }

  #Preview("Arabic count-up · dark") {
    MenuDropdownPreview(
      title: "Arabic count-up (RTL)", display: MenuPreviewData.countUp(rtl: true)
    ).preferredColorScheme(.dark)
  }

#endif
