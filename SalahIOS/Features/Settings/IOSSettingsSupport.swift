import SalahCore
import SalahTimes
import SwiftUI

/// Settings copy follows the app's selected language, including changes made while a page is open.
struct IOSSettingsCopy {
  let locale: Locale
  var isArabic: Bool { locale.language.languageCode?.identifier == "ar" }

  func text(_ english: String, _ arabic: String) -> String {
    IOSL10n.text(english, arabic: arabic, locale: locale)
  }

  func format(_ english: String, _ arabic: String, _ arguments: CVarArg...) -> String {
    String(format: text(english, arabic), locale: locale, arguments: arguments)
  }

  func number(_ value: Int) -> String {
    value.formatted(.number.locale(locale))
  }

  func number(_ value: Double) -> String {
    value.formatted(
      .number.precision(.fractionLength(0...1))
        .locale(locale))
  }

  func minutes(_ value: Int) -> String {
    format("%@ min", "%@ د", number(value))
  }

  func signedMinutes(_ value: Int) -> String {
    let sign = value > 0 ? "+" : value < 0 ? "−" : ""
    return format("%@ min", "%@ د", sign + number(abs(value)))
  }

  func prayer(_ kind: PrayerKind) -> String {
    switch kind {
    case .fajr: text("Fajr", "الفجر")
    case .sunrise: text("Sunrise", "الشروق")
    case .dhuhr: text("Dhuhr", "الظهر")
    case .asr: text("Asr", "العصر")
    case .maghrib: text("Maghrib", "المغرب")
    case .isha: text("Isha", "العشاء")
    }
  }

  func sound(_ sound: IOSSound) -> String {
    if case .custom = sound { return text("Custom sound", "صوت مخصص") }
    return sound.title(locale: locale)
  }

  func appearance(_ appearance: SalahAppearance) -> String {
    switch appearance {
    case .system: text("System", "النظام")
    case .light: text("Light", "فاتح")
    case .dark: text("Dark", "داكن")
    }
  }

  func highLatitude(_ rule: HighLatitudeRule) -> String {
    switch rule {
    case .recommended: text("Recommended", "الموصى به")
    case .middleOfTheNight: text("Middle of the night", "منتصف الليل")
    case .seventhOfTheNight: text("Seventh of the night", "سُبع الليل")
    case .twilightAngle: text("Twilight angle", "زاوية الشفق")
    case .disabled: text("No adjustment", "بلا تعديل")
    }
  }
}

extension IOSAppStore {
  func settingsBinding<Value>(_ keyPath: WritableKeyPath<IOSPreferences, Value>) -> Binding<Value> {
    Binding(
      get: { self.preferences[keyPath: keyPath] },
      set: { value in self.updatePreferences { $0[keyPath: keyPath] = value } })
  }
}

/// Native list rows keep their layout readable at the accessibility text sizes.
struct IOSSettingsRow: View {
  let title: String
  var value: String? = nil
  var subtitle: String? = nil
  var symbol: String? = nil
  var prayer: PrayerKind? = nil
  var jumuah = false

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(spacing: 12) {
      if let symbol {
        Image(systemName: symbol)
          .font(.body)
          .foregroundStyle(IOSTheme.accent)
          .frame(width: 22)
          .accessibilityHidden(true)
      } else if let prayer {
        Image("salah.\(jumuah ? "jumuah" : prayer.rawValue)")
          .symbolRenderingMode(.hierarchical)
          .font(.body)
          .frame(width: 22)
          .accessibilityHidden(true)
      }
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          titleAndSubtitle
          if let value, !value.isEmpty {
            Text(value).foregroundStyle(IOSTheme.labelSecondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        titleAndSubtitle
          .frame(maxWidth: .infinity, alignment: .leading)
        if let value, !value.isEmpty {
          Text(value)
            .foregroundStyle(IOSTheme.labelSecondary)
            .multilineTextAlignment(.trailing)
            .layoutPriority(1)
        }
      }
    }
    .foregroundStyle(.primary)
    .frame(minHeight: subtitle == nil ? 22 : 43)
  }

  private var titleAndSubtitle: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.body)
      if let subtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(.footnote)
          .foregroundStyle(IOSTheme.labelSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

struct IOSSettingsOption: View {
  let title: String
  var detail: String? = nil
  let selected: Bool
  var identifier: String? = nil
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        IOSSettingsRow(title: title, subtitle: detail)
        if selected {
          Image(systemName: "checkmark")
            .foregroundStyle(IOSTheme.accent)
            .accessibilityHidden(true)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16))
    .accessibilityAddTraits(selected ? [.isSelected] : [])
    .accessibilityIdentifier(identifier ?? title)
  }
}

struct IOSSettingsFormStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(IOSTheme.groupedBackground)
      .tint(IOSTheme.accent)
      .environment(\.defaultMinListRowHeight, 52)
      .listSectionSpacing(20)
      .textCase(nil)
  }
}

extension View {
  func iosSettingsForm() -> some View { modifier(IOSSettingsFormStyle()) }
}

extension PrayerAdjustments {
  func settingsMinutes(for kind: PrayerKind) -> Int {
    switch kind {
    case .fajr: fajr
    case .sunrise: sunrise
    case .dhuhr: dhuhr
    case .asr: asr
    case .maghrib: maghrib
    case .isha: isha
    }
  }

  mutating func setSettingsMinutes(_ value: Int, for kind: PrayerKind) {
    switch kind {
    case .fajr: fajr = value
    case .sunrise: sunrise = value
    case .dhuhr: dhuhr = value
    case .asr: asr = value
    case .maghrib: maghrib = value
    case .isha: isha = value
    }
  }
}
