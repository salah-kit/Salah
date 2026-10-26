import SalahCore
import SwiftUI

/// The Apple TV's semantic colors: the token color sets the iPhone and iPad use
/// (`SalahIOS/Assets.xcassets`), which follow the appearance and Increase Contrast.
nonisolated enum TVTheme {
  static var labelPrimary: Color { color("IOSLabelPrimary") }
  static var labelSecondary: Color { color("IOSLabelSecondary") }
  static var labelTertiary: Color { color("IOSLabelTertiary") }
  static var labelOnAccent: Color { color("IOSLabelOnAccent") }
  static var accentText: Color { color("IOSAccentText") }
  static var accentFill: Color { color("IOSAccentFill") }
  static var accentSubtle: Color { color("IOSAccentSubtle") }
  static var accentStroke: Color { color("IOSAccentStroke") }
  static var fillSecondary: Color { color("IOSFillSecondary") }
  static var fillQuaternary: Color { color("IOSFillQuaternary") }
  static var separator: Color { color("IOSSeparatorDefault") }
  static var warning: Color { color("IOSStatusWarning") }
  /// The focus platter: white in both appearances, as tvOS draws a focused item.
  static var platter: Color { color("IOSBgPrimary") }
  static var shadowKey: Color { color("IOSShadowKey") }
  static var shadowAmbient: Color { color("IOSShadowAmbient") }

  /// The unit-test bundle compiles these sources without the app, so it points
  /// `AppResources.bundle` at itself, where the same asset catalog is compiled.
  private static func color(_ name: String) -> Color {
    Color(name, bundle: AppResources.bundle)
  }
}

/// The 1920 × 1080 pt canvas every Apple TV draws, and the grid the HIG gives it.
nonisolated enum TVMetrics {
  /// Text and anything focusable stay this far from the left and right edges.
  static let safeHorizontal: CGFloat = 80
  /// And this far from the top and bottom, so nothing is lost to overscan.
  static let safeVertical: CGFloat = 60
  /// One of two columns across the safe width, with the grid's 40 pt gutter.
  static let column: CGFloat = 860
  static let gutter: CGFloat = 40
  /// One of six columns: the room display's cells.
  static let boardColumn: CGFloat = 260
  /// Where content starts below the tab bar, whose top edge is 46 pt from the top and
  /// which is 68 pt tall.
  static let contentTop: CGFloat = 168
  /// A prayer row, and the pitch between rows that leaves room for a focused row to grow.
  static let rowHeight: CGFloat = 96
  static let rowSpacing: CGFloat = 14
  static let rowRadius: CGFloat = 30
  /// A focused item grows by this much on every side.
  static let focusGrowth: CGFloat = 4
}

/// Salah's three large numerals. They scale with the text style they sit beside, so
/// Larger Text on tvOS 27 grows them too.
nonisolated enum TVNumeral {
  /// The countdown: 152 pt at the default size, scaled with Title 1.
  static let countdown: CGFloat = 152
  /// The room display's clock: 120 pt, scaled with Title 1.
  static let clock: CGFloat = 120
  /// A board cell's time: 57 pt, scaled with Title 2.
  static let boardTime: CGFloat = 57

  static func font(size: CGFloat) -> Font {
    .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
  }
}

/// The time of day's sky, edge to edge: light washes in light mode and deep tones in dark,
/// so labels keep their contrast.
struct TVSkyBackground: View {
  var phase: SalahPhase
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    SalahColors(phase: phase, scheme: scheme, contrast: contrast).sky
      .ignoresSafeArea()
      .accessibilityHidden(true)
  }
}

/// Custom prayer symbols never mirror: they're the same marks in every language.
struct TVPrayerGlyph: View {
  let name: String
  var size: CGFloat
  var color: Color

  var body: some View {
    Image(name, bundle: AppResources.bundle)
      .symbolRenderingMode(.hierarchical)
      // The custom-symbol template includes its optical margins, so its em is smaller than
      // the slot it fills.
      .font(.system(size: size * 0.58))
      .foregroundStyle(color)
      .frame(width: size, height: size)
      .environment(\.layoutDirection, .leftToRight)
      .accessibilityHidden(true)
  }
}

nonisolated extension PrayerEvent {
  /// The glyph of the event: Jumu'ah's own on a Friday that declares it.
  var glyphName: String {
    observance == .jumuah ? "salah.jumuah" : "salah." + kind.rawValue
  }
}
