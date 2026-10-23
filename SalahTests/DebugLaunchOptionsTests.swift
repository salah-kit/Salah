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
    scratch.defaults.set("888", forKey: DebugOptions.windowSizeKey)
    #expect(DebugOptions.now(defaults: scratch.defaults) == nil)
    #expect(DebugOptions.windowSize(defaults: scratch.defaults) == nil)
  }

  /// Without the option the shown moment is the real one.
  @Test func theClockIsRealWithoutTheOption() {
    #expect(abs(AppClock.now.timeIntervalSinceNow) < 1)
    let date = Date(timeIntervalSince1970: 1_000_000)
    #expect(AppClock.shifted(date) == date)
  }
}
