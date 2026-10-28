import Foundation
import SalahCore
import SalahUI
import SwiftUI
import Testing
import WidgetKit

@Suite("The watch's complications")
@MainActor
struct WatchComplicationTests {
  init() { WatchTestResources.use() }

  @Test func askForTheIPhoneUntilItSendsPreferences() {
    let timeline = SalahWidgetTimeline.make(
      settings: nil, playback: nil, now: WatchFixtures.date("2026-10-12T12:19:00Z"))
    #expect(timeline.reload == .never)
    guard case .setupNeeded = timeline.entries.first?.content else {
      Issue.record("Expected the setup entry")
      return
    }
    #expect(
      WatchComplicationCopy.setUp(locale: Locale(identifier: "en"))
        == "Set up Salah on your iPhone")
    #expect(
      WatchComplicationCopy.setUp(locale: AppLanguage.arabic.locale)
        == "أعدّ صلاة على جهاز iPhone")
  }

  @Test func countDownFromTheWatchsOwnSchedule() throws {
    let settings = try #require(WatchFixtures.preferences().mirror)
    let now = WatchFixtures.date("2026-10-12T12:19:00Z")
    let timeline = SalahWidgetTimeline.make(settings: settings, playback: nil, now: now)
    guard case .schedule(let display)? = timeline.entries.first?.content else {
      Issue.record("Expected a schedule entry")
      return
    }
    #expect(display.focus?.event.kind == .asr)
    #expect(timeline.entries.count > 1)
    guard case .after(let reload) = timeline.reload else {
      Issue.record("Expected a reload date")
      return
    }
    #expect(reload > now)
  }

  /// The Smart Stack raises the complication around each prayer.
  @Test func rankHigherAroundAPrayer() throws {
    let preferences = WatchFixtures.preferences()
    func relevance(_ text: String) -> Float? {
      SalahWidgetEntry(
        date: WatchFixtures.date(text),
        content: .schedule(WatchFixtures.display(at: text, preferences: preferences))
      ).relevance?.score
    }
    #expect(relevance("2026-10-12T12:19:00Z") == 1)
    #expect(relevance("2026-10-12T17:05:00Z") == 100)
    #expect(relevance("2026-10-12T17:20:00Z") == 100)
    #expect(SalahWidgetEntry(date: .now, content: .setupNeeded).relevance == nil)
  }

  @Test func measureProgressFromThePreviousPrayer() {
    let atDhuhr = WatchFixtures.display(at: "2026-10-12T11:47:00Z")
    let halfway = WatchFixtures.display(at: "2026-10-12T13:12:00Z")
    #expect(WatchComplicationCopy.progress(display: atDhuhr) < 0.01)
    #expect(abs(WatchComplicationCopy.progress(display: halfway) - 0.5) < 0.01)
  }

  @Test func shortenTheInlineLineToTheTime() throws {
    let display = WatchFixtures.display(at: "2026-10-12T12:19:00Z")
    let focus = try #require(display.focus)
    #expect(
      plain(WatchComplicationCopy.shortInline(display: display, focus: focus)) == "Asr 3:37 PM")
  }

  /// Each family draws, in the watch's language, at a fixed moment.
  @Test(arguments: [
    WidgetFamily.accessoryInline, .accessoryCircular, .accessoryRectangular, .accessoryCorner,
  ])
  func drawEveryFamily(_ family: WidgetFamily) throws {
    for language in [AppLanguage.english, .arabic] {
      let display = WatchFixtures.display(
        at: "2026-10-12T12:19:00Z", preferences: WatchFixtures.preferences(language: language))
      let focus = try #require(display.focus)
      let view = WatchAccessoryFace(display: display, focus: focus, family: family)
        .environment(\.salahTimerPause, display.date)
        .frame(width: 184, height: 80)
      let renderer = ImageRenderer(content: view)
      renderer.scale = 2
      let image = try #require(renderer.cgImage)
      #expect(image.width > 0 && image.height > 0)
    }
  }
}
