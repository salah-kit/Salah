import SalahCalculation
import SalahTimes
import SwiftUI

struct AdjustmentsContent: View {
  @Bindable var prefs = Preferences.shared

  /// "Isha 120 min after Maghrib, for Umm al-Qura": the Ramadan switch's detail, with the
  /// minutes in the language's digits and plural, and the method that delays Isha.
  static func delayedIshaDetail(method: MethodPreference, locale: Locale) -> String {
    let minutes = CalculationChoices.ramadanIshaMinutes
    let name = localizedString(dynamicKey: method.titleKey, locale: locale)
    return String(
      localized: LocalizedStringResource(
        "settings.adj.delayedIsha.detail",
        defaultValue: "Isha \(minutes) min after Maghrib, for \(name)", locale: locale,
        bundle: AppResources.localizationBundle))
  }

  var body: some View {
    Section {
      LabeledContent("settings.adj.hijriOffset") {
        HStack(spacing: 12) {
          Text(verbatim: prefs.hijriOffset.localizedDigits())
            .monospacedDigit()
            .foregroundStyle(.primary)
          Stepper("settings.adj.hijriOffset", value: $prefs.hijriOffset, in: -3...3)
            .labelsHidden()
        }
      }
      .settingsRow(last: true)
    } header: {
      SettingsHeader("settings.adj.hijriHeader", isFirst: true)
    }

    if prefs.calculationChoices.offersDelayedIsha {
      Section {
        Toggle(isOn: $prefs.delayedIshaInRamadan) {
          Text("settings.adj.delayedIsha")
          Text(verbatim: Self.delayedIshaDetail(method: prefs.methodPreference, locale: .app))
        }
        .settingsRow(detail: true, last: true)
      } header: {
        SettingsHeader("settings.adj.ramadan")
      }
    }

    Section {
      AdjustmentRow(label: "prayer.fajr", value: $prefs.fajrAdjustment)
      AdjustmentRow(label: "prayer.sunrise", value: $prefs.shuruqAdjustment)
      AdjustmentRow(label: "prayer.dhuhr", value: $prefs.dhuhrAdjustment)
      AdjustmentRow(label: "prayer.asr", value: $prefs.asrAdjustment)
      AdjustmentRow(label: "prayer.maghrib", value: $prefs.maghribAdjustment)
      AdjustmentRow(label: "prayer.isha", value: $prefs.ishaAdjustment, isLast: true)
    } header: {
      SettingsHeader("settings.adj.offsetsHeader")
    } footer: {
      SettingsFooter("settings.adj.offsetsFooter")
    }
  }
}
