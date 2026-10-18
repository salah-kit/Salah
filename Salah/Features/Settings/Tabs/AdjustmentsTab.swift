import SalahCalculation
import SalahTimes
import SwiftUI

struct AdjustmentsContent: View {
  @Bindable var prefs = Preferences.shared

  /// The footer of the Ramadan Isha switch, with its 120 minutes in the language's digits.
  static func delayedIshaFooter(locale: Locale) -> String {
    String(
      format: localizedString("settings.adj.delayedIsha.footer", locale: locale), locale: locale,
      120.localizedDigits(locale: locale).bidiIsolated)
  }

  var body: some View {
    Section("settings.adj.hijriHeader") {
      Stepper(
        value: $prefs.hijriOffset,
        in: -3...3
      ) {
        Text(
          String(
            format: localizedString("settings.adj.dateOffset", locale: .app),
            locale: .app,
            prefs.hijriOffset.localizedDigits().bidiIsolated
          )
        )
      }
    }

    if hasIntervalIsha {
      Section {
        Toggle("settings.adj.delayedIsha", isOn: $prefs.delayedIshaInRamadan)
      } header: {
        Text("settings.adj.ramadan")
      } footer: {
        Text(verbatim: Self.delayedIshaFooter(locale: .app))
      }
    }

    Section {
      AdjustmentRow(label: "prayer.fajr", value: $prefs.fajrAdjustment)
      AdjustmentRow(label: "prayer.sunrise", value: $prefs.shuruqAdjustment)
      AdjustmentRow(label: "prayer.dhuhr", value: $prefs.dhuhrAdjustment)
      AdjustmentRow(label: "prayer.asr", value: $prefs.asrAdjustment)
      AdjustmentRow(label: "prayer.maghrib", value: $prefs.maghribAdjustment)
      AdjustmentRow(label: "prayer.isha", value: $prefs.ishaAdjustment)
    } header: {
      Text("settings.adj.offsetsHeader")
    } footer: {
      Text("settings.adj.offsetsFooter")
    }
  }

  /// Whether the method's Isha is an interval after Maghrib, the only kind the
  /// Ramadan delay changes.
  private var hasIntervalIsha: Bool {
    let isha = prefs.calculationChoices.calculationSettings.parameters.isha
    if case .minutesAfterMaghrib(let minutes) = isha { return minutes > 0 }
    return false
  }
}
