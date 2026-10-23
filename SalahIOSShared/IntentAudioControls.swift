import AppIntents
import Foundation
import SalahWidgets
import WidgetKit

/// Runs in the app process so stopping works while the foreground app is suspended.
nonisolated struct IOSStopAudioIntent: LiveActivityIntent, AudioPlaybackIntent {
  static var title: LocalizedStringResource { "Stop audio" }
  static var description: IntentDescription { "Stops audio you started in Salah." }
  static var isDiscoverable: Bool { false }

  func perform() async throws -> some IntentResult {
    _ = try SharedValue<IOSPlaybackSession>.iosPlayback.save(
      nil, reloading: [SalahWidgetConstants.prayerTimesWidgetKind])
    _ = try SharedValue<SalahPlayback>.playback.save(nil)
    DarwinSignal.stopAudio.post()
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
    _ = try SharedValue<SalahSettings>.settings.save(
      preferences.mirror, reloading: [SalahWidgetConstants.prayerTimesWidgetKind])
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
