import XCTest

/// Journeys through the running Apple TV app with the Siri Remote: Today and its rows, the
/// room display, the adhan at prayer time, the week, Settings, About and persistence, Arabic
/// and Larger Text.
nonisolated final class TVCoreJourneys: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }

  @MainActor
  func testTodayLeadsWithTheNextPrayer() {
    let journey = TVJourneyApp()
    journey.launch()
    let app = journey.app
    let hero = require("hero", in: app)
    XCTAssertTrue(hero.label.contains("Next prayer, Asr"), hero.label)
    XCTAssertTrue(hero.label.contains("in 2 hours, 16 minutes"), hero.label)
    XCTAssertTrue(hero.label.contains("Adhan at"), hero.label)
    for kind in ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"] {
      require("today.row.\(kind)", in: app)
    }
    XCTAssertTrue(require("today.source", in: app).label.contains("Umm al-Qura"))
    // Launch focus is in the tab bar, and one Down lands on the next prayer.
    let asr = element("today.row.asr", in: app)
    moveFocus(.down, to: asr, in: app, maximumPresses: 1)
    XCTAssertTrue(asr.label.contains("next prayer"), asr.label)
    capture("today-en", in: app)
  }

  @MainActor
  func testAPrayerRowOpensItsSoundAndTheChoiceIsKept() {
    let journey = TVJourneyApp()
    journey.launch()
    let app = journey.app
    let asr = element("today.row.asr", in: app)
    moveFocus(.down, to: asr, in: app, maximumPresses: 3)
    remote.press(.select)
    let tone = require("prayer.sound.softTone", in: app)
    moveFocus(.down, to: tone, in: app, maximumPresses: 4)
    remote.press(.select)
    XCTAssertTrue(waitUntil { tone.isSelected }, "Soft tone wasn't selected")
    capture("prayer-sound", in: app)
    journey.relaunch()
    let hero = require("hero", in: app)
    XCTAssertTrue(hero.label.contains("Tone at"), hero.label)
  }

  @MainActor
  func testKeepOnScreenShowsTheRoomDisplayUntilBack() {
    let journey = TVJourneyApp()
    journey.launch()
    let app = journey.app
    let keep = element("today.keepOnScreen", in: app)
    moveFocus(.down, to: element("today.row.asr", in: app), in: app, maximumPresses: 3)
    moveFocus(.left, to: keep, in: app, maximumPresses: 3)
    remote.press(.select)
    let room = require("room", in: app)
    XCTAssertTrue(waitUntil { (room.value as? String) == "The screen stays on" }, "\(room)")
    for kind in ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"] {
      require("room.cell.\(kind)", in: app)
    }
    capture("room-display", in: app)
    // The board itself takes focus, without showing it, so wait out the presentation.
    settle()
    remote.press(.menu)
    XCTAssertTrue(waitUntil { !room.exists }, "Back didn't leave the room display")
    require("hero", in: app)
  }

  @MainActor
  func testTheRoomDisplayKeepsTheScreenOnAfterHome() {
    var journey = TVJourneyApp()
    journey.route = "room"
    journey.launch()
    let app = journey.app
    let room = require("room", in: app)
    let on = "The screen stays on"
    XCTAssertTrue(waitUntil { (room.value as? String) == on }, "\(room)")
    remote.press(.home)
    XCTAssertTrue(waitUntil { app.state != .runningForeground }, "Home didn't leave Salah")
    // Coming back to the room display keeps the screen on again.
    app.activate()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "Salah didn't come back")
    settle()
    require("room", in: app)
    XCTAssertTrue(
      waitUntil(timeout: 5) { (room.value as? String) == on },
      "The screen no longer stays on: \(room)")
  }

  @MainActor
  func testTheAdhanPlaysAtPrayerTimeAndStopStopsIt() {
    var journey = TVJourneyApp()
    journey.now = "2026-06-02T18:59:55+03:00"
    journey.frozen = false
    journey.launch()
    let app = journey.app
    let adhan = require("adhan", in: app, timeout: 20)
    XCTAssertTrue(app.staticTexts["Maghrib"].exists, app.debugDescription)
    let stop = element("adhan.stop", in: app)
    XCTAssertTrue(waitUntil { self.hasFocus(stop, in: app) }, "Stop doesn't have focus")
    capture("adhan", in: app)
    remote.press(.select)
    XCTAssertTrue(waitUntil { !adhan.exists }, "Stop didn't end the adhan")
    require("hero", in: app)
  }

  @MainActor
  func testTheAdhanPlaysOverAPrayersSoundPage() {
    var journey = TVJourneyApp()
    journey.now = "2026-06-02T18:59:35+03:00"
    journey.frozen = false
    journey.launch()
    let app = journey.app
    // One Down from the tab bar lands on the next prayer, Maghrib, which opens its sound page.
    moveFocus(.down, to: element("today.row.maghrib", in: app), in: app, maximumPresses: 1)
    remote.press(.select)
    let page = require("prayer.sound.adhan", in: app)
    // Opening the page plays nothing. At 19:00 the adhan covers it, and the page that
    // disappears under it mustn't stop it.
    let adhan = require("adhan", in: app, timeout: 30)
    _ = waitUntil(timeout: 5) { !adhan.exists }
    XCTAssertTrue(adhan.exists, "The adhan stopped over the sound page")
    let stop = element("adhan.stop", in: app)
    XCTAssertTrue(waitUntil { self.hasFocus(stop, in: app) }, "Stop doesn't have focus")
    capture("adhan-over-sound-page", in: app)
    remote.press(.select)
    XCTAssertTrue(waitUntil { !adhan.exists }, "Stop didn't end the adhan")
    XCTAssertTrue(page.waitForExistence(timeout: 10), "The sound page didn't come back")
  }

  @MainActor
  func testPlayPauseStopsTheAdhanOverTheRoomDisplay() {
    var journey = TVJourneyApp()
    // Far enough before Maghrib that the room display is up before the adhan.
    journey.now = "2026-06-02T18:59:35+03:00"
    journey.frozen = false
    journey.route = "room"
    journey.launch()
    let app = journey.app
    require("room", in: app)
    let adhan = require("adhan", in: app, timeout: 40)
    // A person presses once the adhan is on screen, with Stop focused.
    let stop = element("adhan.stop", in: app)
    XCTAssertTrue(waitUntil { self.hasFocus(stop, in: app) }, "Stop doesn't have focus")
    remote.press(.playPause)
    XCTAssertTrue(waitUntil { !adhan.exists }, "Play/Pause didn't end the adhan")
    // The adhan interrupted the room display, which comes back.
    require("room", in: app)
  }

  @MainActor
  func testBackStopsTheAdhanOverTheRoomDisplay() {
    var journey = TVJourneyApp()
    journey.now = "2026-06-02T18:59:35+03:00"
    journey.frozen = false
    journey.route = "room"
    journey.launch()
    let app = journey.app
    require("room", in: app)
    let adhan = require("adhan", in: app, timeout: 40)
    let stop = element("adhan.stop", in: app)
    XCTAssertTrue(waitUntil { self.hasFocus(stop, in: app) }, "Stop doesn't have focus")
    remote.press(.menu)
    XCTAssertTrue(waitUntil { !adhan.exists }, "Back didn't end the adhan")
    require("room", in: app)
  }

  @MainActor
  func testTheWeekShowsSevenDaysAndTurnsAtItsEnds() {
    var journey = TVJourneyApp()
    journey.fixture = "london"
    journey.now = "2026-10-16T10:05:00+01:00"
    journey.route = "week"
    journey.launch()
    let app = journey.app
    for day in 12...18 { require("week.day.2026-10-\(day)", in: app) }
    // Launch focus is in the tab bar, and one Down lands on today.
    let friday = element("week.day.2026-10-16", in: app)
    moveFocus(.down, to: friday, in: app, maximumPresses: 1)
    capture("week", in: app)
    // Reaching Sunday keeps the week; moving past it shows the next one from its Monday.
    let sunday = element("week.day.2026-10-18", in: app)
    moveFocus(.right, to: sunday, in: app, maximumPresses: 3)
    settle()
    XCTAssertTrue(hasFocus(sunday, in: app), "The week turned on reaching Sunday")
    remote.press(.right)
    let nextMonday = require("week.day.2026-10-19", in: app)
    XCTAssertTrue(
      waitUntil { self.hasFocus(nextMonday, in: app) }, "The next week didn't take focus")
    XCTAssertFalse(sunday.exists)
    // Moving back past Monday shows the previous week from its Sunday.
    remote.press(.left)
    XCTAssertTrue(
      waitUntil { self.hasFocus(sunday, in: app) }, "The previous week didn't take focus")
    // After browsing to another week, the tab comes back to this one, on today.
    remote.press(.right)
    XCTAssertTrue(
      waitUntil { self.hasFocus(nextMonday, in: app) }, "The next week didn't take focus")
    openTab("Today", in: app)
    openTab("Week", in: app)
    moveFocus(.down, to: friday, in: app, maximumPresses: 1)
    XCTAssertFalse(nextMonday.exists)
  }

  @MainActor
  func testTheWeekStaysWhereItWasAfterTheAdhan() {
    var journey = TVJourneyApp()
    // A minute before Maghrib leaves time to browse on a slow runner.
    journey.now = "2026-06-02T18:59:00+03:00"
    journey.frozen = false
    journey.route = "week"
    journey.launch()
    let app = journey.app
    moveFocus(.down, to: element("week.day.2026-06-02", in: app), in: app, maximumPresses: 1)
    moveFocus(.right, to: element("week.day.2026-06-07", in: app), in: app, maximumPresses: 6)
    settle()
    remote.press(.right)
    let nextMonday = require("week.day.2026-06-08", in: app)
    XCTAssertTrue(
      waitUntil { self.hasFocus(nextMonday, in: app) }, "The next week didn't take focus")
    // The adhan covers the week at Maghrib; after it, the week is where it was.
    let adhan = require("adhan", in: app, timeout: 90)
    let stop = element("adhan.stop", in: app)
    XCTAssertTrue(waitUntil { self.hasFocus(stop, in: app) }, "Stop doesn't have focus")
    remote.press(.select)
    XCTAssertTrue(waitUntil { !adhan.exists }, "Stop didn't end the adhan")
    settle()
    XCTAssertTrue(nextMonday.exists, "The week went back to the current one")
  }

  @MainActor
  func testASettingIsKeptAcrossRelaunch() {
    var journey = TVJourneyApp()
    journey.route = "settings"
    journey.launch()
    let app = journey.app
    let madhab = element("settings.madhab", in: app)
    moveFocus(.down, to: madhab, in: app, maximumPresses: 5)
    remote.press(.select)
    let hanafi = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hanafi"))
      .firstMatch
    moveFocus(.down, to: hanafi, in: app, maximumPresses: 3)
    remote.press(.select)
    XCTAssertTrue(waitUntil { hanafi.isSelected }, "Hanafi wasn't selected")
    remote.press(.menu)
    XCTAssertTrue(waitUntil { madhab.label.contains("Hanafi") }, madhab.label)
    journey.relaunch()
    require("settings.madhab", in: app)
    XCTAssertTrue(element("settings.madhab", in: app).label.contains("Hanafi"))
  }

  @MainActor
  func testAboutScrollsToTheSourceCode() {
    var journey = TVJourneyApp()
    journey.route = "settings"
    journey.launch()
    let app = journey.app
    // About is the last row, so the list shows it only once focus comes near.
    let about = element("settings.about", in: app)
    XCTAssertTrue(press(.down, until: { self.hasFocus(about, in: app) }), "About wasn't reached")
    remote.press(.select)
    let source = require("about.source", in: app)
    settle()
    // tvOS scrolls by moving focus, so moving down has to reach the last section, past the
    // audio credits.
    let reached = press(
      .down,
      until: {
        self.hasFocus(source, in: app) || app.frame.contains(source.frame)
      })
    XCTAssertTrue(reached, "Moving down didn't reach the source code.\n\(app.debugDescription)")
    capture("about-source", in: app)
  }

  @MainActor
  func testArabicIsRightToLeftWithArabicDigits() {
    var journey = TVJourneyApp()
    journey.language = "ar"
    journey.launch()
    let app = journey.app
    let hero = require("hero", in: app)
    XCTAssertTrue(hero.label.contains("العصر"), hero.label)
    XCTAssertTrue(hero.label.contains("٣:٣٥"), hero.label)
    // The hero leads on the right, the rows on the left.
    let row = require("today.row.asr", in: app)
    XCTAssertGreaterThan(hero.frame.minX, row.frame.maxX)
    capture("today-ar", in: app)
  }

  @MainActor
  func testLargerTextStacksTodayInOneColumn() {
    var journey = TVJourneyApp()
    journey.extraArguments = [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
    ]
    journey.launch()
    let app = journey.app
    let hero = require("hero", in: app)
    let row = require("today.row.fajr", in: app)
    // One column: the rows follow the hero instead of standing beside it.
    XCTAssertGreaterThan(row.frame.minY, hero.frame.maxY)
    XCTAssertLessThan(row.frame.minX, hero.frame.maxX)
    capture("today-larger-text", in: app)
  }

  @MainActor
  func testLargerTextKeepsTheHeroAndTheSourceInReach() {
    var journey = TVJourneyApp()
    journey.extraArguments = [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
    ]
    journey.launch()
    let app = journey.app
    let hero = require("hero", in: app)
    let source = require("today.source", in: app)
    // tvOS scrolls by moving focus. Down reaches the line about the method at the end, and
    // Up brings the next prayer's countdown back before the tab bar.
    moveFocus(.down, to: element("today.row.asr", in: app), in: app, maximumPresses: 1)
    XCTAssertTrue(
      press(.down, until: { app.frame.contains(source.frame) }, maximumPresses: 6),
      "Moving down didn't bring the source line on screen")
    XCTAssertTrue(
      press(.up, until: { app.frame.contains(hero.frame) }, maximumPresses: 10),
      "Moving up didn't bring the hero back on screen")
  }
}
