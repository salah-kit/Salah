import SwiftUI

/// What the display's hardware does to a view: the fold that crosses it and the content insets
/// beside a vertical bar. Without either, as on iPhone and iPad and before iOS 27.1, there is no
/// fold and the design system's insets apply.
nonisolated struct IOSDisplayGeometry: Equatable, Sendable {
  var size: CGSize
  var fold: IOSFold?
  var insets: IOSContentInsets
  /// The system shows navigation bars, toolbars and tab bars vertically at one side.
  var hasVerticalBar: Bool
  /// Space to keep from the display's top edge when nothing above the view keeps it clear.
  var topMargin: CGFloat = 0

  var pages: IOSFoldPages? { IOSFoldPages(fold: fold, size: size, insets: insets) }
  var contentWidth: CGFloat { max(0, size.width - insets.leading - insets.trailing) }
}

/// A `GeometryReader` that also reports the display's fold and its vertical bar insets.
struct IOSDisplayGeometryReader<Content: View>: View {
  @ViewBuilder var content: (IOSDisplayGeometry) -> Content

  var body: some View {
    if #available(iOS 27.1, *) {
      IOSHingeAwareReader(content: content)
    } else {
      GeometryReader { proxy in
        content(
          IOSDisplayGeometry(
            size: proxy.size, fold: nil, insets: .standard, hasVerticalBar: false))
      }
    }
  }
}

@available(iOS 27.1, *)
private struct IOSHingeAwareReader<Content: View>: View {
  let content: (IOSDisplayGeometry) -> Content
  @Environment(\.toolbarVerticalEdge) private var verticalBarEdge

  var body: some View {
    GeometryReader { proxy in
      // The flat fold is reported too: its region has the same frame as the folded one, so a
      // layout that keeps clear of it doesn't move when the device folds.
      let fold = proxy.reservedRegions(kind: .division, options: .includeInactive).first.map {
        IOSFold(frame: $0.frame, isActive: $0.isActive)
      }
      let margins = proxy.contentMargins(for: .container, edges: .horizontal)
      let hasVerticalBar = verticalBarEdge != nil
      let insets = IOSContentInsets.resolve(
        container: IOSContentInsets(leading: margins.leading, trailing: margins.trailing),
        hasVerticalBar: hasVerticalBar, hasFold: fold != nil)
      content(
        IOSDisplayGeometry(
          size: proxy.size, fold: fold, insets: insets, hasVerticalBar: hasVerticalBar,
          topMargin: insets.topMargin(
            safeAreaTop: proxy.safeAreaInsets.top, hasVerticalBar: hasVerticalBar,
            hasFold: fold != nil)))
    }
  }
}
