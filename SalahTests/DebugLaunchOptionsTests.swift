import Foundation
import Testing

/// The launch options that put the real app in a given state for a screenshot: the moment
/// it shows and its window's size.
@Suite("Debug launch options")
struct DebugLaunchOptionsTests {
  @Test func readsTheMomentAndTheWindowSize() {
    let scratch = ScratchDefaults()
    scratch.defaults.set("2026-06-02T13:19:00+03:00", forKey: DebugOptions.nowKey)
    scratch.defaults.set("888x411", forKey: DebugOptions.windowSizeKey)
    #expect(DebugOptions.now(defaults: scratch.defaults) == Fixture.date(13, 19))
    #expect(DebugOptions.windowSize(defaults: scratch.defaults) == CGSize(width: 888, height: 411))
  }

  @Test func ignoresWhatItCannotRead() {
    let scratch = ScratchDefaults()
    scratch.defaults.set("noon", forKey: DebugOptions.nowKey)
    #expect(DebugOptions.now(defaults: scratch.defaults) == nil)
    for size in ["888", "888x", "x411", "888xax411", "0x411", "-888x411", "infx411"] {
      scratch.defaults.set(size, forKey: DebugOptions.windowSizeKey)
      #expect(DebugOptions.windowSize(defaults: scratch.defaults) == nil, "\(size)")
    }
  }

  /// The shown moment moves in whole minutes from the real one, so each real minute starts
  /// a shown minute: launched at 10:07:23, 13:19 shows from then until 10:08, then 13:20.
  @Test func theShownMomentStartsWhereItWasAskedForAndRunsOnInWholeMinutes() {
    let start = Fixture.date(13, 19)
    let launch = Fixture.date(10, 7).addingTimeInterval(23.4)
    let offset = AppClock.offset(showing: start, at: launch)
    #expect(offset.truncatingRemainder(dividingBy: 60) == 0)
    #expect(launch.addingTimeInterval(offset) == start.addingTimeInterval(23.4))
    #expect(Fixture.date(10, 8).addingTimeInterval(offset) == Fixture.date(13, 20))
    #expect(AppClock.offset(showing: launch, at: start) == -offset, "Back in time too")
  }

  /// Without the option the shown moment is the real one.
  @Test func theClockIsRealWithoutTheOption() {
    #expect(abs(AppClock.now.timeIntervalSinceNow) < 1)
    let date = Date(timeIntervalSince1970: 1_000_000)
    #expect(AppClock.shifted(date) == date)
  }
}
