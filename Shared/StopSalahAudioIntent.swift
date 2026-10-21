import AppIntents
import Foundation
import SalahWidgets

/// Backs the widget's "tap to stop" action. As a plain `AppIntent`, its
/// `perform()` runs in the widget-extension process, which can't touch the app's
/// audio directly - so it clears what's playing in the App Group, requesting a
/// widget reload when that value changes, and posts `DarwinSignal.stopAudio`, which
/// the app observes to stop `AudioPlaybackController` and confirm by saving again.
///
/// The app acts on the signal, not on the cleared value: the value reaches the app's
/// process through the preferences daemon, which can lag behind the signal.
/// (The intent was once an `AudioPlaybackIntent`, chosen hoping the system would run
/// it in-app; it ran in the extension, so an in-process flag the app gated on wasn't
/// visible there and Stop silently no-op'd.)
///
/// Marked `nonisolated` so it conforms cleanly under the app target's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` - `AppIntent`'s requirements are
/// nonisolated. It's an interactive button intent, so it coexists with the
/// `StaticConfiguration` widget.
nonisolated struct StopSalahAudioIntent: AppIntent {
  private let playback: SharedValue<SalahPlayback>
  private let stopAudio: DarwinSignal

  init() {
    self.init(playback: .playback, stopAudio: .stopAudio)
  }

  init(playback: SharedValue<SalahPlayback>, stopAudio: DarwinSignal) {
    self.playback = playback
    self.stopAudio = stopAudio
  }

  static var title: LocalizedStringResource { "Stop Adhan" }
  static var description: IntentDescription {
    IntentDescription("Stops the currently playing Salah adhan or reminder.")
  }

  func perform() async throws -> some IntentResult {
    // Standalone calls do not receive WidgetKit's automatic interaction reload.
    // Publish and request a reload before signalling the app to stop.
    _ = try? playback.save(
      nil, reloading: [SalahWidgetConstants.prayerTimesWidgetKind])
    stopAudio.post()
    return .result()
  }
}
