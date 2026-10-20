import SwiftUI

/// The dropdown's themed header: the Hijri date (serif) with the Gregorian date
/// beneath, the guiding-light / silent glyph, and the location. Mirrors the
/// widget's (private) full `WidgetHeader` so the menu bar and widget read alike.
struct MenuDropdownHeader: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors

  private var header: SalahHeader { display.header }
  private var silentMode: Bool { display.settings.silentMode }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Image(systemName: silentMode ? "bell.slash.fill" : "moon.stars.fill")
          .font(.subheadline)
          .salahInk((silentMode ? SalahWidgetInk.secondary : .accent).glyph)
          .accessibilityHidden(true)
        Text(verbatim: hijriText)
          .font(.system(.headline, design: .serif, weight: .semibold))
          .salahInk(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Spacer(minLength: 8)
        Label {
          Text(verbatim: header.location).lineLimit(1).privacySensitive()
        } icon: {
          Image(systemName: "location.fill")
        }
        .font(.caption)
        .salahInk(.secondary)
        .labelStyle(.titleAndIcon)
      }
      Text(verbatim: header.gregorianDate)
        .font(.caption2)
        .salahInk(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .accessibilityElement(children: .combine)
  }

  private var hijriText: String {
    "\(header.hijriDay) \(header.hijriMonth) \(header.hijriYear)"
  }
}
