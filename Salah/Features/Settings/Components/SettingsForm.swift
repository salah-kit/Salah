import SwiftUI

/// The settings panes' grouped form at the design's metrics: 38 pt rows, 13 pt bold headers
/// 6 pt above their group, 18 pt between sections, 24 pt side margins, and controls at the
/// regular size. macOS's own grouped form spaces everything more loosely and draws its
/// controls small; these adjust it, and keep its native rows and controls.
struct SettingsForm<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    Form { content }
      .formStyle(.grouped)
      // The form adds its own 20 pt to these.
      .contentMargins(.horizontal, SettingsMetrics.sideMargin - 20, for: .scrollContent)
      // The design draws controls at the regular size: a 54 × 24 switch, a 24 pt pop-up.
      .controlSize(.regular)
      // Gold on switches, the slider and the selected segment; pop-ups and push buttons
      // stay neutral (`settingsPopUp()`, `settingsPushButton()`).
      .tint(WindowPalette.accent)
  }
}

/// The design's form metrics, and how far macOS's grouped form is from them.
enum SettingsMetrics {
  static let sideMargin: CGFloat = 24
  /// Between a section's group and the next section.
  static let sectionSpacing: CGFloat = 18
  /// The vertical space the form adds around a row's content (it makes a row at least
  /// 36 pt tall).
  static let formRowPadding: CGFloat = 20
  /// How much nearer to the group above, and to its own group, a header sits than the form
  /// puts it.
  static let headerTopTrim: CGFloat = 12
  static let headerBottomTrim: CGFloat = 5
  /// How much nearer to the toolbar the first header sits.
  static let firstHeaderTopTrim: CGFloat = 15
}

extension View {
  /// A form row at the design's height: 38 pt, 45 with a detail line, or `height`, its
  /// separator included. The form draws a separator below every row but a group's `last`,
  /// outside the row, so the other rows are a point shorter. A row whose content can run
  /// longer, such as a warning, grows from there instead.
  func settingsRow(
    detail: Bool = false, height: CGFloat? = nil, last: Bool = false, grows: Bool = false
  ) -> some View {
    let content =
      (height ?? (detail ? 45 : 38)) - SettingsMetrics.formRowPadding - (last ? 0 : 1)
    return frame(minHeight: content, maxHeight: grows ? nil : content)
  }

  /// A section header's text: 13 pt bold in the primary label color.
  func settingsHeaderFont() -> some View {
    font(.system(size: 13, weight: .bold)).foregroundStyle(.primary)
  }

  /// A section header at the design's distance from the groups: 18 pt below the one above
  /// (4 pt below the toolbar for the first) and 6 pt above its own, plus `extraBottom`.
  func settingsHeaderPlacement(isFirst: Bool = false, extraBottom: CGFloat = 0) -> some View {
    padding(
      .top, -(isFirst ? SettingsMetrics.firstHeaderTopTrim : SettingsMetrics.headerTopTrim)
    )
    .padding(.bottom, extraBottom - SettingsMetrics.headerBottomTrim)
  }

  /// A pop-up as the design draws it: its value in the primary label color, its chevrons
  /// neutral.
  func settingsPopUp() -> some View {
    pickerStyle(.menu).tint(Color.primary)
  }

  /// A secondary action as the design draws it: a bordered capsule push button with its
  /// title in the primary label color.
  func settingsPushButton() -> some View {
    buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Color.primary)
  }
}

/// A section's header: the design's title, at its distance from the groups.
struct SettingsHeader: View {
  private let key: LocalizedStringKey
  private let isFirst: Bool

  init(_ key: LocalizedStringKey, isFirst: Bool = false) {
    self.key = key
    self.isFirst = isFirst
  }

  var body: some View {
    Text(key).settingsHeaderFont().settingsHeaderPlacement(isFirst: isFirst)
  }
}

/// A section's footer: the design's 10 pt secondary text.
struct SettingsFooter: View {
  private let key: LocalizedStringKey

  init(_ key: LocalizedStringKey) { self.key = key }

  var body: some View {
    Text(key).font(.footnote).foregroundStyle(.secondary)
  }
}
