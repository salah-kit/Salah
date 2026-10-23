import SalahCore
import SalahUI
import SwiftUI

/// Salah's colors, from the design tokens in `Design/tokens`, for one appearance: light or
/// dark, with or without Increase Contrast. The app's window and dropdown and the widget
/// extension draw from the same values.
nonisolated struct SalahPalette: Equatable, Sendable {
  /// `label/primary`: primary text and glyphs.
  var labelPrimary: ThemeColor
  /// `label/secondary`: secondary text, 4.5:1 on every surface and sky.
  var labelSecondary: ThemeColor
  /// `label/tertiary`: passed rows, large text and marks only (3:1).
  var labelTertiary: ThemeColor
  /// `label/on-accent`: text and glyphs on `accentFill`.
  var labelOnAccent: ThemeColor
  /// `accent/default`: the one accent, for controls, selection and marks (3:1).
  var accent: ThemeColor
  /// `accent/text`: accent-colored text (4.5:1).
  var accentText: ThemeColor
  /// `accent/fill`: prominent accent fills, such as Stop, Open Salah and the Now badge.
  var accentFill: ThemeColor
  /// `accent/subtle`: the quiet wash behind the next prayer.
  var accentSubtle: ThemeColor
  /// `fill/secondary`: tracks, the selected sidebar row, the open status item.
  var fillSecondary: ThemeColor
  /// `fill/tertiary`: pressed rows, the status chip.
  var fillTertiary: ThemeColor
  /// `fill/quaternary`: hovered rows.
  var fillQuaternary: ThemeColor
  /// `fill/form-group`: a group of rows, as a grouped form draws it.
  var formGroup: ThemeColor
  /// `separator/default`: hairlines.
  var separator: ThemeColor
  /// `bg/elevated`: popovers and the dropdown.
  var elevated: ThemeColor
  /// `bg/grouped-secondary`: cards; the timeline's knob.
  var groupedSecondary: ThemeColor
  /// `glass/stroke`: the dropdown's rim.
  var glassStroke: ThemeColor
  /// `status/warning`: a permission is off.
  var warning: ThemeColor

  init(isDark: Bool, increasedContrast: Bool = false) {
    func pick(
      _ light: UInt32, _ dark: UInt32, _ lightHigh: UInt32? = nil, _ darkHigh: UInt32? = nil
    )
      -> ThemeColor
    {
      ThemeColor(
        hex: isDark
          ? (increasedContrast ? darkHigh ?? dark : dark)
          : (increasedContrast ? lightHigh ?? light : light))
    }
    labelPrimary = pick(0x0000_00FF, 0xFFFF_FFFF)
    labelSecondary = pick(0x3C3C_43C7, 0xEBEB_F5A3, 0x3C3C_43EB, 0xEBEB_F5D6)
    labelTertiary = pick(0x3C3C_439E, 0xEBEB_F570, 0x3C3C_43C2, 0xEBEB_F599)
    labelOnAccent = pick(0x2619_00FF, 0x2619_00FF)
    accent = pick(0x986F_05FF, 0xCCA5_5BFF, 0x7A57_00FF, 0xE1C1_88FF)
    accentText = pick(0x7A57_00FF, 0xE1C1_88FF, 0x4D36_00FF, 0xF9EC_D6FF)
    accentFill = pick(0xCCA5_5BFF, 0xCCA5_5BFF)
    accentSubtle = pick(0xF9EC_D6FF, 0xCCA5_5B29)
    fillSecondary = pick(0x7878_8029, 0x7878_8052, 0x7878_803D, 0x7878_8066)
    fillTertiary = pick(0x7676_801F, 0x7676_803D, 0x7676_8033, 0x7676_8052)
    fillQuaternary = pick(0x7474_8014, 0x7676_802E, 0x7474_8029, 0x7676_8042)
    formGroup = pick(0x0000_0008, 0xFFFF_FF08)
    separator = pick(0x3C3C_431F, 0x5454_5880)
    elevated = pick(0xFFFF_FFFF, 0x2C2C_2EFF, 0xFFFF_FFFF, 0x3636_38FF)
    groupedSecondary = pick(0xFFFF_FFFF, 0x1C1C_1EFF, 0xFFFF_FFFF, 0x2424_26FF)
    glassStroke = pick(0xFFFF_FF99, 0xFFFF_FF26, 0xFFFF_FFCC, 0xFFFF_FF40)
    warning = pick(0xB830_00FF, 0xFFB3_40FF, 0x9C27_00FF, 0xFFC1_6CFF)
  }
}

/// A time of day, which colors the sky, the prayer glyphs and the day's marks. It follows
/// the prayer period one is in, not the next prayer: dawn from Fajr, day from sunrise,
/// afternoon from Asr, dusk from Maghrib and night from Isha until the next Fajr. Neutral is
/// for when Salah doesn't follow the time of day.
nonisolated enum SalahPhase: String, Codable, CaseIterable, Sendable {
  case fajr, dhuhr, asr, maghrib, isha, neutral

  /// A phase's colors for one appearance.
  struct Colors: Equatable, Sendable {
    /// The sky gradient's top and bottom.
    var skyTop: ThemeColor
    var skyBottom: ThemeColor
    /// The phase's mark: glyphs, the timeline, the progress bar (3:1).
    var tint: ThemeColor
    /// Text in the phase's color (4.5:1 on its sky).
    var text: ThemeColor
    /// The quiet wash behind the current prayer's row.
    var tintSubtle: ThemeColor
  }

  func colors(isDark: Bool, increasedContrast: Bool = false) -> Colors {
    // light, dark, increased-contrast light, increased-contrast dark
    typealias Four = (UInt32, UInt32, UInt32, UInt32)
    func pick(_ four: Four) -> ThemeColor {
      ThemeColor(
        hex: isDark
          ? (increasedContrast ? four.3 : four.1)
          : (increasedContrast ? four.2 : four.0))
    }
    let skyTop: Four
    let skyBottom: Four
    let tint: Four
    let text: Four
    let subtle: Four
    switch self {
    case .fajr:
      skyTop = (0xE4EF_FEFF, 0x0B1C_34FF, 0xE4EF_FEFF, 0x0B1C_34FF)
      skyBottom = (0xFCF5_FCFF, 0x1A2F_4FFF, 0xFCF5_FCFF, 0x1A2F_4FFF)
      tint = (0x5178_B0FF, 0xAAC8_F4FF, 0x3D5F_91FF, 0xC9DE_FDFF)
      text = (0x3D5F_91FF, 0xC9DE_FDFF, 0x2B47_70FF, 0xE4EF_FEFF)
      subtle = (0xE4EF_FEFF, 0x1A2F_4FFF, 0xE4EF_FEFF, 0x1A2F_4FFF)
    case .dhuhr:
      skyTop = (0xDCF2_FFFF, 0x011F_2EFF, 0xDCF2_FFFF, 0x011F_2EFF)
      skyBottom = (0xF0F9_FFFF, 0x0134_4AFF, 0xF0F9_FFFF, 0x0134_4AFF)
      tint = (0x2180_ACFF, 0x94CF_F1FF, 0x0666_8DFF, 0xBBE3_FBFF)
      text = (0x0666_8DFF, 0xBBE3_FBFF, 0x024D_6BFF, 0xDCF2_FFFF)
      subtle = (0xDCF2_FFFF, 0x0134_4AFF, 0xDCF2_FFFF, 0x0134_4AFF)
    case .asr:
      skyTop = (0xFEEA_D8FF, 0x2C16_00FF, 0xFEEA_D8FF, 0x2C16_00FF)
      skyBottom = (0xFFF6_EDFF, 0x4626_00FF, 0xFFF6_EDFF, 0x4626_00FF)
      tint = (0xA566_1EFF, 0xECBB_8EFF, 0x874F_07FF, 0xF8D5_B6FF)
      text = (0x874F_07FF, 0xF8D5_B6FF, 0x673A_00FF, 0xFEEA_D8FF)
      subtle = (0xFEEA_D8FF, 0x4626_00FF, 0xFEEA_D8FF, 0x4626_00FF)
    case .maghrib:
      skyTop = (0xF7E9_F6FF, 0x2614_26FF, 0xF7E9_F6FF, 0x2614_26FF)
      skyBottom = (0xFFE7_E8FF, 0x4D1E_22FF, 0xFFE7_E8FF, 0x4D1E_22FF)
      tint = (0xAE5A_60FF, 0xF5B2_B5FF, 0x8E44_4AFF, 0xFECF_D0FF)
      text = (0x8E44_4AFF, 0xFECF_D0FF, 0x6D30_36FF, 0xFFE7_E8FF)
      subtle = (0xFFE7_E8FF, 0x4D1E_22FF, 0xFFE7_E8FF, 0x4D1E_22FF)
    case .isha:
      skyTop = (0xE9ED_FFFF, 0x1619_32FF, 0xE9ED_FFFF, 0x1619_32FF)
      skyBottom = (0xF5F7_FFFF, 0x272C_4DFF, 0xF5F7_FFFF, 0x272C_4DFF)
      tint = (0x6872_ADFF, 0xBAC3_F2FF, 0x5159_8EFF, 0xD4DB_FBFF)
      text = (0x5159_8EFF, 0xD4DB_FBFF, 0x3C42_6EFF, 0xE9ED_FFFF)
      subtle = (0xE9ED_FFFF, 0x272C_4DFF, 0xE9ED_FFFF, 0x272C_4DFF)
    case .neutral:
      skyTop = (0xF2F2_F7FF, 0x1C1C_1EFF, 0xEBEB_F0FF, 0x2424_26FF)
      skyBottom = (0xFFFF_FFFF, 0x0000_00FF, 0xFFFF_FFFF, 0x0000_00FF)
      tint = (0x986F_05FF, 0xCCA5_5BFF, 0x7A57_00FF, 0xE1C1_88FF)
      text = (0x7A57_00FF, 0xE1C1_88FF, 0x4D36_00FF, 0xF9EC_D6FF)
      subtle = (0xE5E5_EAFF, 0x2C2C_2EFF, 0xE5E5_EAFF, 0x3636_38FF)
    }
    return Colors(
      skyTop: pick(skyTop), skyBottom: pick(skyBottom), tint: pick(tint), text: pick(text),
      tintSubtle: pick(subtle))
  }

  /// The phase an event opens, if it opens one. Dhuhr opens the day only when there's no
  /// sunrise to open it.
  private static func opened(by event: PrayerEvent, hasSunrise: Bool) -> SalahPhase? {
    switch event.kind {
    case .fajr: .fajr
    case .sunrise: .dhuhr
    case .dhuhr: hasSunrise ? nil : .dhuhr
    case .asr: .asr
    case .maghrib: .maghrib
    case .isha: .isha
    }
  }

  /// The phase at `date`: the last one an event opened by then, or night.
  static func at(_ date: Date, events: [PrayerEvent]) -> SalahPhase {
    let hasSunrise = events.contains { $0.kind == .sunrise }
    return
      events
      .filter { $0.time <= date }
      .sorted { $0.time < $1.time }
      .compactMap { opened(by: $0, hasSunrise: hasSunrise) }
      .last ?? .isha
  }

  /// A stretch of the day in one phase.
  struct Segment: Equatable, Sendable {
    var phase: SalahPhase
    var start: Date
    var end: Date
  }

  /// The day from `start` to `end` in phases: the phase at `start` (night unless an
  /// earlier event opened another, such as a Fajr before midnight), then each phase from
  /// the event that opens it to the next one.
  static func segments(of events: [PrayerEvent], from start: Date, to end: Date) -> [Segment] {
    guard start < end else { return [] }
    let hasSunrise = events.contains { $0.kind == .sunrise }
    let openings =
      events
      .filter { $0.time > start && $0.time < end }
      .sorted { $0.time < $1.time }
      .compactMap { event in opened(by: event, hasSunrise: hasSunrise).map { (event.time, $0) } }
    var segments: [Segment] = []
    var phase = at(start, events: events)
    var from = start
    for (time, next) in openings {
      if time > from { segments.append(Segment(phase: phase, start: from, end: time)) }
      phase = next
      from = time
    }
    segments.append(Segment(phase: phase, start: from, end: end))
    return segments
  }
}

nonisolated extension ThemeColor {
  /// A color from `0xRRGGBBAA`.
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 24) & 0xFF) / 255, green: Double((hex >> 16) & 0xFF) / 255,
      blue: Double((hex >> 8) & 0xFF) / 255, opacity: Double(hex & 0xFF) / 255)
  }
}

/// Light, dark, or the system's appearance, for Salah's window, dropdown and widgets.
nonisolated enum SalahAppearance: String, Codable, CaseIterable, Sendable {
  case system, light, dark

  /// The color scheme to draw in, or `nil` to follow the system's.
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

// MARK: - In SwiftUI

/// Stills of a face, such as the visual baselines, pause its live timers at this moment, so
/// they read as they would then rather than against the clock. Unset, timers run.
nonisolated extension EnvironmentValues {
  @Entry var salahTimerPause: Date? = nil
}

/// The palette and a phase's colors for the view's appearance.
nonisolated struct SalahColors {
  let palette: SalahPalette
  let phase: SalahPhase.Colors

  init(phase: SalahPhase, scheme: ColorScheme, contrast: ColorSchemeContrast) {
    let isDark = scheme == .dark
    let increased = contrast == .increased
    palette = SalahPalette(isDark: isDark, increasedContrast: increased)
    self.phase = phase.colors(isDark: isDark, increasedContrast: increased)
  }

  /// Secondary text on the sky, as one opaque color: `labelSecondary` composited over the
  /// sky's end it sits nearest. It's close to the translucent label over the sky, and the
  /// accessibility audit measures it as drawn, where it reported the translucent label's
  /// small text on some skies.
  func secondaryOnSky(atTop: Bool) -> ThemeColor {
    palette.labelSecondary.composited(over: atTop ? phase.skyTop : phase.skyBottom)
  }

  /// The sky gradient, top to bottom.
  var sky: LinearGradient {
    LinearGradient(
      colors: [phase.skyTop.color, phase.skyBottom.color], startPoint: .top,
      endPoint: .bottom)
  }
}

nonisolated extension View {
  /// Draws the view in `scheme`, or in the system's appearance when it's `nil`.
  @ViewBuilder
  func salahColorScheme(_ scheme: ColorScheme?) -> some View {
    if let scheme {
      environment(\.colorScheme, scheme)
    } else {
      self
    }
  }
}

nonisolated extension ThemeColor {
  /// This color drawn over the opaque `surface`, as one opaque color.
  func composited(over surface: ThemeColor) -> ThemeColor {
    let alpha = opacity
    return ThemeColor(
      red: red * alpha + surface.red * (1 - alpha),
      green: green * alpha + surface.green * (1 - alpha),
      blue: blue * alpha + surface.blue * (1 - alpha))
  }
}
