import SalahCore
import SwiftUI

/// One prayer on the room display: a 260 pt column of the HIG's six-column grid. The panel
/// is a plain translucent fill, not glass, because the board is content. Nothing on the
/// board takes focus.
struct TVBoardCell: View {
  let event: PrayerEvent
  let presentation: TVPrayerPresentation

  @ScaledMetric(relativeTo: .title2) private var timeSize = TVNumeral.boardTime
  /// The design's 404 pt, scaled like the time. The board row is as tall as its tallest
  /// cell, so larger text grows every cell instead of clipping one.
  @ScaledMetric(relativeTo: .title2) private var height: CGFloat = 404

  var body: some View {
    let status = presentation.status(of: event)
    let isNext = Self.isNext(status)
    let isPassed = status == .passed
    let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
    VStack(alignment: .leading, spacing: 6) {
      TVPrayerGlyph(
        name: event.glyphName, size: 52,
        color: isNext
          ? TVTheme.accentText : (isPassed ? TVTheme.labelTertiary : TVTheme.labelSecondary))
      Text(verbatim: presentation.display.name(of: event))
        .font(.title3.weight(.medium))
        .foregroundStyle(isPassed ? TVTheme.labelSecondary : TVTheme.labelPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(verbatim: presentation.time.clock(event.time))
          .font(TVNumeral.font(size: timeSize))
        if let period = presentation.time.period(event.time) {
          Text(verbatim: period).font(.callout.weight(.medium))
        }
      }
      .foregroundStyle(
        isNext ? TVTheme.accentText : (isPassed ? TVTheme.labelSecondary : TVTheme.labelPrimary)
      )
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      if let iqama = event.iqama {
        VStack(alignment: .leading, spacing: 0) {
          Text(verbatim: presentation.copy("Iqama", "الإقامة"))
            .font(.caption.weight(.medium))
            .foregroundStyle(TVTheme.labelSecondary)
          Text(verbatim: presentation.time.time(iqama))
            .font(.callout.bold())
            .foregroundStyle(isPassed ? TVTheme.labelSecondary : TVTheme.labelPrimary)
        }
        .padding(.top, 10)
      }
      if let chip = presentation.chip(for: event) {
        Text(verbatim: chip)
          .font(.callout.bold())
          .foregroundStyle(TVTheme.labelOnAccent)
          .padding(.horizontal, 16)
          .padding(.vertical, 4)
          .background(TVTheme.accentFill, in: Capsule())
          .padding(.top, 12)
      }
      Spacer(minLength: 0)
    }
    .padding(.top, 28)
    .padding(.bottom, 24)
    .padding(.horizontal, 24)
    .frame(width: TVMetrics.boardColumn, alignment: .leading)
    .frame(minHeight: height, maxHeight: .infinity, alignment: .top)
    .background(isNext ? TVTheme.accentSubtle : TVTheme.fillQuaternary, in: shape)
    .overlay {
      if isNext { shape.strokeBorder(TVTheme.accentStroke, lineWidth: 3) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(presentation.rowAccessibility(for: event))
    .accessibilityIdentifier("room.cell.\(event.kind.rawValue)")
  }

  private static func isNext(_ status: PrayerEventStatus) -> Bool {
    switch status {
    case .next, .justStarted: true
    case .passed, .upcoming: false
    }
  }
}
