import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct IOSSoundSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(IOSAudioService.self) private var audio
  @Environment(\.openURL) private var openURL
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section {
        Toggle(copy.text("Mute sounds", "كتم الأصوات"), isOn: store.settingsBinding(\.muteSounds))
          .accessibilityIdentifier("sound.mute")
      } header: {
        Text(copy.text("All alerts", "جميع التنبيهات"))
      } footer: {
        Text(
          copy.text(
            "Notifications and reminders still arrive when sounds are muted.",
            "تستمر الإشعارات والتذكيرات عند كتم الأصوات."))
      }
      Section {
        Toggle(
          copy.text("Du’a after adhan", "الدعاء بعد الأذان"),
          isOn: store.settingsBinding(\.duaEnabled)
        )
        .accessibilityIdentifier("sound.dua")
        Stepper(value: store.settingsBinding(\.playbackVolume), in: 0...1, step: 0.05) {
          IOSSettingsRow(
            title: copy.text("Playback volume", "مستوى صوت التشغيل"),
            subtitle: store.preferences.playbackVolume.formatted(
              .percent.precision(.fractionLength(0)).locale(store.locale)))
        }
        .accessibilityIdentifier("sound.volume")
        .listRowInsets(EdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16))
        .accessibilityValue(
          store.preferences.playbackVolume.formatted(.percent.locale(store.locale)))
      } header: {
        Text(copy.text("Playback in Salah", "التشغيل في صلاة"))
      } footer: {
        Text(
          copy.text(
            "Start the full adhan in Salah. Playback continues when the app is in the background. Du’a and playback volume apply to this audio.",
            "ابدأ تشغيل الأذان كاملًا في تطبيق صلاة. يستمر التشغيل عندما يكون التطبيق في الخلفية. ينطبق الدعاء ومستوى صوت التشغيل على هذا الصوت."
          ))
      }
      .disabled(store.preferences.muteSounds)
      Section {
        Button {
          if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        } label: {
          HStack {
            IOSSettingsRow(
              title: copy.text("Open Settings", "فتح الإعدادات"),
              subtitle: copy.text("Salah notification settings", "إعدادات إشعارات صلاة"))
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(IOSTheme.labelTertiary)
              .accessibilityHidden(true)
          }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sound.openSettings")
        .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
      } header: {
        Text(copy.text("Notification sounds", "أصوات الإشعارات"))
      } footer: {
        Text(
          copy.text(
            "iPhone settings control alert volume, Silent mode and Focus.",
            "تتحكم إعدادات iPhone بمستوى صوت التنبيه والوضع الصامت والتركيز."))
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("Sound", "الصوت"))
    .navigationBarTitleDisplayMode(.large)
    .accessibilityIdentifier("sound.form")
    .onChange(of: store.preferences.muteSounds) { _, muted in if muted { audio.stop() } }
    .onChange(of: store.preferences.playbackVolume) { _, volume in audio.setVolume(volume) }
  }
}

struct IOSNotificationSoundSettingsView: View {
  @Binding var sound: IOSSound
  let context: String
  @Environment(IOSAppStore.self) private var store
  @Environment(IOSAudioService.self) private var audio
  @State private var showImporter = false
  @State private var importing = false
  @State private var importError: String?
  @State private var lastCustomSound: IOSSound?
  @State private var previewed = false
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section {
        ForEach(IOSSound.builtIn, id: \.self) { option in
          IOSSettingsOption(
            title: copy.sound(option),
            detail: option == .none
              ? copy.text("Notification without sound", "إشعار بلا صوت") : nil,
            selected: sound == option, identifier: optionIdentifier(option)
          ) {
            rememberCustomSound()
            sound = option
            if previewed { audio.stop() }
          }
        }
        if let custom = customSound {
          IOSSettingsOption(
            title: copy.text("Custom sound", "صوت مخصص"),
            detail: copy.text("Imported audio", "صوت مستورد"),
            selected: sound == custom, identifier: "sound.option.custom"
          ) {
            sound = custom
            if previewed { audio.stop() }
          }
        }
      } header: {
        Text(context)
      } footer: {
        Text(
          copy.text(
            "Your choice applies to this alert only. Reminders have their own sounds.",
            "ينطبق اختيارك على هذا التنبيه فقط. للتذكيرات أصواتها الخاصة."))
      }
      .disabled(store.preferences.muteSounds || importing)
      Section(copy.text("Preview", "المعاينة")) {
        Button {
          if isPreviewing {
            audio.stop()
          } else {
            previewed = true
            audio.preview(sound, volume: store.preferences.playbackVolume)
          }
        } label: {
          IOSSettingsRow(
            title: isPreviewing
              ? copy.text("Stop preview", "إيقاف المعاينة")
              : copy.format("Preview %@", "معاينة %@", copy.sound(sound)))
        }
        .disabled(sound == .none || store.preferences.muteSounds || importing)
        .accessibilityIdentifier("sound.preview")
        if previewed, let message = audio.errorMessage {
          Text(IOSL10n.text(message, locale: store.locale))
            .font(.footnote)
            .foregroundStyle(IOSTheme.labelSecondary)
            .accessibilityIdentifier("sound.previewError")
        }
      }
      Section {
        Button {
          showImporter = true
        } label: {
          HStack {
            IOSSettingsRow(title: copy.text("Choose audio file", "اختيار ملف صوتي"))
            if importing {
              ProgressView()
            } else {
              Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(IOSTheme.labelTertiary)
                .accessibilityHidden(true)
            }
          }
        }
        .disabled(importing || store.preferences.muteSounds)
        .accessibilityIdentifier("sound.import")
      } header: {
        Text(copy.text("Custom sound", "صوت مخصص"))
      } footer: {
        Text(
          copy.text(
            "Notifications use a prepared clip under 30 seconds. The full recording can play inside Salah.",
            "تستخدم الإشعارات مقطعًا معدًا أقل من ٣٠ ثانية. يمكن تشغيل التسجيل الكامل داخل تطبيق صلاة."
          ))
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("Notification sound", "صوت الإشعار"))
    .navigationBarTitleDisplayMode(.large)
    .accessibilityIdentifier("sound.picker")
    .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
      switch result {
      case .success(let url):
        importing = true
        Task {
          do {
            let imported = try await audio.importAudio(from: url)
            lastCustomSound = imported
            sound = imported
          } catch {
            importError =
              (error as? IOSAudioImportError)?.errorDescription
              ?? "This audio file could not be opened. Choose another file."
          }
          importing = false
        }
      case .failure:
        importError = "This audio file could not be opened. Choose another file."
      }
    }
    .alert(
      copy.text("Could not import audio", "تعذر استيراد الصوت"), isPresented: showingImportError
    ) {
      Button(copy.text("OK", "موافق"), role: .cancel) { importError = nil }
    } message: {
      Text(IOSL10n.text(importError ?? "", locale: store.locale))
    }
    .onAppear { rememberCustomSound() }
    .onDisappear { if previewed { audio.stop() } }
    .onChange(of: store.preferences.muteSounds) { _, muted in if muted { audio.stop() } }
  }

  private var showingImportError: Binding<Bool> {
    Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
  }

  private var customSound: IOSSound? {
    if case .custom = sound { return sound }
    return lastCustomSound
  }

  private var isPreviewing: Bool { previewed && audio.isPlaying && audio.currentSound == sound }

  private func rememberCustomSound() {
    if case .custom = sound { lastCustomSound = sound }
  }

  private func optionIdentifier(_ sound: IOSSound) -> String {
    switch sound {
    case .adhan: "sound.option.adhan"
    case .fajrAdhan: "sound.option.fajrAdhan"
    case .system: "sound.option.system"
    case .none: "sound.option.none"
    case .softTone: "sound.option.softTone"
    case .custom: "sound.option.custom"
    }
  }
}
