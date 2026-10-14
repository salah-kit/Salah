import AppIntents
import Foundation
import SalahWidgets

/// Backs the widget's "tap to stop" action. As a plain `AppIntent`, its
/// `perform()` runs in the widget-extension process, which can't touch the app's
/// audio directly - so it clears what's playing in the App Group, which reloads the
/// widget, and posts `DarwinSignal.stopAudio`, which the running app observes to stop
/// `AudioPlaybackController` and confirm by saving what's playing again.
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
  static var title: LocalizedStringResource { "Stop Adhan" }
  static var description: IntentDescription {
    IntentDescription("Stops the currently playing Salah adhan or reminder.")
  }

  func perform() async throws -> some IntentResult {
    // The widget redraws without the Stop control at once; the app's confirmation
    // follows when it has stopped.
    _ = try? SharedValue.playback.save(
      nil, reloading: [SalahWidgetConstants.prayerTimesWidgetKind])
    DarwinSignal.stopAudio.post()
    return .result()
  }
}
