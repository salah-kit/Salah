import AppKit
import SalahCore
import XCTest

/// What VoiceOver says for the pop-ups and pickers each Settings pane shows when it opens,
/// the Appearance preview and the menu-bar dropdown, through the VoiceOver service of
/// macOS 27's XCTest (`XCUIDevice.voiceOverService`). They cover part of what #17 asks a
/// person to listen to.
///
/// Each test turns VoiceOver on and moves it as VO-Right Arrow, VO-Shift-Down Arrow and
/// VO-Shift-Up Arrow do; VO-Space, Escape, Return and the arrow keys reach VoiceOver as
/// key presses. VoiceOver speaks aloud while a test runs and reads whichever app is in
/// front, so leave the Mac alone, with Do Not Disturb on, until the tests end. A test keeps
/// only what VoiceOver says after its own moves in the window it reads, and, after a key
/// press, the exact words it waits for, while Salah is in front with that window open; it
/// fails at the first move after that stops holding. Speech VoiceOver makes for another app
/// right after a move, such as a notification it reads out, can still be kept (`Speech`).
/// A test turns VoiceOver on and off itself. They launch Salah as `Launch` does: Makkah with
/// Salah's default calculation, English, muted, every alert off but the ones a test turns
/// on, in a scratch preferences suite.
///
/// They skip before macOS 27, which the service needs, on a Mac that isn't in English, when
/// VoiceOver is already on, and when it doesn't turn on. The dropdown tests also skip when
/// the menu bar is full, as `SalahUITests` does (#14).
final class VoiceOverSpeechUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  static let needsMacOS27 = "XCTest's VoiceOver service needs macOS 27."

  // MARK: - Settings

  /// Settings → Location, with automatic location off: VoiceOver reads the time zone's row,
  /// then its pop-up as the zone, the name and the role. VO-Space opens the pop-up's menu
  /// of every zone, and Escape closes it on the same zone.
  ///
  /// VoiceOver names a Settings pop-up after its row's label, so it reads "Time zone" even
  /// without the pop-up's own name, which `SettingsAccessibilityUITests` checks.
  @MainActor
  func testTimeZonePopUpSaysTheZoneThenItsName() throws {
    guard #available(macOS 27.0, *) else { throw XCTSkip(Self.needsMacOS27) }
    let pane = try openPane("Location", heading: "Detection")
    let (app, speech) = (pane.app, pane.speech)
    try speech.next { $0 == "Time zone" }
    XCTAssertEqual(try speech.next(), "Riyadh Time zone pop up button", speech.log)

    app.typeKey(" ", modifierFlags: [.control, .option])
    try speech.waitFor { $0 == "menu (\(TimeZone.knownTimeZoneIdentifiers.count) items)" }
    let riyadh = app.menuItems["Riyadh"]
    XCTAssertTrue(riyadh.exists, speech.log)
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(Self.eventually { !riyadh.exists }, speech.log)
    XCTAssertEqual(pane.settings.popUpButtons["Time zone"].value as? String, "Riyadh")
    // VoiceOver stays on the pop-up, which reads the same zone.
    XCTAssertEqual(try speech.previous(), "Time zone", speech.log)
    XCTAssertEqual(try speech.next(), "Riyadh Time zone pop up button", speech.log)
  }

  /// Settings → General: VoiceOver reads each row's name, then its pop-up as the choice,
  /// the name and the role.
  @MainActor
  func testGeneralPopUpsSayTheirChoiceThenTheirName() throws {
    guard #available(macOS 27.0, *) else { throw XCTSkip(Self.needsMacOS27) }
    let speech = try openPane("General", heading: "Language").speech
    try speech.next { $0 == "Name style" }
    XCTAssertEqual(try speech.next(), "Full name Name style pop up button", speech.log)
    try speech.next { $0 == "Time style" }
    XCTAssertEqual(try speech.next(), "Countdown Time style pop up button", speech.log)
  }

  /// VoiceOver changes a pop-up's choice and changes it back, as #17 asks a person to try:
  /// VO-Space opens Settings → General's name style, the arrow keys move through its three
  /// choices, which VoiceOver reads, and Return chooses one.
  @MainActor
  func testVoiceOverChangesTheNameStyleAndBack() throws {
    guard #available(macOS 27.0, *) else { throw XCTSkip(Self.needsMacOS27) }
    let pane = try openPane("General", heading: "Language")
    let (app, speech) = (pane.app, pane.speech)
    try speech.next { $0 == "Full name Name style pop up button" }
    // The pane's first pop-up; it has no name of its own, as the row's label names it.
    let nameStyle = pane.settings.popUpButtons.element(boundBy: 0)
    XCTAssertEqual(nameStyle.value as? String, "Full name", speech.log)

    app.typeKey(" ", modifierFlags: [.control, .option])
    try speech.waitFor { $0 == "menu (3 items)" }
    app.typeKey(.downArrow, modifierFlags: [])
    try speech.waitFor { $0 == "✓ Full name" }
    app.typeKey(.downArrow, modifierFlags: [])
    try speech.waitFor { $0 == "Abbreviation" }
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(Self.eventually { nameStyle.value as? String == "Abbreviation" }, speech.log)

    app.typeKey(" ", modifierFlags: [.control, .option])
    try speech.waitFor { $0 == "menu (3 items)" }
    app.typeKey(.downArrow, modifierFlags: [])
    try speech.waitFor { $0 == "Full name" }
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(Self.eventually { nameStyle.value as? String == "Full name" }, speech.log)
  }

  /// Settings → Calculation: VoiceOver reads each pop-up as its choice, its name and its
  /// role, and says "dimmed" for the high-latitude rule while it's detected from the
  /// location.
  @MainActor
  func testCalculationPopUpsSayTheirChoiceThenTheirName() throws {
    guard #available(macOS 27.0, *) else { throw XCTSkip(Self.needsMacOS27) }
    let speech = try openPane(
      "Calculation", heading: "Method",
      arguments: Self.launch(["-salah.autoDetectHighLatitudeRule": "YES"])
    ).speech
    try speech.next { $0 == "Calculation method" }
    XCTAssertEqual(
      try speech.next(), "Umm Al-Qura, Makkah Calculation method pop up button", speech.log)
    try speech.next { $0 == "Asr calculation" }
    XCTAssertEqual(
      try speech.next(), "Shafi / Maliki / Hanbali Asr calculation pop up button", speech.log)
    try speech.next { $0 == "High latitude rule dimmed" }
    XCTAssertEqual(
      try speech.next(), "Middle of the night High latitude rule dimmed pop up button",
      speech.log)
  }

  /// Settings → Notifications, with Fajr's alert on: the prayer picker is a radio group
  /// named "Prayer" that says which prayer is selected, and the alert's sound pop-up reads
  /// as its choice, its name and its role.
  @MainActor
  func testNotificationsPickersSayTheirChoiceAndName() throws {
    guard #available(macOS 27.0, *) else { throw XCTSkip(Self.needsMacOS27) }
    let speech = try openPane(
      "Notifications", heading: "Global Alerts",
      arguments: Launch.arguments(alerts: [.fajr: ["alertEnabled": true]])
    ).speech
    try speech.next { $0 == "Prayer radio group" }
    XCTAssertEqual(
      try speech.enter(), "In Prayer radio group 6 items Fajr selected radio button, 1 of 6",
      speech.log)
    XCTAssertEqual(try speech.next(), "Sunrise radio button, 2 of 6", speech.log)
    try speech.leave()
    try speech.next { $0 == "Sound" }
    XCTAssertEqual(try speech.next(), "System Default Sound pop up button", speech.log)
  }

  /// Settings → Appearance: the preview is one group named "Preview", in which VoiceOver
  /// reads each of today's prayers by its name, then its time; the preview's size is a
  /// radio group that says which size is selected.
  @MainActor
  func testAppearancePreviewIsOneGroupNamedPreview() throws {
    guard #available(macOS 27.0, *) else { throw XCTSkip(Self.needsMacOS27) }
    let speech = try openPane("Appearance", heading: "Preview").speech
    XCTAssertEqual(try speech.next(), "Preview group", speech.log)
    let opening = try speech.enter()
    XCTAssertTrue(opening.hasPrefix("In Preview group "), speech.log)
    let items = [opening] + (try speech.rest())
    for (name, time) in Self.today(in: Self.english) {
      // A row reads "Fajr, 5:01 AM"; a passed or current one has its count-up or "Now"
      // between the two.
      XCTAssertTrue(
        items.contains { $0.hasPrefix("\(name), ") && $0.hasSuffix(", \(time)") },
        "\(name) at \(time)\n\(speech.log)")
    }
    try speech.leave()
    try speech.next { $0 == "Size radio group" }
    XCTAssertEqual(
      try speech.enter(), "In Size radio group 3 items Small radio button, 1 of 3", speech.log)
    XCTAssertEqual(try speech.next(), "Medium selected radio button, 2 of 3", speech.log)
  }

  // MARK: - Dropdown

  /// The dropdown, in English: VoiceOver reads each prayer's name, then its time, names the
  /// alert toggles by their prayer and state, and reads the countdown in words: "Isha ·
  /// 1 hour, 10 minutes remaining".
  @MainActor
  func testDropdownSaysThePrayersAndTheCountdownInEnglish() throws {
    guard #available(macOS 27.0, *) else { throw XCTSkip(Self.needsMacOS27) }
    try assertDropdownSpeech(in: Self.english)
  }

  /// The dropdown, in Arabic: the same, in Salah's Arabic, "العشاء · ساعة و١١ دقيقة
  /// متبقّية", with Salah's Arabic role names, such as "زر" for a button.
  @MainActor
  func testDropdownSaysThePrayersAndTheCountdownInArabic() throws {
    guard #available(macOS 27.0, *) else { throw XCTSkip(Self.needsMacOS27) }
    try assertDropdownSpeech(in: Self.arabic)
  }

  @available(macOS 27.0, *)
  @MainActor
  private func assertDropdownSpeech(in language: Language) throws {
    let app = XCUIApplication()
    app.launchArguments = Self.launch([
      "-salah.appLanguage": language.setting, "-AppleLanguages": "(\(language.code))",
    ])
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    let statusItem = app.statusItems.firstMatch
    XCTAssertTrue(statusItem.waitForExistence(timeout: 30))
    try XCTSkipUnless(
      SalahUITests.canClick(statusItem.frame),
      "The menu bar is full: macOS put Salah's status item behind the camera housing.")
    try XCTSkipUnless(
      statusItem.isHittable,
      "The menu bar is full: macOS put Salah's status item in its overflow.")

    statusItem.click()
    let quit = app.buttons[language.quit]
    XCTAssertTrue(quit.waitForExistence(timeout: 10), app.windows.debugDescription)
    let dropdown = app.dialogs.containing(.button, identifier: language.quit).firstMatch
    XCTAssertTrue(dropdown.waitForExistence(timeout: 10), app.dialogs.debugDescription)
    XCTAssertEqual(dropdown.title, language.code == "ar" ? "صلاة" : "Salah")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(quit.waitForNonExistence(timeout: 10))
    statusItem.click()
    XCTAssertTrue(quit.waitForExistence(timeout: 10))
    XCTAssertEqual(dropdown.title, language.code == "ar" ? "صلاة" : "Salah")
    app.activate()
    let isOpen: @MainActor () -> Bool = { app.state == .runningForeground && quit.exists }
    XCTAssertTrue(isOpen(), "The dropdown closed, or Salah isn't in front.")
    try assertSpeechOfTheOpenDropdown(in: language, while: isOpen)
  }

  /// Turns VoiceOver on in the dropdown, which is open and in front while `isOpen` holds,
  /// reads it from its first item to its last, and compares what VoiceOver said with what
  /// Salah shows.
  @available(macOS 27.0, *)
  @MainActor
  private func assertSpeechOfTheOpenDropdown(
    in language: Language, while isOpen: @escaping @MainActor () -> Bool
  ) throws {
    let start = Date()
    let today = Self.events(on: CivilDay(containing: start, in: Self.makkah))
    XCTAssertEqual(today.count, 6, "Today's events in Makkah")

    let speech = try Speech.start(in: self, reading: "the dropdown", while: isOpen)
    let names = today.map { language.names.name(of: $0) }
    // A row reads "Fajr", a toggle and the countdown "Fajr · …", and the last item "Quit Salah".
    try speech.confirm { said in
      names.contains(said) || names.contains { said.contains("\($0) · ") }
        || said.contains(language.quit)
    }
    // Every item, from the dropdown's first to its last, the Quit button.
    let first = try XCTUnwrap(
      try speech.previousToTheStart(),
      "VoiceOver's first move back, toward the dropdown's first item, failed.\n\(speech.log)")
    let items = [first] + (try speech.rest(limit: 60))
    let end = Date()
    XCTAssertEqual(items.last, language.quitSpoken, speech.log)

    for event in today {
      let name = language.names.name(of: event)
      let time = Self.time(event.time, in: language)
      let index = items.firstIndex(of: name)
      XCTAssertNotNil(index, "\(name)\n\(speech.log)")
      if let index {
        // The time follows the name, after the count-up of the prayer that passed last.
        XCTAssertTrue(
          items[index...].prefix(4).contains(time), "\(name) at \(time)\n\(speech.log)")
      }
    }
    // Each prayer's alert toggle says the prayer and the alert's state; every alert is off.
    // The next event's row shows its state instead while a prayer counts up.
    let stateRows = Self.nextWhileCountingUp(from: start.addingTimeInterval(-120), to: end)
    for event in today where event.kind.isPrayer && !stateRows.contains(event.time) {
      let toggle = language.alertOff(language.names.name(of: event))
      XCTAssertTrue(items.contains(toggle), "\(toggle)\n\(speech.log)")
    }
    for toggle in items.filter({ $0.contains(language.playAtPrayerTime) }) {
      XCTAssertTrue(names.contains { toggle == language.alertOff($0) }, "\(toggle)\n\(speech.log)")
    }
    let countdowns = Self.countdowns(from: start.addingTimeInterval(-120), to: end, in: language)
    XCTAssertTrue(
      items.contains(where: countdowns.contains),
      "None of \(countdowns.sorted())\n\(speech.log)")
  }
}

// MARK: - Launching and expectations

extension VoiceOverSpeechUITests {
  /// A Settings pane, with VoiceOver on in it.
  @available(macOS 27.0, *)
  struct Pane {
    let app: XCUIApplication
    let settings: XCUIElement
    let speech: Speech
  }

  /// Opens Settings on `pane` and turns VoiceOver on, with its cursor moved into the pane.
  ///
  /// VoiceOver starts on the window's first item, the sidebar's General. The pane is the
  /// window's scroll area, after the sidebar; moving into it, VoiceOver says the scroll
  /// area and the pane's first heading, `heading`.
  @available(macOS 27.0, *)
  @MainActor
  func openPane(
    _ pane: String, heading: String, arguments: [String] = VoiceOverSpeechUITests.launch()
  ) throws -> Pane {
    let app = XCUIApplication()
    app.launchArguments = arguments
    app.open(try XCTUnwrap(URL(string: "salah://settings")))
    addTeardownBlock { @MainActor in app.terminate() }
    let settings = app.windows["Salah Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 30), app.windows.debugDescription)
    let tab = settings.buttons[pane]
    XCTAssertTrue(tab.waitForExistence(timeout: 10), settings.debugDescription)
    tab.click()
    app.activate()
    let isOpen: @MainActor () -> Bool = {
      app.state == .runningForeground && settings.exists
    }
    XCTAssertTrue(isOpen(), "Settings closed, or Salah isn't in front.")

    let speech = try Speech.start(in: self, reading: "Settings", while: isOpen)
    // The window's title, or one of the sidebar's items.
    let sidebar =
      SettingsAccessibilityUITests.panes.map { "\($0) button" } + [
        "Salah Help button", "About Salah button",
      ]
    try speech.confirm(timeout: 3) { said in
      said.contains("Salah Settings") || sidebar.contains(said)
    }
    try speech.next(within: 12) { $0 == "scroll area" }
    let opening = try speech.enter()
    XCTAssertTrue(
      opening.hasPrefix("In scroll area ") && opening.hasSuffix(" heading \(heading)"),
      speech.log)
    return Pane(app: app, settings: settings, speech: speech)
  }

  /// Polls `condition` until it holds; whether it did within `timeout` seconds.
  @MainActor
  static func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      guard Date() < deadline else { return false }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return true
  }

  /// `Launch`'s arguments, with each of `overrides`' keys set to its value.
  static func launch(_ overrides: [String: String] = [:]) -> [String] {
    var arguments = Launch.arguments()
    for (key, value) in overrides {
      if let index = arguments.firstIndex(of: key) {
        arguments[index + 1] = value
      } else {
        arguments += [key, value]
      }
    }
    return arguments
  }

  /// A language of the dropdown tests, with the words Salah and VoiceOver use in it.
  struct Language: Sendable {
    /// `-salah.appLanguage`'s value.
    var setting: String
    var code: String
    /// The locale Salah formats in.
    var locale: Locale
    /// The Quit button's name, and what VoiceOver says for it.
    var quit: String
    var quitSpoken: String
    /// `SalahWidgetLabels`' words for the countdown and the count-up.
    var remaining: String
    var since: @Sendable (_ duration: String) -> String
    /// What VoiceOver says for a prayer's alert toggle while the alert is off, and the
    /// toggle's name after the prayer's.
    var alertOff: @Sendable (_ prayer: String) -> String
    var playAtPrayerTime: String

    var names: PrayerNames { PrayerNames(locale: locale) }
  }

  static let english = Language(
    setting: "english", code: "en", locale: Locale(identifier: "en"), quit: "Quit Salah",
    quitSpoken: "Quit Salah button", remaining: "remaining", since: { "started \($0) ago" },
    alertOff: { "Alert off \($0) · Play at prayer time button" },
    playAtPrayerTime: "Play at prayer time")

  static let arabic: Language = {
    // Salah's Arabic: Arabic-Indic digits, which `Locale(identifier: "ar")` doesn't use.
    var components = Locale.Components(languageCode: .arabic)
    components.numberingSystem = Locale.NumberingSystem("arab")
    return Language(
      setting: "arabic", code: "ar", locale: Locale(components: components), quit: "إنهاء صلاة",
      quitSpoken: "إنهاء صلاة زر", remaining: "متبقّية", since: { "منذ \($0)" },
      alertOff: { "تنبيه مُعطّل \($0) · تشغيل عند وقت الصلاة زر" },
      playAtPrayerTime: "تشغيل عند وقت الصلاة")
  }()

  static let makkah = TimeZone(identifier: "Asia/Riyadh") ?? .gmt

  /// The events of `Launch`'s schedule from `start` through `end`, as Salah names them:
  /// every Friday's Dhuhr is Jumu'ah, Salah's own policy (`SalahPrayerSource`).
  static func events(from start: Date, through end: Date) -> [PrayerEvent] {
    PlacedPrayer.schedule.events(from: start, through: end).events.map { event in
      var event = event
      if event.kind == .dhuhr, event.scheduleDay.weekday == 6 {
        event.observance = .jumuah
      }
      return event
    }
  }

  /// The events of `day` in `Launch`'s schedule.
  static func events(on day: CivilDay) -> [PrayerEvent] {
    let middle = Date()
    return events(
      from: middle.addingTimeInterval(-2 * 86_400), through: middle.addingTimeInterval(2 * 86_400)
    ).filter { $0.scheduleDay == day }
  }

  /// Today's events in Makkah, by name and time, as the Appearance preview shows them.
  @available(macOS 27.0, *)
  static func today(in language: Language) -> [(name: String, time: String)] {
    events(on: CivilDay(containing: Date(), in: makkah)).map {
      (language.names.name(of: $0), time($0.time, in: language))
    }
  }

  /// A time as Salah's lists write it, the locale's short time in Makkah, as VoiceOver's
  /// utterance has it (`Speech.spoken(_:)`).
  @available(macOS 27.0, *)
  static func time(_ date: Date, in language: Language) -> String {
    let formatter = DateFormatter()
    formatter.locale = language.locale
    formatter.calendar = language.locale.calendar
    formatter.timeZone = makkah
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return Speech.spoken(formatter.string(from: date))
  }

  /// What the dropdown's countdown can say for VoiceOver at any minute from `start` to
  /// `end`: the count-up of a prayer in its first 15 minutes, "Asr · started 5 minutes ago",
  /// or else the countdown to the next event, sunrise included, "Isha · 1 hour, 10
  /// minutes remaining". The dropdown words it at each minute.
  static func countdowns(from start: Date, to end: Date, in language: Language) -> Set<String> {
    var said: Set<String> = []
    for (minute, started, next) in minutes(from: start, to: end) {
      if let event = started ?? next {
        let duration = PrayerDurationFormat.string(
          abs(event.time.timeIntervalSince(minute)), width: .spoken, locale: language.locale)
        let name = language.names.name(of: event)
        said.insert(
          started == nil
            ? "\(name) · \(duration) \(language.remaining)"
            : "\(name) · \(language.since(duration))")
      }
    }
    return said
  }

  /// The times of the events whose dropdown row shows its state instead of its alert toggle
  /// at any minute from `start` to `end`: the next event, while a prayer counts up.
  static func nextWhileCountingUp(from start: Date, to end: Date) -> Set<Date> {
    Set(minutes(from: start, to: end).compactMap { $0.started == nil ? nil : $0.next?.time })
  }

  /// Each minute from `start` to `end`, with the prayer counting up in its first 15 minutes
  /// then, if any, and the next event, sunrise included.
  static func minutes(from start: Date, to end: Date) -> [(
    minute: Date, started: PrayerEvent?, next: PrayerEvent?
  )] {
    let events = events(
      from: start.addingTimeInterval(-86_400), through: end.addingTimeInterval(86_400))
    var minutes: [(Date, PrayerEvent?, PrayerEvent?)] = []
    var minute = Date(
      timeIntervalSinceReferenceDate: (start.timeIntervalSinceReferenceDate / 60).rounded(.down)
        * 60)
    while minute <= end.addingTimeInterval(60) {
      let started = events.last {
        $0.kind.isPrayer && $0.time <= minute && minute.timeIntervalSince($0.time) < 15 * 60
      }
      minutes.append((minute, started, events.first { $0.time > minute }))
      minute.addTimeInterval(60)
    }
    return minutes
  }
}

// MARK: - VoiceOver

/// VoiceOver on this Mac, and what it said after the test's moves in the window of Salah's
/// the test reads.
///
/// The service reports what VoiceOver says after a move, without the hints it adds later,
/// and at most 64 characters of it, cutting a longer utterance there: the item it moved
/// to, unless VoiceOver says something else first. A move takes up to about 10 seconds.
/// `currentSpeech()` is the last thing VoiceOver said, whatever it was about. Past the first
/// or last item of a group VoiceOver stays put: the service repeats the item, or reports
/// `noSpeech`. Utterances keep the bidi isolates Salah puts around numbers and names and the
/// narrow spaces of times, which `spoken(_:)` drops and widens.
///
/// VoiceOver reads whichever app is in front, so nothing it says is kept until it's in the
/// window the test reads (`confirm`). After that, only what it says after the test's own
/// moves is kept, and, after a key press, the exact words the test waits for (`waitFor`),
/// and only while Salah is in front with that window open: at the first move after that
/// stops holding, the test drops the speech and fails (`Left`). Speech VoiceOver
/// makes for another app right after a move, such as a notification it reads out while
/// Salah stays in front, can still be kept; run the tests with Do Not Disturb on.
@available(macOS 27.0, *)
@MainActor
final class Speech {
  private let service = XCUIDevice.shared.voiceOverService
  /// The window the test reads, and whether VoiceOver can only be in it: Salah in front with
  /// the window open.
  private let place: String
  private let isInPlace: @MainActor () -> Bool
  /// Each move and what VoiceOver said, for failure messages and the attachment.
  private(set) var transcript: [String] = []
  /// What VoiceOver said at the last kept move.
  private var lastSaid: String?
  /// Whether VoiceOver came on for the test.
  private var isOn = false

  /// The transcript, one move a line.
  var log: String { transcript.joined(separator: "\n") }

  /// The time a test turned VoiceOver on, in the test runner's own defaults, until it turns
  /// it off. A runner that stops before its teardown, or a test whose `enable()` gave up,
  /// leaves the time set: for half an hour, a test takes VoiceOver that's on as a test's,
  /// even one the person turned on meanwhile: it restarts it, and turns it off at its end.
  /// Later, VoiceOver that's on is taken as the person's, and the tests skip; Command-F5
  /// turns it off.
  private static let turnedOnKey = "VoiceOverSpeechUITests.turnedVoiceOverOn"

  /// Whether a test turned VoiceOver on in the last half hour and didn't turn it off.
  private static var aTestTurnedItOn: Bool {
    guard let date = UserDefaults.standard.object(forKey: turnedOnKey) as? Date else {
      return false
    }
    return Date().timeIntervalSince(date) < 30 * 60
  }

  private init(place: String, isInPlace: @escaping @MainActor () -> Bool) {
    self.place = place
    self.isInPlace = isInPlace
  }

  /// Turns VoiceOver on for the rest of `test`, to read `place`, a window of Salah's that is
  /// open and in front while `isInPlace` holds; turns it off at the test's end, including
  /// when `enable()` gave up but VoiceOver came on later, and attaches the transcript.
  ///
  /// VoiceOver that comes on starts on the window's first item, where the tests read from;
  /// VoiceOver that was on already may be elsewhere. So when VoiceOver is on already, the
  /// test restarts it if a test turned it on in the last half hour, and otherwise skips, as
  /// it's the person's, leaving it as it is. It also skips on a Mac that isn't in English,
  /// as VoiceOver's own words, such as "selected" and "dimmed", are in the Mac's language,
  /// and when VoiceOver doesn't turn off to restart, or doesn't turn on.
  static func start(
    in test: XCTestCase, reading place: String,
    while isInPlace: @escaping @MainActor () -> Bool
  ) throws -> Speech {
    let language = Locale.preferredLanguages.first.map { Locale(identifier: $0).language }
    try XCTSkipUnless(
      language?.languageCode == .english,
      "VoiceOver speaks its own words in the Mac's language, and these tests expect English.")
    let service = XCUIDevice.shared.voiceOverService
    try XCTSkipIf(
      service.isEnabled && !aTestTurnedItOn,
      "VoiceOver is already on. Turn it off (Command-F5) and run the tests again; they turn it "
        + "on and off themselves.")
    UserDefaults.standard.set(Date(), forKey: turnedOnKey)
    let speech = Speech(place: place, isInPlace: isInPlace)
    test.addTeardownBlock { @MainActor in
      let attachment = XCTAttachment(string: speech.log)
      attachment.name = "VoiceOver"
      attachment.lifetime = .keepAlways
      test.add(attachment)
      let service = XCUIDevice.shared.voiceOverService
      if !speech.isOn {
        // VoiceOver didn't come on for the test: a stopped run's VoiceOver didn't turn off,
        // or enable() gave up, and VoiceOver may still start. It's turned off if it's on now
        // or comes on within 10 seconds. If it doesn't, the time stays set, so a test in the
        // next half hour turns it off should it start later.
        let deadline = Date().addingTimeInterval(10)
        while !service.isEnabled, Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
        guard service.isEnabled else { return }
      }
      guard service.isEnabled else {
        UserDefaults.standard.removeObject(forKey: turnedOnKey)
        return
      }
      do {
        try service.disable()
        UserDefaults.standard.removeObject(forKey: turnedOnKey)
      } catch {
        // The time stays set, so the next test turns VoiceOver off.
        XCTFail("VoiceOver didn't turn off (\(error)); Command-F5 turns it off.")
      }
    }
    // VoiceOver a test left on would stay where it was: enable() does nothing to VoiceOver
    // that's on. So it's turned off first, and the test skips if it doesn't turn off.
    if service.isEnabled {
      do {
        try service.disable()
      } catch {
        throw XCTSkip(
          "VoiceOver, which a test left on, didn't turn off to start again: "
            + error.localizedDescription)
      }
    }
    do {
      try service.enable()
    } catch {
      throw XCTSkip("VoiceOver didn't turn on: \(error.localizedDescription)")
    }
    speech.isOn = true
    return speech
  }

  /// Waits up to `timeout` seconds for VoiceOver, just turned on, to say something
  /// `match` recognizes while it can only be in `place`; then moves forward at most `moves`
  /// items for it. Nothing VoiceOver says until then is kept, as it may be another app's;
  /// when it never says anything of the place's, the error names only the place.
  func confirm(timeout: TimeInterval = 10, moves: Int = 2, _ match: (String) -> Bool) throws {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if match(Self.spoken((try? service.currentSpeech())?.utterance ?? "")), isInPlace() {
        return
      }
      Thread.sleep(forTimeInterval: 0.25)
    } while Date() < deadline
    for _ in 0..<moves {
      if match(Self.spoken((try? service.moveForward())?.utterance ?? "")), isInPlace() {
        return
      }
    }
    transcript.append("(VoiceOver isn't in \(place).)")
    throw Missing(what: "anything in \(place)", transcript: transcript)
  }

  /// Moves to the next item, as VO-Right Arrow does; what VoiceOver said there.
  @discardableResult
  func next() throws -> String {
    try move("→", { try service.moveForward() }, back: { try service.moveBackward() })
  }

  /// Moves to the previous item, as VO-Left Arrow does.
  @discardableResult
  func previous() throws -> String {
    try move("←", { try service.moveBackward() }, back: { try service.moveForward() })
  }

  /// Moves into the item, as VO-Shift-Down Arrow does.
  @discardableResult
  func enter() throws -> String {
    try move("↘", { try service.moveIn() }, back: { try service.moveOut() })
  }

  /// Moves out to the item's group, as VO-Shift-Up Arrow does.
  @discardableResult
  func leave() throws -> String { try record("↖") { try service.moveOut() } }

  /// Moves as `body` does. VoiceOver sometimes says what it said last again: it didn't move,
  /// or it moved and hasn't spoken yet. That answer isn't kept. A second later, if VoiceOver
  /// still hasn't said anything new, the move is tried once more. If it has, which may also
  /// be another app's speech, it moves `back` and as `body` again, and keeps what it says
  /// then: the item it's on. When that's still the one before, it moves once more, though
  /// VoiceOver may have been late again, which would skip an item. The transcript notes each
  /// move tried once more. (Past a group's last item, VoiceOver says the same thing at every
  /// try.)
  private func move(
    _ move: String, _ body: () throws -> XCUIVoiceOverService.Output,
    back: () throws -> XCUIVoiceOverService.Output
  ) throws -> String {
    let before = lastSaid
    let said = try answer(move, body)
    guard said == before else { return try keep(move, said) }
    Thread.sleep(forTimeInterval: 1)
    if Self.spoken((try? service.currentSpeech())?.utterance ?? said) != said {
      _ = try? back()
      let again = try answer(move, body)
      if again != before { return try keep(move, again) }
    }
    transcript.append("\(move) (said the same again; retried)")
    return try record(move, body)
  }

  /// Moves forward until VoiceOver says something `match` accepts, and returns it. Fails
  /// after `limit` moves, or when VoiceOver says the same thing three times in a row: the
  /// end of the group.
  @discardableResult
  func next(within limit: Int = 30, until match: (String) -> Bool) throws -> String {
    var last: String?
    var repeats = 0
    for _ in 0..<limit {
      let said = try next()
      if match(said) { return said }
      repeats = said == last ? repeats + 1 : 0
      if repeats == 2 { break }
      last = said
    }
    throw Missing(what: "what the test looked for", transcript: transcript)
  }

  /// Moves forward to the group's last item, and returns what VoiceOver said on the way:
  /// until it says the same thing three times in a row or has nothing to say, at most
  /// `limit` moves.
  func rest(limit: Int = 40) throws -> [String] {
    var said: [String] = []
    var repeats = 0
    for _ in 0..<limit {
      let next: String
      do {
        next = try self.next()
      } catch let left as Left {
        throw left
      } catch {
        break
      }
      repeats = next == said.last ? repeats + 1 : 0
      if repeats == 2 { break }
      said.append(next)
    }
    return said
  }

  /// Moves back to the group's first item, the same way, at most `limit` moves, and returns
  /// the last item kept on the way: the first item, unless a move fails before it; `nil`
  /// when none was kept.
  func previousToTheStart(limit: Int = 40) throws -> String? {
    var last: String?
    var repeats = 0
    for _ in 0..<limit {
      let said: String
      do {
        said = try previous()
      } catch let left as Left {
        throw left
      } catch {
        break
      }
      repeats = said == last ? repeats + 1 : 0
      last = said
      if repeats == 2 { break }
    }
    return last
  }

  /// Waits up to `timeout` seconds for VoiceOver to say something `match` accepts, and
  /// returns it: what it says after a key press. What it says otherwise isn't kept, as it
  /// may be about something else.
  @discardableResult
  func waitFor(timeout: TimeInterval = 10, _ match: (String) -> Bool) throws -> String {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      let said = Self.spoken((try? service.currentSpeech())?.utterance ?? "")
      if match(said) { return try keep("…", said) }
      Thread.sleep(forTimeInterval: 0.25)
    } while Date() < deadline
    guard isInPlace() else { throw left() }
    transcript.append("… (nothing it waited for, in \(Int(timeout)) seconds)")
    throw Missing(what: "what the test waited for", transcript: transcript)
  }

  /// A move or a wait didn't reach what a test looked for.
  struct Missing: Error, CustomStringConvertible {
    var what: String
    var transcript: [String]
    var description: String {
      "VoiceOver didn't say \(what). It said:\n" + transcript.joined(separator: "\n")
    }
  }

  /// VoiceOver left the window the test reads: Salah went to the background, or the window
  /// closed.
  struct Left: Error, CustomStringConvertible {
    var place: String
    var description: String { "VoiceOver left \(place)." }
  }

  /// Records what `body` makes VoiceOver say (`keep(_:_:)`).
  private func record(_ move: String, _ body: () throws -> XCUIVoiceOverService.Output) throws
    -> String
  {
    try keep(move, try answer(move, body))
  }

  /// What `body` makes VoiceOver say, not kept yet. When the service fails instead, as it can
  /// once VoiceOver has left `place`, that's `Left` too.
  private func answer(_ move: String, _ body: () throws -> XCUIVoiceOverService.Output) throws
    -> String
  {
    do {
      return Self.spoken(try body().utterance)
    } catch {
      guard isInPlace() else { throw left() }
      transcript.append("\(move) (\(error.localizedDescription))")
      throw error
    }
  }

  /// Keeps `said` while VoiceOver can only be in `place`. Once it can't, drops `said`, which
  /// may be another app's, and throws `Left`.
  private func keep(_ move: String, _ said: String) throws -> String {
    guard isInPlace() else { throw left() }
    transcript.append("\(move) \(said)")
    lastSaid = said
    return said
  }

  /// `Left`, noted in the transcript.
  private func left() -> Left {
    transcript.append("(VoiceOver left \(place).)")
    return Left(place: place)
  }

  /// What VoiceOver said, without bidi isolates and marks, and with plain spaces.
  nonisolated static func spoken(_ utterance: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in utterance.unicodeScalars {
      switch scalar.value {
      case 0x2066...0x2069, 0x200E, 0x200F, 0x061C: continue
      case 0x00A0, 0x202F: scalars.append(" ")
      default: scalars.append(scalar)
      }
    }
    return String(scalars)
  }
}
