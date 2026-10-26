import CoreGraphics

/// The hinge where it crosses a view: the division region iOS reserves on iPhone Duo's inner
/// display. Its frame includes the system's margins either side of the hinge line, and it is the
/// same whether the device is flat or folded, so a layout that keeps clear of it never moves.
nonisolated struct IOSFold: Equatable, Sendable {
  enum Axis: Equatable, Sendable {
    /// The fold runs top to bottom, as when the device is held like a book: pages sit side by side.
    case vertical
    /// The fold runs across, as when the device is propped like a laptop: pages stack.
    case horizontal
  }

  var frame: CGRect
  var isActive: Bool

  var axis: Axis { frame.height >= frame.width ? .vertical : .horizontal }
}

/// Horizontal content insets. iPhone and iPad keep the design system's screen margin. Beside
/// iPhone Duo's vertical bar, and on its folding display, the system's container margins apply:
/// they keep the far side's margin and bring content up to the bar.
nonisolated struct IOSContentInsets: Equatable, Sendable {
  var leading: CGFloat
  var trailing: CGFloat

  static let standard = IOSContentInsets(
    leading: IOSMetrics.screenMargin, trailing: IOSMetrics.screenMargin)

  static func resolve(container: IOSContentInsets?, hasVerticalBar: Bool, hasFold: Bool)
    -> IOSContentInsets
  {
    guard hasVerticalBar || hasFold, let container else { return .standard }
    return container
  }

  /// With its bars on the side, iPhone Duo has no status bar above the content: a screen without
  /// a navigation bar keeps the far side's margin from the display's top edge instead.
  func topMargin(safeAreaTop: CGFloat, hasVerticalBar: Bool, hasFold: Bool) -> CGFloat {
    guard hasVerticalBar || hasFold else { return 0 }
    return max(0, max(leading, trailing) - safeAreaTop)
  }
}

/// Two pages either side of a fold, in the coordinates of the view that read the fold: x ranges
/// for a vertical fold, y ranges for a horizontal one. Each page keeps clear of the fold region.
nonisolated struct IOSFoldPages: Equatable, Sendable {
  var axis: IOSFold.Axis
  var first: ClosedRange<CGFloat>
  var second: ClosedRange<CGFloat>

  /// Each page needs room for a phone-sized column. A fold along the view's edge, as in Split
  /// View, divides nothing.
  static let minimumLength: CGFloat = 240

  init?(fold: IOSFold?, size: CGSize, insets: IOSContentInsets) {
    guard let fold else { return nil }
    let first: ClosedRange<CGFloat>
    let second: ClosedRange<CGFloat>
    switch fold.axis {
    case .vertical:
      guard insets.leading <= fold.frame.minX, fold.frame.maxX <= size.width - insets.trailing
      else { return nil }
      first = insets.leading...fold.frame.minX
      second = fold.frame.maxX...(size.width - insets.trailing)
    case .horizontal:
      guard 0 <= fold.frame.minY, fold.frame.maxY <= size.height else { return nil }
      first = 0...fold.frame.minY
      second = fold.frame.maxY...size.height
    }
    guard first.length >= Self.minimumLength, second.length >= Self.minimumLength else {
      return nil
    }
    self.axis = fold.axis
    self.first = first
    self.second = second
  }
}

/// How Today arranges the next prayer and the day's prayers for the space it has.
nonisolated enum IOSTodayLayout: Equatable, Sendable {
  /// One column: the next prayer above the day's prayers.
  case stacked
  /// The tablet's two columns across a wide view.
  case wide
  /// The next prayer beside the day's prayers, when iPhone Duo stands closed on its side.
  case sideBySide
  /// A fold divides the view: the next prayer on the first page, the day on the second.
  case pages(IOSFoldPages)

  static func resolve(
    size: CGSize, pages: IOSFoldPages?, isCompactHeight: Bool, hasVerticalBar: Bool,
    isAccessibilitySize: Bool
  ) -> IOSTodayLayout {
    if let pages { return .pages(pages) }
    if isAccessibilitySize { return .stacked }
    if size.width >= 740 { return .wide }
    if isCompactHeight && hasVerticalBar && size.width >= 520 { return .sideBySide }
    return .stacked
  }
}

/// The week table's column widths that put the fold between the third prayer, Dhuhr, and the
/// fourth, Asr: the day and the morning's times on the first page, the rest on the second.
nonisolated struct IOSWeekColumns: Equatable, Sendable {
  var day: CGFloat
  var prayer: CGFloat
  /// Empty space where the fold crosses the table.
  var gap: CGFloat

  static let minimumPrayer: CGFloat = 56
  /// The day column's width, or more when the first page has room to spare.
  static let preferredDay: CGFloat = 64

  /// `rowStart` and `rowEnd` bound a row's content, in the coordinates the fold was read in.
  /// Either page can be the narrower one: in right-to-left layouts the first page lies beside
  /// iPhone Duo's bar, without a margin.
  init?(rowStart: CGFloat, rowEnd: CGFloat, fold: IOSFold?) {
    guard let fold, fold.axis == .vertical else { return nil }
    let firstPage = fold.frame.minX - rowStart
    let secondPage = rowEnd - fold.frame.maxX
    let prayer = min(secondPage, firstPage - Self.preferredDay) / 3
    let day = firstPage - 3 * prayer
    guard prayer >= Self.minimumPrayer else { return nil }
    self.day = day
    self.prayer = prayer
    self.gap = fold.frame.width
  }
}

extension ClosedRange where Bound == CGFloat {
  nonisolated var length: CGFloat { upperBound - lowerBound }
}
