import XCTest

/// Run on iPhone Duo after choosing a pose in Device Hub, since XCTest can't fold or turn it.
/// Each test skips unless the simulator is in its pose; CONTRIBUTING lists the steps. The
/// layouts don't change when the open display folds, so flat and folded run the same test.
/// XCTest's screenshots show only the outer display, so the open poses attach none.
nonisolated final class IOSDuoPoseJourneys: XCTestCase {
  private enum Pose: String { case tent, openLandscape, openPortrait }

  override func setUpWithError() throws { continueAfterFailure = false }

  /// Closed and on its side: the next prayer stands beside the day's prayers.
  @MainActor
  func testTentStandsTheNextPrayerBesideTheDaysPrayers() throws {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }
    let window = try window(of: app, in: .tent)

    let hero = require("today.nextPrayer", in: app)
    let list = require("today.dayList", in: app)
    XCTAssertLessThanOrEqual(hero.frame.maxX, list.frame.minX)
    XCTAssertEqual(hero.frame.minY, list.frame.minY, accuracy: 1)
    XCTAssertTrue(window.frame.contains(hero.frame), "The next prayer is in view without scrolling")
    capture("Duo-English-Tent-Today", in: app)
  }

  /// Open on its side, flat or folded like a book: each screen's pages meet at the fold.
  @MainActor
  func testOpenLandscapePagesMeetAtTheFoldAndLeaveItEmpty() throws {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }
    let fold = try foldRegion(in: window(of: app, in: .openLandscape))

    try expectPagesMeetAtTheFold(fold, of: app, rightToLeft: false)
  }

  /// In Arabic the pages read from the right, so the first page is the one beside the bar.
  @MainActor
  func testOpenLandscapePagesReadFromTheRightInArabic() throws {
    let journey = IOSJourneyApp()
    journey.launch()
    let app = journey.app
    defer { app.terminate() }
    let fold = try foldRegion(in: window(of: app, in: .openLandscape))

    chooseArabic(in: app)
    XCTAssertTrue(
      require("today.name", in: app).label.unicodeScalars.contains {
        (0x0600...0x06FF).contains(Int($0.value))
      }, "Today is in Arabic")
    try expectPagesMeetAtTheFold(fold, of: app, rightToLeft: true)
  }

  /// Without a location, Today's and Times' recovery keeps to the first page and Qibla's to the
  /// second, beside its dial, in either reading direction.
  @MainActor
  func testOpenLandscapeLocationRecoveryLeavesTheFoldEmpty() throws {
    let journey = IOSJourneyApp(fixture: false)
    journey.app.resetAuthorizationStatus(for: .location)
    journey.launch()
    let app = journey.app
    defer { app.terminate() }
    let fold = try foldRegion(in: window(of: app, in: .openLandscape))

    for rightToLeft in [false, true] {
      if rightToLeft { chooseArabic(in: app) }
      for (tab, recovery, onFirstPage) in [
        ("tab.today", "today.chooseCity", true), ("tab.times", "times.chooseCity", true),
        ("tab.qibla", "qibla.chooseCity", false),
      ] {
        tap(tab, in: app)
        expect(recovery, in: app, onFirstPage: onFirstPage, of: fold, rightToLeft: rightToLeft)
        try expectNothing(in: fold, of: app, on: tab)
      }
    }
  }

  /// At accessibility text sizes each screen still leaves the fold empty, and Times keeps one
  /// column on the first page, in either reading direction.
  @MainActor
  func testOpenLandscapeLargeTextLeavesTheFoldEmpty() throws {
    let largeText = [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    var journey = IOSJourneyApp(extraArguments: largeText)
    journey.launch()
    let app = journey.app
    defer { app.terminate() }
    let fold = try foldRegion(in: window(of: app, in: .openLandscape))

    try expectLargeTextLeavesTheFoldEmpty(fold, of: app, rightToLeft: false)
    // Arabic is chosen at the default size, where Settings shows its row, and the choice persists.
    journey.extraArguments = []
    journey.relaunch()
    chooseArabic(in: app)
    journey.extraArguments = largeText
    journey.relaunch()
    try expectLargeTextLeavesTheFoldEmpty(fold, of: app, rightToLeft: true)
  }

  /// Open upright, flat or folded like a laptop: Today's and Qibla's pages stack at the fold,
  /// and a playing sound's Stop starts Today's lower page.
  @MainActor
  func testOpenPortraitPagesStackAtTheFoldWithStopOnTheLowerPage() throws {
    // At 8 PM the day's list scrolls to Isha, its last prayer.
    let journey = IOSJourneyApp(now: "2026-06-02T20:00:00+03:00")
    journey.launch()
    let app = journey.app
    defer { app.terminate() }
    let fold = try foldRegion(in: window(of: app, in: .openPortrait))

    expect("today.nextPrayer", in: app, onFirstPage: true, of: fold)
    let isha = require("prayer.row.isha", in: app)
    XCTAssertTrue(isha.isHittable, "The next prayer's row is in view")
    XCTAssertGreaterThanOrEqual(isha.frame.minY, fold.maxY - 1)
    try expectNothing(in: fold, of: app, on: "tab.today")

    isha.press(forDuration: 1)
    let play = app.buttons["Play prayer sound"].firstMatch
    XCTAssertTrue(play.waitForExistence(timeout: 5))
    play.tap()
    let card = require("today.nowPlaying", in: app)
    let stop = require("today.stopAudio", in: app)
    // The card leads the lower page, whose content starts 8 points below the fold.
    XCTAssertTrue(
      waitUntil {
        (fold.maxY - 1...fold.maxY + 9).contains(card.frame.minY) && stop.isHittable
      }, "What's playing, with Stop, starts the lower page: \(card.frame)")
    stop.tap()
    XCTAssertTrue(waitUntil { !card.exists })

    tap("tab.qibla", in: app)
    expect("qibla.heading", in: app, onFirstPage: true, of: fold)
    expect("qibla.facts", in: app, onFirstPage: false, of: fold)
    try expectNothing(in: fold, of: app, on: "tab.qibla")
  }

  /// Upright and without a location, Today's recovery keeps to the upper page and Qibla's to
  /// the lower one, below its dial.
  @MainActor
  func testOpenPortraitLocationRecoveryLeavesTheFoldEmpty() throws {
    let journey = IOSJourneyApp(fixture: false)
    journey.app.resetAuthorizationStatus(for: .location)
    journey.launch()
    let app = journey.app
    defer { app.terminate() }
    let fold = try foldRegion(in: window(of: app, in: .openPortrait))

    for (tab, recovery, onFirstPage) in [
      ("tab.today", "today.chooseCity", true), ("tab.qibla", "qibla.chooseCity", false),
    ] {
      tap(tab, in: app)
      expect(recovery, in: app, onFirstPage: onFirstPage, of: fold)
      try expectNothing(in: fold, of: app, on: tab)
    }
  }

  /// Each screen's first and second pages lie either side of the fold, in reading order, and
  /// leave it empty.
  @MainActor
  private func expectPagesMeetAtTheFold(
    _ fold: CGRect, of app: XCUIApplication, rightToLeft: Bool
  ) throws {
    let screens: [(steps: [String], first: String, second: String)] = [
      (["tab.today"], "today.nextPrayer", "today.dayList"),
      (["tab.times"], "times.next", "times.mode"),
      (["tab.qibla"], "qibla.heading", "qibla.facts"),
      (["tab.settings", "settings.method"], "settings.method", "method.automatic"),
    ]
    for screen in screens {
      for step in screen.steps { tap(step, in: app) }
      expect(screen.first, in: app, onFirstPage: true, of: fold, rightToLeft: rightToLeft)
      expect(screen.second, in: app, onFirstPage: false, of: fold, rightToLeft: rightToLeft)
      try expectNothing(in: fold, of: app, on: screen.steps[0])
    }
    tap("tab.times", in: app)
    tap("times.week", in: app)
    require("times.weekTable", in: app)
    try expectNothing(in: fold, of: app, on: "times.week")
  }

  @MainActor
  private func expectLargeTextLeavesTheFoldEmpty(
    _ fold: CGRect, of app: XCUIApplication, rightToLeft: Bool
  ) throws {
    for tab in ["tab.today", "tab.qibla", "tab.settings"] {
      tap(tab, in: app)
      try expectNothing(in: fold, of: app, on: tab)
    }
    tap("tab.times", in: app)
    tap("times.day", in: app)
    expect("times.dayList", in: app, onFirstPage: true, of: fold, rightToLeft: rightToLeft)
    try expectNothing(in: fold, of: app, on: "times.day")
    tap("times.week", in: app)
    expect("times.weekTable", in: app, onFirstPage: true, of: fold, rightToLeft: rightToLeft)
    try expectNothing(in: fold, of: app, on: "times.week")
  }

  /// Chooses Arabic in Settings, then returns to Today.
  @MainActor
  private func chooseArabic(in app: XCUIApplication) {
    tap("tab.settings", in: app)
    tap("settings.language", in: app)
    tap("language.arabic", in: app)
    tap("tab.today", in: app)
    XCTAssertTrue(app.buttons["اليوم"].waitForExistence(timeout: 5), "The tabs are in Arabic")
  }

  /// The window shows the pose; Device Hub chooses it.
  @MainActor
  private func window(of app: XCUIApplication, in pose: Pose) throws -> XCUIElement {
    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 15))
    let size = window.frame.size
    let current: Pose? =
      size.width > 900
      ? .openLandscape
      : size.height > 900 ? .openPortrait : size.width > size.height ? .tent : nil
    try XCTSkipUnless(current == pose, "Choose the \(pose) pose in Device Hub for this journey")
    return window
  }

  /// The fold's region in the open display's window: 40 points across its middle, running top
  /// to bottom on its side and across when upright.
  @MainActor
  private func foldRegion(in window: XCUIElement) -> CGRect {
    let frame = window.frame
    return frame.width > frame.height
      ? CGRect(x: frame.midX - 20, y: frame.minY, width: 40, height: frame.height)
      : CGRect(x: frame.minX, y: frame.midY - 20, width: frame.width, height: 40)
  }

  /// An element keeps to one page. The first page lies left of a fold that runs top to bottom,
  /// or right of it in Arabic, and above a fold that runs across.
  @MainActor
  private func expect(
    _ identifier: String, in app: XCUIApplication, onFirstPage: Bool, of fold: CGRect,
    rightToLeft: Bool = false, file: StaticString = #filePath, line: UInt = #line
  ) {
    let frame = require(identifier, in: app, file: file, line: line).frame
    let message = "\(identifier) keeps to the \(onFirstPage ? "first" : "second") page: \(frame)"
    if fold.height > fold.width {
      if onFirstPage != rightToLeft {
        XCTAssertLessThanOrEqual(frame.maxX, fold.minX + 1, message, file: file, line: line)
      } else {
        XCTAssertGreaterThanOrEqual(frame.minX, fold.maxX - 1, message, file: file, line: line)
      }
    } else if onFirstPage {
      XCTAssertLessThanOrEqual(frame.maxY, fold.minY + 1, message, file: file, line: line)
    } else {
      XCTAssertGreaterThanOrEqual(frame.minY, fold.maxY - 1, message, file: file, line: line)
    }
  }

  /// Text and controls stay out of the fold where they show: a scrolling view clips what it
  /// holds. System bars, and the week's rows, whose cells leave the fold empty, may cross it.
  @MainActor
  private func expectNothing(
    in fold: CGRect, of app: XCUIApplication, on screen: String,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let bars: Set<XCUIElement.ElementType> = [.navigationBar, .tabBar, .toolbar, .statusBar]
    let scrollers: Set<XCUIElement.ElementType> = [.scrollView, .collectionView, .table]
    let content: Set<XCUIElement.ElementType> = [
      .button, .staticText, .image, .switch, .toggle, .slider, .segmentedControl, .textField,
      .searchField, .link, .cell, .stepper,
    ]
    var crossing: [String] = []
    func visit(_ element: any XCUIElementSnapshot, inBar: Bool, clip: CGRect) {
      let inBar = inBar || bars.contains(element.elementType)
      let clip = scrollers.contains(element.elementType) ? clip.intersection(element.frame) : clip
      let shown = element.frame.intersection(clip)
      if !inBar, element.children.isEmpty, content.contains(element.elementType),
        !element.identifier.hasPrefix("times.day."), shown.intersects(fold.insetBy(dx: 1, dy: 1))
      {
        crossing.append("\(element.identifier) '\(element.label)' \(shown)")
      }
      for child in element.children { visit(child, inBar: inBar, clip: clip) }
    }
    let snapshot = try app.snapshot()
    visit(snapshot, inBar: false, clip: snapshot.frame)
    XCTAssertEqual(crossing, [], "\(screen) puts content in the fold", file: file, line: line)
  }
}
