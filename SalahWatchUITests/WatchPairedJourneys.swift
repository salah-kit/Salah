import XCTest

/// The preferences' way from the iPhone to the watch, on an iPhone simulator paired with a
/// watch simulator: a watch app with no preferences of its own shows the place the iPhone app
/// sent. `scripts/paired-watch-journey.sh` sets Salah up on the iPhone at the Kaaba first,
/// and runs this with `SALAH_WATCH_PAIRED=1`; otherwise it skips.
nonisolated final class WatchPairedJourneys: XCTestCase {
  override func setUpWithError() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SALAH_WATCH_PAIRED"] == "1",
      "The paired journey runs only from scripts/paired-watch-journey.sh.")
  }

  @MainActor
  func testThePreferencesArriveFromTheIPhone() {
    var journey = WatchJourneyApp()
    journey.fixture = nil
    journey.now = nil
    journey.frozen = false
    journey.tab = "qibla"
    journey.heading = "none"
    journey.launch()
    let app = journey.app
    // The watch has nothing until the iPhone's preferences arrive: the context it sent, or
    // the reply to the watch's request. Only the iPhone's place puts the watch at the Kaaba.
    require("qibla.dial", in: app, timeout: 120)
    waitForLabel("qibla.dial", containing: "You are at the Kaaba", in: app)
    screenshot("paired-received")
    // The watch keeps them: a relaunch shows them without waiting for the iPhone.
    journey.relaunch()
    waitForLabel("qibla.dial", containing: "You are at the Kaaba", in: app)
  }
}
