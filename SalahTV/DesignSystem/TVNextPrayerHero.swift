import SalahCore
import SwiftUI

/// The next prayer, large, straight on the sky: the eyebrow, the name, when it begins, the
/// countdown and what the adhan will do. It isn't focusable.
struct TVNextPrayerHero: View {
  let presentation: TVPrayerPresentation

  @ScaledMetric(relativeTo: .title) private var countdownSize = TVNumeral.countdown

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 16) {
          if let event = presentation.event {
            TVPrayerGlyph(name: event.glyphName, size: 56, color: TVTheme.accentText)
          }
          Text(verbatim: presentation.eyebrow)
            .font(.callout.bold())
            .foregroundStyle(TVTheme.accentText)
        }
        .padding(.bottom, 6)
        Text(verbatim: presentation.name)
          .font(.title.bold())
          .foregroundStyle(TVTheme.labelPrimary)
        Text(verbatim: presentation.subtitle)
          .font(.headline.weight(.medium))
          .foregroundStyle(TVTheme.labelSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(verbatim: presentation.countdown)
        .font(TVNumeral.font(size: countdownSize))
        .foregroundStyle(presentation.isApproaching ? TVTheme.accentText : TVTheme.labelPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      if let note = presentation.soundNote {
        Label {
          Text(verbatim: note.text)
        } icon: {
          Image(systemName: note.isOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
            .accessibilityHidden(true)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(TVTheme.labelSecondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: TVMetrics.column, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(presentation.heroAccessibility)
    .accessibilityIdentifier("hero")
  }
}

/// The day at the top of Today: the Hijri date, then the Gregorian date and the place.
struct TVDateHeader: View {
  let display: SalahDisplay

  var body: some View {
    let header = display.header
    let hijri = "\(header.hijriDay) \(header.hijriMonth) \(header.hijriYear)"
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: hijri)
        .font(.headline.bold())
        .foregroundStyle(TVTheme.labelPrimary)
      HStack(spacing: 14) {
        Text(verbatim: header.gregorianDate)
          .foregroundStyle(TVTheme.labelSecondary)
        if !header.location.isEmpty {
          Text(verbatim: "·").foregroundStyle(TVTheme.labelTertiary)
          Image(systemName: "location.fill")
            .font(.system(size: 22))
            .foregroundStyle(TVTheme.labelSecondary)
          Text(verbatim: header.location)
            .foregroundStyle(TVTheme.labelSecondary)
        }
      }
      .font(.callout.weight(.medium))
      .lineLimit(1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      [hijri, header.gregorianDate, header.location].filter { !$0.isEmpty }
        .joined(separator: ", ")
    )
    .accessibilityIdentifier("today.date")
  }
}
