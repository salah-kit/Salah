import Foundation
import SalahCore
import Testing

/// The status item draws Figma's menu bar gallery: each of the five displays in the normal,
/// approaching, just-started, playing and needs-attention states, in English and Arabic.
@Suite("Menu bar item")
struct MenuBarItemTests {
  init() { TestEnvironment.configure() }

  enum Display: CaseIterable {
    case icon, iconCountdown, iconNameCountdown, nameTime, abbreviationCountdown

    var settings: MenuBarItem.Display {
      switch self {
      case .icon: MenuBarItem.Display(showsIcon: true, showsNextPrayer: false)
      case .iconCountdown: MenuBarItem.Display(name: .none, time: .timeUntil)
      case .iconNameCountdown: MenuBarItem.Display(name: .full, time: .timeUntil)
      case .nameTime: MenuBarItem.Display(showsIcon: false, name: .full, time: .timeOfPrayer)
      case .abbreviationCountdown: MenuBarItem.Display(name: .abbreviation, time: .timeUntil)
      }
    }
  }

  enum State {
    case normal, approaching, justStarted, playing, needsAttention

    /// The gallery's moments on the fixture day: Asr in 2:16 (1:19 PM), Asr in 10 minutes,
    /// Dhuhr 4 minutes in, Maghrib's adhan 2 minutes in.
    var moment: MenuBarItem.Moment {
      let asr = Fixture.event(.asr)
      switch self {
      case .normal, .needsAttention:
        return MenuBarItem.Moment(
          now: Fixture.date(13, 19), justStarted: nil, next: asr, isApproaching: false,
          needsAttention: self == .needsAttention)
      case .approaching:
        return MenuBarItem.Moment(
          now: asr.time.adding(minutes: -10), justStarted: nil, next: asr, isApproaching: true,
          needsAttention: false)
      case .justStarted:
        let dhuhr = Fixture.event(.dhuhr)
        return MenuBarItem.Moment(
          now: dhuhr.time.adding(minutes: 4), justStarted: dhuhr, next: asr,
          isApproaching: false, needsAttention: false)
      case .playing:
        let maghrib = Fixture.event(.maghrib)
        return MenuBarItem.Moment(
          now: maghrib.time.adding(minutes: 2), playing: maghrib, playingTitle: "Playing adhan",
          justStarted: maghrib, next: Fixture.event(.isha), isApproaching: false,
          needsAttention: false)
      }
    }
  }

  func item(_ display: Display, _ state: State, _ language: AppLanguage = .english)
    -> MenuBarItem
  {
    AppLanguageScope.with(language) {
      MenuBarItem(
        display: display.settings, moment: state.moment,
        text: SalahText(locale: language.locale, timeZone: Fixture.timeZone),
        names: PrayerNames(locale: language.locale), appName: "Salah")
    }
  }

  /// The text without its bidi isolates, as it reads.
  func text(_ item: MenuBarItem) -> String { plain(item.text) }

  func plain(_ string: String) -> String {
    string.replacingOccurrences(of: "\u{2068}", with: "")
      .replacingOccurrences(of: "\u{2069}", with: "")
  }

  @Test func theNormalStateShowsEachDisplay() {
    let expected: [(Display, MenuBarItem.Icon, String)] = [
      (.icon, .glyph(.asr), ""),
      (.iconCountdown, .glyph(.asr), "2:16"),
      (.iconNameCountdown, .glyph(.asr), "Asr 2:16"),
      (.nameTime, .none, "Asr 3:35"),
      (.abbreviationCountdown, .glyph(.asr), "A 2:16"),
    ]
    for (display, icon, string) in expected {
      let item = item(display, .normal)
      #expect(item.icon == icon, "\(display)")
      #expect(text(item) == string, "\(display)")
      #expect(!item.approaching && !item.attention, "\(display)")
    }
  }

  @Test func theApproachingStateIsTheGoldCapsuleInEveryDisplay() {
    let expected: [(Display, String)] = [
      (.icon, ""), (.iconCountdown, "10m"), (.iconNameCountdown, "Asr 10m"),
      (.nameTime, "Asr 3:35"), (.abbreviationCountdown, "A 10m"),
    ]
    for (display, string) in expected {
      let item = item(display, .approaching)
      #expect(item.approaching, "\(display)")
      #expect(text(item) == string, "\(display)")
    }
  }

  /// The prayer that just began leads, in the countdown and the clock-time displays
  /// alike: its glyph, and "Dhuhr +4m" or "Dhuhr 12:19".
  @Test func theJustStartedPrayerLeadsEveryDisplay() {
    let expected: [(Display, MenuBarItem.Icon, String)] = [
      (.icon, .glyph(.dhuhr), ""),
      (.iconCountdown, .glyph(.dhuhr), "+4m"),
      (.iconNameCountdown, .glyph(.dhuhr), "Dhuhr +4m"),
      (.nameTime, .none, "Dhuhr 12:19"),
      (.abbreviationCountdown, .glyph(.dhuhr), "D +4m"),
    ]
    for (display, icon, string) in expected {
      let item = item(display, .justStarted)
      #expect(item.icon == icon, "\(display)")
      #expect(text(item) == string, "\(display)")
      #expect(!item.approaching, "\(display)")
    }
  }

  /// While the adhan plays, the speaker shows only where the display has the icon, and the
  /// text names the prayer, with its time in the clock-time display.
  @Test func playingShowsTheSpeakerAndThePrayer() {
    let expected: [(Display, MenuBarItem.Icon, String)] = [
      (.icon, .speaker, ""),
      (.iconCountdown, .speaker, "Maghrib"),
      (.iconNameCountdown, .speaker, "Maghrib"),
      (.nameTime, .none, "Maghrib 7:00"),
      (.abbreviationCountdown, .speaker, "M"),
    ]
    for (display, icon, string) in expected {
      let item = item(display, .playing)
      #expect(item.icon == icon, "\(display)")
      #expect(text(item) == string, "\(display)")
      #expect(!item.approaching, "\(display)")
    }
  }

  /// A permission that's off adds the dot to the glyph, and adds no glyph where the display
  /// has none: Name + time reads "Asr 3:35" plainly.
  @Test func needsAttentionDotsTheGlyphOnly() {
    for display in Display.allCases {
      let item = item(display, .needsAttention)
      #expect(item.attention == (display != .nameTime), "\(display)")
      #expect(item.icon == (display == .nameTime ? .none : .glyph(.asr)), "\(display)")
      #expect(text(item) == text(self.item(display, .normal)), "\(display)")
    }
  }

  @Test func arabicReadsAsFigmaDrawsIt() {
    let expected: [(Display, State, String)] = [
      (.iconCountdown, .normal, "٢:١٦"),
      (.iconNameCountdown, .normal, "العصر ٢:١٦"),
      (.nameTime, .normal, "العصر ٣:٣٥"),
      (.abbreviationCountdown, .normal, "عص ٢:١٦"),
      (.iconNameCountdown, .approaching, "العصر ١٠د"),
      (.iconNameCountdown, .justStarted, "الظهر +٤د"),
      (.nameTime, .justStarted, "الظهر ١٢:١٩"),
      (.iconNameCountdown, .playing, "المغرب"),
      (.nameTime, .playing, "المغرب ٧:٠٠"),
    ]
    for (display, state, string) in expected {
      #expect(text(item(display, state, .arabic)) == string, "\(display) \(state)")
    }
  }

  /// VoiceOver says the app, then what the item shows in words: "Salah, Asr in 2 hours,
  /// 16 minutes".
  @Test func voiceOverSaysTheAppAndTheCountdownInWords() {
    let english = AppLanguage.english.locale
    let spoken = PrayerDurationFormat.string(136 * 60, width: .spoken, locale: english)
    #expect(item(.icon, .normal).accessibilityLabel == "Salah, Asr in \(spoken)")
    #expect(item(.nameTime, .normal).accessibilityLabel == "Salah, Asr in \(spoken)")
    #expect(spoken.hasPrefix("2 hours") && spoken.contains("16 minutes"))
    #expect(item(.icon, .playing).accessibilityLabel == "Salah, Playing adhan · Maghrib")
    #expect(item(.iconNameCountdown, .justStarted).accessibilityLabel.hasPrefix("Salah, Dhuhr"))
    #expect(
      plain(item(.iconNameCountdown, .normal, .arabic).accessibilityLabel).hasPrefix(
        "Salah، العصر بعد"))
  }
}
