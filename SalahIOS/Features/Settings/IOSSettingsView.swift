import SalahCore
import SalahTimes
import SwiftUI
import UIKit

/// The settings tab uses the same persisted preferences as schedules, alerts and widgets.
struct IOSSettingsView: View {
  @Environment(IOSAppStore.self) private var store

  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section {
        NavigationLink(value: IOSSettingsDestination.location) {
          IOSSettingsRow(
            title: copy.text("Location", "الموقع"),
            value: store.preferences.location?.name ?? copy.text("Choose a city", "اختر مدينة"),
            symbol: "location.fill")
        }
        .accessibilityIdentifier("settings.location")
      }

      Section {
        NavigationLink(value: IOSSettingsDestination.calculation) {
          IOSSettingsRow(
            title: copy.text("Method", "طريقة الحساب"),
            value: store.preferences.method.title(locale: store.locale), symbol: "function")
        }
        .accessibilityIdentifier("settings.method")

        NavigationLink {
          IOSMadhabSettingsView()
        } label: {
          IOSSettingsRow(
            title: copy.text("Asr (madhab)", "العصر (المذهب)"),
            value: store.preferences.madhab == .hanafi
              ? copy.text("Hanafi", "حنفي") : copy.text("Shafi’i", "شافعي"),
            symbol: "sun.max")
        }
        .accessibilityIdentifier("settings.asr")

        NavigationLink {
          IOSHighLatitudeSettingsView()
        } label: {
          IOSSettingsRow(
            title: copy.text("High latitudes", "خطوط العرض العليا"),
            value: copy.highLatitude(
              store.preferences.automaticHighLatitude
                ? .recommended : store.preferences.highLatitudeRule),
            symbol: "globe")
        }
        .accessibilityIdentifier("settings.highLatitude")

        NavigationLink {
          IOSAdjustmentsSettingsView()
        } label: {
          IOSSettingsRow(
            title: copy.text("Adjustments", "التعديلات"),
            value: store.preferences.adjustments == .zero
              ? copy.text("None", "بلا تعديل") : copy.text("Custom", "مخصص"),
            symbol: "slider.horizontal.3")
        }
        .accessibilityIdentifier("settings.adjustments")
      } header: {
        Text(copy.text("Prayer times", "مواقيت الصلاة"))
      }

      Section {
        NavigationLink(value: IOSSettingsDestination.alerts) {
          IOSSettingsRow(
            title: copy.text("Prayer alerts", "تنبيهات الصلاة"),
            value: copy.text("Per prayer", "لكل صلاة"), symbol: "bell.fill")
        }
        .accessibilityIdentifier("settings.alerts")

        NavigationLink(value: IOSSettingsDestination.sound) {
          IOSSettingsRow(
            title: copy.text("Sound", "الصوت"),
            value: store.preferences.muteSounds
              ? copy.text("Muted", "مكتوم") : copy.text("Sounds on", "مفعّل"),
            symbol: "speaker.wave.2.fill")
        }
        .accessibilityIdentifier("settings.sound")
      } header: {
        Text(copy.text("Alerts", "التنبيهات"))
      }

      Section {
        NavigationLink(value: IOSSettingsDestination.appearance) {
          IOSSettingsRow(
            title: copy.text("Appearance", "المظهر"),
            value: copy.appearance(store.preferences.appearance), symbol: "paintpalette.fill")
        }
        .accessibilityIdentifier("settings.appearance")

        NavigationLink {
          IOSHijriSettingsView()
        } label: {
          IOSSettingsRow(
            title: copy.text("Hijri date", "التاريخ الهجري"),
            value: copy.text("Umm al-Qura", "أم القرى"), symbol: "calendar")
        }
        .accessibilityIdentifier("settings.hijri")

        NavigationLink {
          IOSLanguageSettingsView()
        } label: {
          IOSSettingsRow(
            title: copy.text("Language", "اللغة"), value: languageName, symbol: "globe")
        }
        .accessibilityIdentifier("settings.language")
      } header: {
        Text(copy.text("Display", "العرض"))
      } footer: {
        Text(
          copy.text(
            "Choose Salah’s language, or follow the language set in iPhone Settings.",
            "اختر لغة صلاة، أو اتبع اللغة المحددة في إعدادات iPhone."))
      }

      Section {
        NavigationLink {
          IOSAboutSettingsView()
        } label: {
          IOSSettingsRow(title: copy.text("About Salah", "عن صلاة"), symbol: "info.circle")
        }
        .accessibilityIdentifier("settings.about")
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("Settings", "الإعدادات"))
    .navigationBarTitleDisplayMode(.large)
    .accessibilityIdentifier("settings.form")
  }

  private var languageName: String {
    if store.preferences.language == .system {
      return copy.text("System", "النظام")
    }
    return store.preferences.language.nativeName
  }
}

struct IOSAppearanceSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section(copy.text("Appearance", "المظهر")) {
        ForEach(SalahAppearance.allCases, id: \.self) { appearance in
          IOSSettingsOption(
            title: copy.appearance(appearance), detail: detail(appearance),
            selected: store.preferences.appearance == appearance,
            identifier: "appearance.\(appearance.rawValue)"
          ) {
            store.updatePreferences { $0.appearance = appearance }
          }
        }
      }
      Section {
        Toggle(
          copy.text("Follow time of day", "اتباع وقت اليوم"),
          isOn: store.settingsBinding(\.followsTimeOfDay)
        )
        .accessibilityIdentifier("appearance.followTimeOfDay")
      } footer: {
        Text(
          copy.text(
            "The sky follows the prayer period, from dawn to night. Turn this off for a neutral sky with a gold accent.",
            "تتبع السماء فترة الصلاة من الفجر إلى الليل. عطّل هذا الخيار لسماء محايدة بلمسة ذهبية."))
      }
      Section {
        Text(
          copy.text(
            "Applies to the app and Home Screen widgets. iOS controls tinted and Lock Screen widget colors.",
            "ينطبق على التطبيق وأدوات الشاشة الرئيسية. يتحكم iOS بألوان الأدوات الملونة وأدوات شاشة القفل."
          )
        )
        .font(.footnote)
        .foregroundStyle(IOSTheme.labelSecondary)
        .listRowBackground(Color.clear)
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("Appearance", "المظهر"))
    .navigationBarTitleDisplayMode(.large)
  }

  private func detail(_ appearance: SalahAppearance) -> String {
    switch appearance {
    case .system: copy.text("Follow the device appearance", "اتباع مظهر الجهاز")
    case .light: copy.text("Use light appearance", "استخدام المظهر الفاتح")
    case .dark: copy.text("Use dark appearance", "استخدام المظهر الداكن")
    }
  }
}

struct IOSLanguageSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(\.openURL) private var openURL
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section {
        ForEach(AppLanguage.allCases, id: \.self) { language in
          IOSSettingsOption(
            title: language == .system ? copy.text("System", "النظام") : language.nativeName,
            detail: language == .system
              ? copy.text("Follow iPhone language", "اتباع لغة iPhone")
              : language.translatedName(in: store.locale),
            selected: store.preferences.language == language,
            identifier: "language.\(language.rawValue)"
          ) {
            store.updatePreferences { $0.language = language }
          }
        }
      }
      Section {
        Button {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } label: {
          IOSSettingsRow(
            title: copy.text("Open iPhone Settings", "فتح إعدادات iPhone"),
            symbol: "arrow.up.forward.app")
        }
        .accessibilityIdentifier("language.openSettings")
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("Language", "اللغة"))
    .navigationBarTitleDisplayMode(.large)
  }
}

private struct IOSAboutSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    Form {
      Section {
        LabeledContent(copy.text("Version", "الإصدار"), value: version)
        Text(
          copy.text(
            "Prayer times, Qibla and reminders, calculated on your iPhone. Built on the open Salah Kit prayer-time engine.",
            "مواقيت الصلاة والقبلة والتذكيرات، تُحسب على iPhone. يعتمد على محرك حساب الصلاة المفتوح Salah Kit."
          )
        )
        .foregroundStyle(IOSTheme.labelSecondary)
      }
      Section {
        if let source = URL(string: "https://github.com/salah-kit/Salah") {
          Link(destination: source) {
            IOSSettingsRow(
              title: copy.text("Source and support", "المصدر والدعم"), symbol: "arrow.up.forward")
          }
        }
        if let license = URL(string: "https://github.com/salah-kit/Salah/blob/main/LICENSE") {
          Link(destination: license) {
            IOSSettingsRow(
              title: copy.text("Open source license", "ترخيص المصدر المفتوح"), symbol: "doc.text")
          }
        }
        NavigationLink {
          IOSAudioLicensesSettingsView()
        } label: {
          IOSSettingsRow(title: copy.text("Audio licenses", "تراخيص الصوت"), symbol: "waveform")
        }
        .accessibilityIdentifier("settings.audioLicenses")
        NavigationLink(copy.text("Privacy", "الخصوصية")) {
          Form {
            Text(
              copy.text(
                "Salah stores your selected location, preferences and imported audio on this device. Prayer times are calculated offline. Current location uses Apple’s location services and sends coordinates to Apple’s geocoding service to find your city and time zone. City searches use Apple Maps. Salah has no account, advertising or analytics.",
                "يحفظ تطبيق صلاة موقعك المختار وتفضيلاتك والصوت المستورد على هذا الجهاز. تُحسب المواقيت دون اتصال. يستخدم الموقع الحالي خدمات الموقع من Apple ويرسل الإحداثيات إلى خدمة الترميز الجغرافي من Apple لتحديد المدينة والمنطقة الزمنية. يستخدم البحث عن المدن خرائط Apple. لا توجد حسابات أو إعلانات أو تحليلات في تطبيق صلاة."
              ))
            if let policy = URL(
              string: "https://github.com/salah-kit/Salah/blob/main/docs/privacy.md")
            {
              Link(copy.text("Privacy Policy", "سياسة الخصوصية"), destination: policy)
                .accessibilityIdentifier("settings.privacyPolicy")
            }
          }
          .iosSettingsForm()
          .navigationTitle(copy.text("Privacy", "الخصوصية"))
        }
      }
    }
    .iosSettingsForm()
    .navigationTitle(copy.text("About Salah", "عن صلاة"))
    .navigationBarTitleDisplayMode(.large)
  }

  private var version: String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    return build.isEmpty ? version : "\(version) (\(build))"
  }
}

/// Audio attribution is read verbatim from the NOTICE distributed with the recordings.
private struct IOSAudioLicensesSettingsView: View {
  @Environment(IOSAppStore.self) private var store
  @State private var notice: String?
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if let notice {
          Text(notice)
            .font(.callout)
            .textSelection(.enabled)
            .accessibilityIdentifier("audioLicenses.notice")
        }
        if let credits = URL(string: "https://github.com/salah-kit/Salah/blob/main/NOTICE") {
          Link(
            copy.text("Full audio credits and sources", "اعتمادات الصوت ومصادره الكاملة"),
            destination: credits
          )
          .accessibilityIdentifier("audioLicenses.credits")
        }
        if let license = URL(string: "https://creativecommons.org/licenses/by/4.0/") {
          Link("Creative Commons Attribution 4.0", destination: license)
            .accessibilityIdentifier("audioLicenses.license")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .background(IOSTheme.groupedBackground)
    .tint(IOSTheme.accent)
    .navigationTitle(copy.text("Audio licenses", "تراخيص الصوت"))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      let url =
        Bundle.main.url(forResource: "NOTICE", withExtension: nil, subdirectory: "Audio")
        ?? Bundle.main.url(forResource: "NOTICE", withExtension: nil)
      if let url { notice = try? String(contentsOf: url, encoding: .utf8) }
    }
  }
}
