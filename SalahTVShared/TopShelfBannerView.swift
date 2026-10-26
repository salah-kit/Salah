import SalahCore
import SalahUI
import SwiftUI
import UIKit

/// A Top Shelf banner as an image: 1940 × 692 pt, with everything inside the 1740 × 560 pt
/// the system shows unfocused, because focus crops it to 1740 × 620.
struct TopShelfBannerView: View {
  static let size = CGSize(width: 1940, height: 692)

  let banner: TopShelfBanner
  let snapshot: TopShelfSnapshot

  private var colors: SalahColors {
    SalahColors(
      phase: snapshot.phase(of: banner), scheme: snapshot.isDark ? .dark : .light,
      contrast: .standard)
  }

  var body: some View {
    let colors = colors
    ZStack {
      colors.sky
      content(colors)
        .frame(width: 1640, height: 460, alignment: .leading)
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .environment(\.colorScheme, snapshot.isDark ? .dark : .light)
    .environment(\.locale, snapshot.display.locale)
    .environment(\.layoutDirection, snapshot.display.isRightToLeft ? .rightToLeft : .leftToRight)
  }

  @ViewBuilder
  private func content(_ colors: SalahColors) -> some View {
    switch banner {
    case .nextPrayer:
      HStack(spacing: 0) {
        lead(colors, glyph: snapshot.nextPrayer?.glyphName ?? "salah.dhuhr")
        Spacer(minLength: 40)
        dayPanel(colors)
      }
    case .today:
      VStack(alignment: .leading, spacing: 26) {
        words(colors)
        if let day = snapshot.display.listedDay {
          TVDayRibbon(
            day: day, date: snapshot.display.date,
            followsTimeOfDay: snapshot.display.settings.followsTimeOfDay, barHeight: 31,
            knobSize: 72, knobStroke: 10)
        }
        todayTimes(colors)
      }
    case .roomDisplay:
      HStack(alignment: .center, spacing: 48) {
        TVPrayerGlyph(name: "salah.isha", size: 168, color: colors.phase.tint.color)
        VStack(alignment: .leading, spacing: 8) {
          eyebrowAndTitle(colors)
          Text(verbatim: snapshot.roomDisplayNote)
            .font(.system(size: 31, weight: .medium))
            .foregroundStyle(colors.palette.labelSecondary.color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
          roomBoard(colors).padding(.top, 24)
        }
      }
    }
  }

  private func lead(_ colors: SalahColors, glyph: String) -> some View {
    HStack(spacing: 48) {
      TVPrayerGlyph(name: glyph, size: 168, color: colors.phase.tint.color)
      words(colors)
    }
  }

  private func words(_ colors: SalahColors) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      eyebrowAndTitle(colors)
      Text(verbatim: snapshot.dateLine(of: banner))
        .font(.system(size: 31, weight: .medium))
        .foregroundStyle(colors.palette.labelSecondary.color)
        .lineLimit(1)
    }
  }

  private func eyebrowAndTitle(_ colors: SalahColors) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: snapshot.eyebrow(of: banner))
        .font(.system(size: 38, weight: .bold))
        .foregroundStyle(colors.phase.text.color)
        .lineLimit(1)
      Text(verbatim: snapshot.title(of: banner))
        .font(.system(size: 96, weight: .bold))
        .foregroundStyle(colors.palette.labelPrimary.color)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
  }

  /// The day's six times beside the next prayer, the next one in gold. After Isha they're
  /// tomorrow's.
  private func dayPanel(_ colors: SalahColors) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(snapshot.slots(of: banner)) { slot in
        let next = isNext(slot)
        HStack {
          Text(verbatim: snapshot.name(of: slot))
          Spacer(minLength: 24)
          Text(verbatim: time(of: slot))
        }
        .font(.system(size: 31, weight: next ? .bold : .medium))
        .foregroundStyle(
          next ? colors.palette.accentText.color : colors.palette.labelPrimary.color
        )
        .frame(width: 380)
      }
    }
    .padding(.horizontal, 36)
    .padding(.vertical, 28)
    .background(colors.palette.fillQuaternary.color, in: .rect(cornerRadius: 36))
  }

  private func todayTimes(_ colors: SalahColors) -> some View {
    HStack(alignment: .top) {
      ForEach(Array(snapshot.slots(of: banner).enumerated()), id: \.element.id) { index, slot in
        if index > 0 { Spacer(minLength: 16) }
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: snapshot.name(of: slot))
            .font(.system(size: 25, weight: .bold))
            .foregroundStyle(colors.palette.labelSecondary.color)
          Text(verbatim: time(of: slot))
            .font(.system(size: 31, weight: .bold))
            .foregroundStyle(
              isNext(slot) ? colors.palette.accentText.color : colors.palette.labelPrimary.color)
        }
        .lineLimit(1)
      }
    }
    .frame(width: 1640)
  }

  /// The five prayers' times, sunrise left out, as the room display shows them.
  private func roomBoard(_ colors: SalahColors) -> some View {
    HStack(alignment: .top, spacing: 14) {
      ForEach(snapshot.slots(of: banner)) { slot in
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: snapshot.name(of: slot))
            .font(.system(size: 25, weight: .bold))
          Text(verbatim: time(of: slot, clock: true))
            .font(.system(size: 31, weight: .bold))
            .monospacedDigit()
        }
        .lineLimit(1)
        .foregroundStyle(colors.palette.labelPrimary.color)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(colors.palette.fillQuaternary.color, in: .rect(cornerRadius: 22))
      }
    }
  }

  private func isNext(_ slot: SalahDisplay.Slot) -> Bool {
    guard case .event(let event) = slot else { return false }
    return event.id == snapshot.nextPrayer?.id
  }

  /// A slot's time, without its day period on the room board, or a dash when it's missing.
  private func time(of slot: SalahDisplay.Slot, clock: Bool = false) -> String {
    guard case .event(let event) = slot else { return TopShelfSnapshot.missingTime }
    return clock ? snapshot.time.clock(event.time) : snapshot.time.time(event.time)
  }
}

/// Draws the banners into images the system can show.
nonisolated enum TopShelfImages {
  /// A banner as PNG data at a screen scale: 1940 × 692 pixels at 1x, twice that at 2x.
  @MainActor
  static func png(of banner: TopShelfBanner, snapshot: TopShelfSnapshot, scale: CGFloat) -> Data? {
    let renderer = ImageRenderer(content: TopShelfBannerView(banner: banner, snapshot: snapshot))
    renderer.scale = scale
    renderer.isOpaque = true
    renderer.proposedSize = ProposedViewSize(TopShelfBannerView.size)
    return renderer.uiImage?.pngData()
  }
}
