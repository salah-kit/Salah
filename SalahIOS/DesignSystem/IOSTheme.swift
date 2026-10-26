import Foundation
import SalahUI
import SwiftUI

/// The iPhone and iPad's semantic colors, mirrored from `Design/tokens`.
/// Asset variants follow both appearance and Increase Contrast.
enum IOSTheme {
  static let labelPrimary = Color("IOSLabelPrimary")
  static let labelSecondary = Color("IOSLabelSecondary")
  static let labelTertiary = Color("IOSLabelTertiary")
  static let labelQuaternary = Color("IOSLabelQuaternary")
  static let labelOnAccent = Color("IOSLabelOnAccent")
  static let accent = Color("IOSAccentDefault")
  static let accentText = Color("IOSAccentText")
  static let accentFill = Color("IOSAccentFill")
  static let accentSubtle = Color("IOSAccentSubtle")
  static let accentStroke = Color("IOSAccentStroke")
  static let fillSecondary = Color("IOSFillSecondary")
  static let fillTertiary = Color("IOSFillTertiary")
  static let separator = Color("IOSSeparatorDefault")
  static let warning = Color("IOSStatusWarning")
  static let groupedBackground = Color("IOSBgGrouped")
  static let groupedSecondary = Color("IOSBgGroupedSecondary")
  static let groupedTertiary = Color("IOSBgGroupedTertiary")
}

/// Shared dimensions are points, as in the Figma library and the token source.
nonisolated enum IOSMetrics {
  static let screenMargin: CGFloat = 16
  static let cardPadding: CGFloat = 16
  static let cardRadius: CGFloat = 26
  static let rowRadius: CGFloat = 14
  static let rowHeight: CGFloat = 52
  static let rowGlyph: CGFloat = 26
  static let hitTarget: CGFloat = 44
  static let sectionGap: CGFloat = 16
}

/// The phase belongs to the prayer period now, rather than the next prayer.
struct IOSSkyBackground: View {
  var phase: SalahPhase = .neutral
  var fadeStart: CGFloat = 0.22
  var fadeEnd: CGFloat = 0.42
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let colors = SalahColors(phase: phase, scheme: scheme, contrast: contrast)
    LinearGradient(
      stops: [
        .init(color: colors.phase.skyTop.color, location: 0),
        .init(color: colors.phase.skyBottom.color, location: fadeStart),
        .init(color: IOSTheme.groupedBackground, location: fadeEnd),
        .init(color: IOSTheme.groupedBackground, location: 1),
      ], startPoint: .top, endPoint: .bottom
    )
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}

typealias IOSPageBackground = IOSSkyBackground

struct IOSCard<Content: View>: View {
  var padding: CGFloat = IOSMetrics.cardPadding
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        IOSTheme.groupedSecondary,
        in: RoundedRectangle(cornerRadius: IOSMetrics.cardRadius, style: .continuous))
  }
}

/// Custom prayer symbols never mirror: they represent the same marks in every language.
struct IOSPrayerGlyph: View {
  let name: String
  var size: CGFloat = IOSMetrics.rowGlyph
  var resourceBundle: Bundle? = nil

  var body: some View {
    Image(name.hasPrefix("salah.") ? name : "salah.\(name)", bundle: resourceBundle)
      .symbolRenderingMode(.hierarchical)
      // The custom-symbol template includes its optical margins. Its font em is
      // smaller than the layout slot: 26 points contains an 18-point drawn mark.
      .font(.system(size: size * 0.58))
      .frame(width: size, height: size)
      .environment(\.layoutDirection, .leftToRight)
      .accessibilityHidden(true)
  }
}

struct IOSSummaryChip: View {
  let title: String
  var symbol: String = "location.fill"
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(IOSTheme.labelPrimary)
        .lineLimit(1)
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.capsule)
    .controlSize(.small)
    .tint(IOSTheme.labelSecondary)
    .frame(minHeight: IOSMetrics.hitTarget)
  }
}
