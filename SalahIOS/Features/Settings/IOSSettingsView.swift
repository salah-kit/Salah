import SalahCore
import SalahTimes
import SwiftUI
import UIKit

/// The settings tab uses the same persisted preferences as schedules, alerts and widgets.
struct IOSSettingsView: View {
  @Environment(IOSAppStore.self) private var store

  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    List {
      Section {
        NavigationLink(value: IOSSettingsDestination.location) {
          IOSSettingsCategoryLabel(destination: .location)
        }
        .accessibilityIdentifier("settings.location")
      }

      Section {
        NavigationLink(value: IOSSettingsDestination.calculation) {
          IOSSettingsCategoryLabel(destination: .calculation)
        }
        .accessibilityIdentifier("settings.method")

        NavigationLink(value: IOSSettingsDestination.madhab) {
          IOSSettingsCategoryLabel(destination: .madhab)
        }
        .accessibilityIdentifier("settings.asr")

        NavigationLink(value: IOSSettingsDestination.highLatitude) {
          IOSSettingsCategoryLabel(destination: .highLatitude)
        }
        .accessibilityIdentifier("settings.highLatitude")

        NavigationLink(value: IOSSettingsDestination.adjustments) {
          IOSSettingsCategoryLabel(destination: .adjustments)
        }
        .accessibilityIdentifier("settings.adjustments")
      } header: {
        Text(copy.text("Prayer times", "مواقيت الصلاة"))
      }

      Section {
        NavigationLink(value: IOSSettingsDestination.alerts) {
          IOSSettingsCategoryLabel(destination: .alerts)
        }
        .accessibilityIdentifier("settings.alerts")

        NavigationLink(value: IOSSettingsDestination.sound) {
          IOSSettingsCategoryLabel(destination: .sound)
        }
        .accessibilityIdentifier("settings.sound")
      } header: {
        Text(copy.text("Alerts", "التنبيهات"))
      }

      Section {
        NavigationLink(value: IOSSettingsDestination.appearance) {
          IOSSettingsCategoryLabel(destination: .appearance)
        }
        .accessibilityIdentifier("settings.appearance")

        NavigationLink(value: IOSSettingsDestination.hijri) {
          IOSSettingsCategoryLabel(destination: .hijri)
        }
        .accessibilityIdentifier("settings.hijri")

        NavigationLink(value: IOSSettingsDestination.language) {
          IOSSettingsCategoryLabel(destination: .language)
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
        NavigationLink(value: IOSSettingsDestination.about) {
          IOSSettingsCategoryLabel(destination: .about)
        }
        .accessibilityIdentifier("settings.about")
      }
    }
    .listStyle(.insetGrouped)
    .iosSettingsForm()
    .navigationTitle(copy.text("Settings", "الإعدادات"))
    .navigationBarTitleDisplayMode(.large)
    .accessibilityIdentifier("settings.form")
  }

}

/// The store route owns the selected category in both layouts. Compact widths use a native
/// stack, so popping a nested page never changes a split column or clears the category.
/// Resizing restores the category; nested detail pages return to that category's root.
struct IOSSettingsNavigationView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    @Bindable var store = store
    return Group {
      if horizontalSizeClass == .regular {
        IOSRegularSettingsComposition()
          .onAppear { store.prepareSettingsForRegularWidth() }
      } else {
        NavigationStack(path: $store.settingsPath) {
          IOSSettingsView()
            .navigationDestination(for: IOSSettingsDestination.self) { destination in
              IOSSettingsDestinationView(destination: destination)
            }
        }
      }
    }
  }

}

/// The iPad composition keeps the documented 400 / 682 point content columns at 1210 points.
/// The detail's native navigation and form each inset content by 20 points, so its enclosing
/// frame starts 20 points earlier and is 40 points wider than the visible detail column.
/// On iPhone Duo's inner display, the list and the detail meet the fold from either side.
private struct IOSRegularSettingsComposition: View {
  @Environment(IOSAppStore.self) private var store
  private static let formInset: CGFloat = 20

  var body: some View {
    IOSDisplayGeometryReader { geometry in
      if let pages = geometry.pages, pages.axis == .vertical {
        let detailStart = pages.second.lowerBound - Self.formInset
        HStack(alignment: .top, spacing: detailStart - pages.first.upperBound) {
          IOSRegularSettingsMaster(topPadding: max(8, geometry.topMargin))
            .frame(width: pages.first.length)
          detail
            .frame(width: geometry.size.width - detailStart)
        }
        .padding(.leading, pages.first.lowerBound)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        // Inner portrait on iPhone Duo keeps the system's margins, its tab bar is at the bottom,
        // and the fold crosses both lists, which may scroll through it.
        let tablet = geometry.fold == nil
        let leading = tablet ? 48 : geometry.insets.leading
        let trailing = tablet ? 28 : max(0, geometry.insets.trailing - Self.formInset)
        let masterWidth = min(400, max(280, (geometry.size.width - 96) * 400 / 1_114))
        let detailWidth = max(0, geometry.size.width - masterWidth - leading - trailing - 12)
        HStack(alignment: .top, spacing: 12) {
          // On a tablet this column has no navigation bar to reserve the floating tab bar's height.
          IOSRegularSettingsMaster(topPadding: tablet ? 72 : max(8, geometry.topMargin))
            .frame(width: masterWidth)
          detail
            .frame(width: detailWidth)
        }
        .padding(.leading, leading)
        .padding(.trailing, trailing)
        .frame(maxHeight: .infinity, alignment: .top)
      }
    }
    .background(IOSTheme.groupedBackground.ignoresSafeArea())
  }

  private var detail: some View {
    NavigationStack {
      IOSSettingsDestinationView(destination: store.selectedSettingsDestination ?? .calculation)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
    .id(store.selectedSettingsDestination ?? .calculation)
    .id(store.settingsNavigationRequestID)
  }
}

private struct IOSRegularSettingsMaster: View {
  let topPadding: CGFloat
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(copy.text("Settings", "الإعدادات"))
          .font(.largeTitle.bold())
          .frame(minHeight: 41, alignment: .leading)
          .accessibilityAddTraits(.isHeader)
        card([.location])
        section(
          copy.text("Prayer times", "مواقيت الصلاة"),
          [.calculation, .madhab, .highLatitude, .adjustments])
        section(copy.text("Alerts", "التنبيهات"), [.alerts, .sound])
        section(copy.text("Display", "العرض"), [.appearance, .hijri, .language])
        card([.about])
      }
      .padding(.top, topPadding)
      .padding(.bottom, 24)
    }
    .scrollIndicators(.hidden)
    .accessibilityIdentifier("settings.form")
  }

  private func section(_ title: String, _ destinations: [IOSSettingsDestination]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.footnote)
        .foregroundStyle(IOSTheme.labelSecondary)
        .padding(.horizontal, 16)
        .frame(minHeight: 26, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
      card(destinations)
    }
  }

  private func card(_ destinations: [IOSSettingsDestination]) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(destinations.enumerated()), id: \.element) { index, destination in
        Button {
          store.selectedSettingsDestination = destination
        } label: {
          HStack(spacing: 12) {
            IOSSettingsCategoryLabel(destination: destination)
            Image(systemName: "chevron.forward")
              .font(.body.weight(.semibold))
              .foregroundStyle(IOSTheme.labelTertiary)
              .accessibilityHidden(true)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 11)
          .frame(minHeight: 52)
          .contentShape(Rectangle())
          .background(
            store.selectedSettingsDestination == destination
              ? IOSTheme.accentSubtle : IOSTheme.groupedSecondary)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
          if index < destinations.count - 1 {
            Divider().padding(.leading, 50)
          }
        }
        .accessibilityIdentifier(destination.settingsIdentifier)
        .accessibilityAddTraits(
          store.selectedSettingsDestination == destination ? [.isSelected] : [])
      }
    }
    .background(IOSTheme.groupedSecondary)
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
  }
}

/// Both layouts read identical labels and values from the same preference owner.
private struct IOSSettingsCategoryLabel: View {
  let destination: IOSSettingsDestination
  @Environment(IOSAppStore.self) private var store
  private var copy: IOSSettingsCopy { IOSSettingsCopy(locale: store.locale) }

  var body: some View { IOSSettingsRow(title: title, value: value, symbol: symbol) }

  private var title: String {
    switch destination {
    case .location: copy.text("Location", "الموقع")
    case .calculation: copy.text("Method", "طريقة الحساب")
    case .madhab: copy.text("Asr (madhab)", "العصر (المذهب)")
    case .highLatitude: copy.text("High latitudes", "خطوط العرض العليا")
    case .adjustments: copy.text("Adjustments", "التعديلات")
    case .alerts: copy.text("Prayer alerts", "تنبيهات الصلاة")
    case .sound: copy.text("Sound", "الصوت")
    case .appearance: copy.text("Appearance", "المظهر")
    case .hijri: copy.text("Hijri date", "التاريخ الهجري")
    case .language: copy.text("Language", "اللغة")
    case .about: copy.text("About Salah", "عن صلاة")
    }
  }

  private var value: String? {
    switch destination {
    case .location:
      store.preferences.location?.name ?? copy.text("Choose a city", "اختر مدينة")
    case .calculation: store.preferences.method.title(locale: store.locale)
    case .madhab:
      store.preferences.madhab == .hanafi
        ? copy.text("Hanafi", "حنفي") : copy.text("Shafi’i", "شافعي")
    case .highLatitude:
      copy.highLatitude(
        store.preferences.automaticHighLatitude ? .recommended : store.preferences.highLatitudeRule)
    case .adjustments:
      store.preferences.adjustments == .zero
        ? copy.text("None", "بلا تعديل") : copy.text("Custom", "مخصص")
    case .alerts: copy.text("Per prayer", "لكل صلاة")
    case .sound:
      store.preferences.muteSounds ? copy.text("Muted", "مكتوم") : copy.text("Sounds on", "مفعّل")
    case .appearance: copy.appearance(store.preferences.appearance)
    case .hijri: copy.text("Umm al-Qura", "أم القرى")
    case .language:
      store.preferences.language == .system
        ? copy.text("System", "النظام") : store.preferences.language.nativeName
    case .about: nil
    }
  }

  private var symbol: String {
    switch destination {
    case .location: "location.fill"
    case .calculation: "function"
    case .madhab: "sun.max"
    case .highLatitude: "globe"
    case .adjustments: "slider.horizontal.3"
    case .alerts: "bell.fill"
    case .sound: "speaker.wave.2.fill"
    case .appearance: "paintpalette.fill"
    case .hijri: "calendar"
    case .language: "globe"
    case .about: "info.circle"
    }
  }
}

extension IOSSettingsDestination {
  fileprivate var settingsIdentifier: String {
    switch self {
    case .madhab: "settings.asr"
    case .calculation: "settings.method"
    default: "settings.\(rawValue)"
    }
  }
}

private struct IOSSettingsDestinationView: View {
  let destination: IOSSettingsDestination

  var body: some View {
    switch destination {
    case .location: IOSLocationSettingsView()
    case .calculation: IOSCalculationSettingsView()
    case .madhab: IOSMadhabSettingsView()
    case .highLatitude: IOSHighLatitudeSettingsView()
    case .adjustments: IOSAdjustmentsSettingsView()
    case .alerts: IOSPrayerAlertsSettingsView()
    case .sound: IOSSoundSettingsView()
    case .appearance: IOSAppearanceSettingsView()
    case .hijri: IOSHijriSettingsView()
    case .language: IOSLanguageSettingsView()
    case .about: IOSAboutSettingsView()
    }
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
              : translatedName(language),
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

  private func translatedName(_ language: AppLanguage) -> String {
    guard let code = language.languageCode else { return language.nativeName }
    let resolved = store.locale.localizedString(forLanguageCode: code) ?? code
    return resolved.prefix(1).uppercased() + resolved.dropFirst()
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
