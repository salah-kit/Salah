import CoreGraphics
import Testing

/// The values below are what iOS 27.1 reports on iPhone Duo: the inner display's content view
/// is 867 × 553 points in landscape beside an 84-point side bar, and 669 × 786 in portrait. The
/// fold's division region is 40 points, the hinge line plus 20 points either side, flat or folded.
@Suite("iPhone Duo fold layout")
struct FoldLayoutTests {
  static let landscape = CGSize(width: 867, height: 553)
  static let portrait = CGSize(width: 669, height: 786)
  static let bookFold = IOSFold(
    frame: CGRect(x: 455.5, y: -82, width: 40, height: 669), isActive: true)
  static let flatFold = IOSFold(
    frame: CGRect(x: 455.5, y: -82, width: 40, height: 669), isActive: false)
  static let laptopFold = IOSFold(
    frame: CGRect(x: 0, y: 373.5, width: 669, height: 40), isActive: true)
  static let besideBar = IOSContentInsets(leading: 20, trailing: 0)

  @Test func aTallFrameIsAFoldBetweenSideBySidePages() {
    #expect(Self.bookFold.axis == .vertical)
    #expect(Self.laptopFold.axis == .horizontal)
  }

  @Test func landscapePagesMeetTheFoldOnEitherSide() throws {
    let pages = try #require(
      IOSFoldPages(fold: Self.bookFold, size: Self.landscape, insets: Self.besideBar))
    #expect(pages.axis == .vertical)
    #expect(pages.first == 20...455.5)
    #expect(pages.second == 495.5...867)
  }

  @Test func foldingMovesNothingBecauseTheFlatFoldReservesTheSameRegion() {
    let flat = IOSFoldPages(fold: Self.flatFold, size: Self.landscape, insets: Self.besideBar)
    let folded = IOSFoldPages(fold: Self.bookFold, size: Self.landscape, insets: Self.besideBar)
    #expect(flat != nil)
    #expect(flat == folded)
  }

  @Test func portraitPagesStackAboveAndBelowTheFold() throws {
    let pages = try #require(
      IOSFoldPages(
        fold: Self.laptopFold, size: Self.portrait,
        insets: IOSContentInsets(leading: 20, trailing: 20)))
    #expect(pages.axis == .horizontal)
    #expect(pages.first == 0...373.5)
    #expect(pages.second == 413.5...786)
  }

  @Test func aFoldAtTheViewsEdgeSplitsNothing() {
    // Salah in one half of Split View: the hinge runs along the edge between the two apps.
    let half = CGSize(width: 400, height: 553)
    let edge = IOSFold(frame: CGRect(x: 380, y: -82, width: 40, height: 669), isActive: false)
    #expect(IOSFoldPages(fold: edge, size: half, insets: Self.besideBar) == nil)
    #expect(IOSFoldPages(fold: nil, size: Self.landscape, insets: Self.besideBar) == nil)
  }

  @Test func rightToLeftPagesUseTheMirroredFoldFromTheLeadingEdge() throws {
    // In Arabic the bar stays on the physical right, which is the leading edge, and iOS
    // mirrors the region: the first page, read first, is the right-hand page.
    let mirrored = IOSFold(frame: CGRect(x: 371.5, y: -82, width: 40, height: 669), isActive: false)
    let pages = try #require(
      IOSFoldPages(
        fold: mirrored, size: Self.landscape, insets: IOSContentInsets(leading: 0, trailing: 20)))
    #expect(pages.first == 0...371.5)
    #expect(pages.second == 411.5...847)
  }

  @Test func insetsKeepTheDesignMarginWithoutABarOrAFold() {
    let iPhone = IOSContentInsets.resolve(
      container: IOSContentInsets(leading: 16, trailing: 16), hasVerticalBar: false,
      hasFold: false)
    #expect(iPhone == .standard)
    let older = IOSContentInsets.resolve(container: nil, hasVerticalBar: false, hasFold: false)
    #expect(older == .standard)
  }

  @Test func insetsFollowTheSystemBesideAVerticalBarOrAcrossAFold() {
    let outer = IOSContentInsets.resolve(
      container: Self.besideBar, hasVerticalBar: true, hasFold: false)
    #expect(outer == Self.besideBar)
    let innerPortrait = IOSContentInsets.resolve(
      container: IOSContentInsets(leading: 20, trailing: 20), hasVerticalBar: false,
      hasFold: true)
    #expect(innerPortrait == IOSContentInsets(leading: 20, trailing: 20))
  }

  @Test func contentKeepsAMarginFromTheTopEdgeWhenTheStatusBarMovesToTheSide() {
    // With the bars on the side, a screen without a navigation bar starts at the display's edge.
    #expect(
      Self.besideBar.topMargin(safeAreaTop: 0, hasVerticalBar: true, hasFold: false) == 20)
    #expect(
      IOSContentInsets(leading: 0, trailing: 20).topMargin(
        safeAreaTop: 0, hasVerticalBar: true, hasFold: true) == 20)
    // A status bar or navigation bar above already keeps it clear.
    #expect(
      Self.besideBar.topMargin(safeAreaTop: 82, hasVerticalBar: true, hasFold: false) == 0)
    // iPhone and iPad keep their layouts, including a phone in landscape without a status bar.
    #expect(
      IOSContentInsets.standard.topMargin(safeAreaTop: 0, hasVerticalBar: false, hasFold: false)
        == 0)
  }

  @Test func todayChoosesPagesWheneverAFoldDividesTheView() throws {
    let pages = try #require(
      IOSFoldPages(fold: Self.flatFold, size: Self.landscape, insets: Self.besideBar))
    for accessibility in [false, true] {
      #expect(
        IOSTodayLayout.resolve(
          size: Self.landscape, pages: pages, isCompactHeight: false, hasVerticalBar: true,
          isAccessibilitySize: accessibility) == .pages(pages))
    }
  }

  @Test func todayKeepsItsPhoneAndTabletLayoutsWithoutAFold() {
    func layout(
      _ width: CGFloat, compactHeight: Bool = false, verticalBar: Bool = false,
      accessibility: Bool = false
    ) -> IOSTodayLayout {
      IOSTodayLayout.resolve(
        size: CGSize(width: width, height: 500), pages: nil, isCompactHeight: compactHeight,
        hasVerticalBar: verticalBar, isAccessibilitySize: accessibility)
    }
    #expect(layout(382, verticalBar: true) == .stacked)  // iPhone Duo closed, beside its side bar
    #expect(layout(1_100) == .wide)  // iPad landscape
    #expect(layout(1_100, accessibility: true) == .stacked)
    #expect(layout(750, compactHeight: true) == .wide)  // a large iPhone in landscape
    #expect(layout(667, compactHeight: true) == .stacked)  // a small iPhone in landscape
  }

  @Test func todayStandsTheNextPrayerBesideTheListInTheTent() {
    // iPhone Duo closed and turned on its side, standing like a tent.
    let tent = IOSTodayLayout.resolve(
      size: CGSize(width: 594, height: 350), pages: nil, isCompactHeight: true,
      hasVerticalBar: true, isAccessibilitySize: false)
    #expect(tent == .sideBySide)
    let tentLargeText = IOSTodayLayout.resolve(
      size: CGSize(width: 594, height: 350), pages: nil, isCompactHeight: true,
      hasVerticalBar: true, isAccessibilitySize: true)
    #expect(tentLargeText == .stacked)
  }

  @Test func weekColumnsPutTheFoldBetweenDhuhrAndAsr() throws {
    // The card starts at the 20-point inset; card and row padding add 12 points each.
    let columns = try #require(
      IOSWeekColumns(rowStart: 44, rowEnd: 843, fold: Self.flatFold))
    #expect(abs(columns.prayer - 115.833) < 0.01)
    #expect(abs(columns.day - 64) < 0.01)
    #expect(columns.gap == 40)
    // Day, Fajr, Sunrise and Dhuhr end where the fold begins; Asr starts where it ends.
    #expect(abs(44 + columns.day + 3 * columns.prayer - 455.5) < 0.01)
    #expect(abs(44 + columns.day + 3 * columns.prayer + columns.gap - 495.5) < 0.01)
  }

  @Test func weekColumnsFitTheNarrowerFirstPageRightToLeft() throws {
    // In Arabic the first page lies beside the bar, with no margin, so it's the narrower one:
    // the mirrored fold starts 371.5 points from the leading edge and the rows run to 823.
    let mirrored = IOSFold(
      frame: CGRect(x: 371.5, y: -82, width: 40, height: 669), isActive: false)
    let columns = try #require(IOSWeekColumns(rowStart: 24, rowEnd: 823, fold: mirrored))
    #expect(abs(24 + columns.day + 3 * columns.prayer - 371.5) < 0.01)
    #expect(24 + columns.day + 3 * columns.prayer + columns.gap + 3 * columns.prayer <= 823)
    #expect(abs(columns.day - IOSWeekColumns.preferredDay) < 0.01)
    #expect(columns.prayer >= IOSWeekColumns.minimumPrayer)
  }

  @Test func weekColumnsNeedRoomForTheDayAndEveryTime() {
    #expect(IOSWeekColumns(rowStart: 44, rowEnd: 843, fold: nil) == nil)
    #expect(IOSWeekColumns(rowStart: 44, rowEnd: 843, fold: Self.laptopFold) == nil)
    // A fold so close to the leading edge would leave the morning's times too narrow.
    let early = IOSFold(frame: CGRect(x: 200, y: 0, width: 40, height: 600), isActive: false)
    #expect(IOSWeekColumns(rowStart: 44, rowEnd: 843, fold: early) == nil)
  }
}
