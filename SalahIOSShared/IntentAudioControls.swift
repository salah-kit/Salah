import AppIntents
import Foundation
import SalahWidgets
import WidgetKit

/// How an intent stops the app's audio.
///
/// Stop runs in the app's process, where the app registers itself: the audio stops and the
/// Live Activity changes before the intent returns, so one tap is enough. In another process
/// the signal reaches the app.
@MainActor enum IOSAudioStopper {
  static var stopInProcess: (@MainActor () async -> Void)?

  /// Returns whether the app stopped in this process.
  @discardableResult
  static func stop(signal: @MainActor () -> Void = { DarwinSignal.stopAudio.post() }) async
    -> Bool
  {
    guard let stopInProcess else {
      signal()
      return false
    }
    await stopInProcess()
    return true
  }
}

/// Runs in the app process so stopping works while the foreground app is suspended.
nonisolated struct IOSStopAudioIntent: LiveActivityIntent, AudioPlaybackIntent {
  static var title: LocalizedStringResource { "Stop audio" }
  static var description: IntentDescription { "Stops audio you started in Salah." }
  static var isDiscoverable: Bool { false }

  func perform() async throws -> some IntentResult {
    _ = try SharedValue<IOSPlaybackSession>.iosPlayback.save(
      nil, reloading: [SalahWidgetConstants.prayerTimesWidgetKind])
    _ = try SharedValue<SalahPlayback>.playback.save(nil)
    await IOSAudioStopper.stop()
    ControlCenter.shared.reloadControls(ofKind: IOSControlKind.stopAudio)
    return .result()
  }
}

/// The canonical preferences owner handles the mutation; alert enablement stays intact.
struct IOSSetMuteSoundsIntent: SetValueIntent, AudioPlaybackIntent {
  static var title: LocalizedStringResource { "Mute sounds" }
  static var description: IntentDescription {
    "Mutes Salah sounds. Your prayer notifications and reminders still arrive."
  }
  static var isDiscoverable: Bool { false }

  @Parameter(title: "Mute sounds") var value: Bool

  func perform() async throws -> some IntentResult {
    let preferences = try IOSSharedPreferencesStore.live.update { $0.muteSounds = value }
    // Without a location there are no settings to publish, and the widgets keep theirs.
    if let settings = preferences.mirror {
      _ = try SharedValue<SalahSettings>.settings.save(
        settings, reloading: [SalahWidgetConstants.prayerTimesWidgetKind])
    }
    if value {
      _ = try SharedValue<IOSPlaybackSession>.iosPlayback.save(nil)
      _ = try SharedValue<SalahPlayback>.playback.save(nil)
      DarwinSignal.stopAudio.post()
    }
    #if !SALAH_WIDGET_EXTENSION
      await IOSNotificationService.refreshFromPreferences(preferences)
    #endif
    ControlCenter.shared.reloadControls(ofKind: IOSControlKind.muteSounds)
    ControlCenter.shared.reloadControls(ofKind: IOSControlKind.stopAudio)
    return .result()
  }
}
