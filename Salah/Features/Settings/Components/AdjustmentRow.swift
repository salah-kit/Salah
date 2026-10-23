import SwiftUI

/// A prayer's own minutes: its value ("0 min" / "٠ د") and a stepper, a minute at a time.
struct AdjustmentRow: View {
  let label: LocalizedStringKey
  @Binding var value: Int
  /// Whether the row ends its group.
  var isLast = false

  /// "5 min", "-5 min" / "٥ د": the minutes in the language's digits and short unit.
  static func valueText(_ minutes: Int, locale: Locale) -> String {
    String(
      format: localizedString("settings.adj.unit.min", locale: locale), locale: locale,
      minutes.localizedDigits(locale: locale))
  }

  var body: some View {
    LabeledContent(label) {
      HStack(spacing: 12) {
        Text(verbatim: Self.valueText(value, locale: .app))
          .monospacedDigit()
          .foregroundStyle(.primary)
        Stepper(label, value: $value, in: Preferences.adjustmentMinutes)
          .labelsHidden()
      }
    }
    .settingsRow(last: isLast)
  }
}
