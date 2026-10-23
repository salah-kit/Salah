import SalahCore
import Testing

/// The status item's glyph and speaker follow what plays and what the text names.
@Suite("Menu bar status")
struct MenuBarStatusTests {
  init() { TestEnvironment.configure() }

  /// For 15 minutes after a prayer the text counts up from it: its glyph, and no speaker,
  /// since nothing plays.
  @Test func aCountUpShowsItsPrayerWithoutTheSpeaker() {
    let status = MenuBarStatus(
      audio: .idle, countUp: Fixture.event(.dhuhr), next: Fixture.event(.asr))
    #expect(!status.isPlaying)
    #expect(status.playingPrayer == nil)
    #expect(status.glyph == .dhuhr)
  }

  /// When the text shows the next prayer's time, no count-up leads, so the glyph is the
  /// next prayer's, as the text is, even in the prayer's first 15 minutes.
  @Test func withoutACountUpTheGlyphIsTheNextPrayers() {
    let status = MenuBarStatus(audio: .idle, countUp: nil, next: Fixture.event(.asr))
    #expect(status.glyph == .asr)
  }

  /// While audio plays, the speaker shows and the text names the playing prayer.
  @Test func playingAudioShowsTheSpeakerAndItsPrayer() {
    let asr = Fixture.event(.asr)
    let status = MenuBarStatus(
      audio: .playing(AudioPlaybackContext(source: .prayerAlert, slot: .preReminder, event: asr)),
      countUp: nil, next: asr)
    #expect(status.isPlaying)
    #expect(status.playingPrayer == asr)
  }
}
