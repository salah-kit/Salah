import AppIntents
import Foundation
import SalahUI
import SalahWidgets
import SwiftUI
import WidgetKit

struct IOSMuteSoundsControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: IOSControlKind.muteSounds, provider: MuteProvider()) { value in
      ControlWidgetToggle(isOn: value.muted, action: IOSSetMuteSoundsIntent()) {
        Text(verbatim: IOSL10n.text("Mute sounds", arabic: "كتم الأصوات", locale: value.locale))
          .accessibilityHint(
            Text(
              verbatim: IOSL10n.text(
                "Prayer notifications and reminders still arrive.",
                arabic: "ستستمر تنبيهات الصلاة والتذكيرات بالوصول.", locale: value.locale)))
      } valueLabel: { isMuted in
        Label {
          Text(
            verbatim: IOSL10n.text(
              isMuted ? "Muted" : "Sounds on", arabic: isMuted ? "مكتوم" : "الأصوات مفعّلة",
              locale: value.locale))
        } icon: {
          Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
        }
      }
      .tint(SalahPalette(isDark: true).accentFill.color)
    }
    .displayName("Mute sounds")
    .description("Mute Salah sounds while keeping your notifications and reminders enabled.")
  }

  struct Value: Sendable {
    var muted: Bool
    var locale: Locale
  }
  struct MuteProvider: ControlValueProvider {
    var previewValue: Value { .init(muted: false, locale: .current) }
    func currentValue() async throws -> Value {
      let preferences = try IOSSharedPreferencesStore.live.load() ?? IOSPreferences()
      return .init(muted: preferences.muteSounds, locale: preferences.language.locale)
    }
  }
}

struct IOSStopAudioControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: IOSControlKind.stopAudio, provider: PlaybackProvider()) {
      value in
      ControlWidgetButton(action: IOSStopAudioIntent()) {
        Label {
          Text(
            verbatim: IOSL10n.text(
              value.isPlaying ? "Stop audio" : "Nothing playing",
              arabic: value.isPlaying ? "إيقاف الصوت" : "لا يوجد صوت قيد التشغيل",
              locale: value.locale))
        } icon: {
          Image(systemName: "stop.fill")
        }
      }
      .tint(value.isPlaying ? SalahPalette(isDark: true).accentFill.color : Color.secondary)
      .disabled(!value.isPlaying)
    }
    .displayName("Stop audio")
    .description("Stop the audio you started in Salah.")
  }

  struct Value: Sendable {
    var isPlaying: Bool
    var locale: Locale
  }
  struct PlaybackProvider: ControlValueProvider {
    var previewValue: Value { .init(isPlaying: true, locale: .current) }
    func currentValue() async throws -> Value {
      let preferences = try IOSSharedPreferencesStore.live.load() ?? IOSPreferences()
      let isPlaying = SharedValue<IOSPlaybackSession>.iosPlayback.load()?.playing(at: .now) != nil
      return .init(isPlaying: isPlaying, locale: preferences.language.locale)
    }
  }
}
