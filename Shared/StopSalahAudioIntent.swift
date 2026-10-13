import AppIntents
import Foundation

/// Backs the widget's "tap to stop" action. As a plain `AppIntent`, its
/// `perform()` runs in the widget-extension process, which can't touch the app's
/// audio directly - so it writes the App-Group command flag and posts a Darwin
/// notification that the always-running app observes
/// (`SalahWidgetCommandObserver`) to stop `AudioPlaybackController`.
/// It also clears the stored active-alert snapshot before the reload request so
/// WidgetKit never refreshes from stale "still playing" data.
///
/// (Was an `AudioPlaybackIntent`, chosen hoping the system would run it in-app;
/// in practice it ran in the extension, so the in-process flag the observer
/// gated on wasn't visible there and Stop silently no-op'd. A plain `AppIntent`
/// plus acting on the cross-process Darwin notification is the reliable path.)
///
/// Marked `nonisolated` (along with the `SalahWidgetStore` /
/// `SalahWidgetConstants` it touches) so it conforms cleanly under the app
/// target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` - `AppIntent`'s
/// requirements are nonisolated. It's an interactive button intent, so it
/// coexists with the `StaticConfiguration` widget.
nonisolated struct StopSalahAudioIntent: AppIntent {
  static var title: LocalizedStringResource { "Stop Adhan" }
  static var description: IntentDescription {
    IntentDescription("Stops the currently playing Salah adhan or reminder.")
  }

  func perform() async throws -> some IntentResult {
    SalahWidgetStore.requestStopAudio()
    return .result()
  }
}
