import AppKit
import SwiftUI

/// The colors of Salah's window, from the design tokens in `Design/tokens`: the gold accent,
/// and each time of day's sky and tint, in light and dark and their increased-contrast
/// variants.
enum WindowPalette {
  /// `accent.default`: the sidebar's symbols and the window's controls.
  static let accent = dynamic(
    light: 0x986F05, dark: 0xCCA55B, lightHigh: 0x7A5700, darkHigh: 0xE1C188)
  /// `accent.text`: text in the accent, such as the next prayer's countdown in its row.
  static let accentText = dynamic(
    light: 0x7A5700, dark: 0xE1C188, lightHigh: 0x4D3600, darkHigh: 0xF9ECD6)
  /// `accent.fill`: a filled accent control, such as the note's Got It.
  static let accentFill = dynamic(light: 0xCCA55B, dark: 0xCCA55B)
  /// `label/on-accent`: text on `accentFill`.
  static let onAccent = dynamic(light: 0x261900, dark: 0x261900)
  /// `accent.subtle`: the next prayer's row.
  static let accentSubtle = dynamic(light: 0xF9ECD6, dark: 0xCCA55B, darkAlpha: 0.16)
  /// `fill/form-group`: a group of rows, as a grouped form draws it.
  static let groupFill = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.03, darkAlpha: 0.05)

  /// A time of day's colors.
  struct Phase {
    /// The top and bottom of its sky, the next prayer card's gradient.
    var skyTop: Color
    var skyBottom: Color
    /// Its signature mark: its stretch of the day timeline and its glyph.
    var tint: Color
  }

  static let fajr = Phase(
    skyTop: dynamic(light: 0xE4EFFE, dark: 0x0B1C34),
    skyBottom: dynamic(light: 0xFCF5FC, dark: 0x1A2F4F),
    tint: dynamic(light: 0x5178B0, dark: 0xAAC8F4, lightHigh: 0x3D5F91, darkHigh: 0xC9DEFD))
  static let dhuhr = Phase(
    skyTop: dynamic(light: 0xDCF2FF, dark: 0x011F2E),
    skyBottom: dynamic(light: 0xF0F9FF, dark: 0x01344A),
    tint: dynamic(light: 0x2180AC, dark: 0x94CFF1, lightHigh: 0x06668D, darkHigh: 0xBBE3FB))
  static let asr = Phase(
    skyTop: dynamic(light: 0xFEEAD8, dark: 0x2C1600),
    skyBottom: dynamic(light: 0xFFF6ED, dark: 0x462600),
    tint: dynamic(light: 0xA5661E, dark: 0xECBB8E, lightHigh: 0x874F07, darkHigh: 0xF8D5B6))
  static let maghrib = Phase(
    skyTop: dynamic(light: 0xF7E9F6, dark: 0x261426),
    skyBottom: dynamic(light: 0xFFE7E8, dark: 0x4D1E22),
    tint: dynamic(light: 0xAE5A60, dark: 0xF5B2B5, lightHigh: 0x8E444A, darkHigh: 0xFECFD0))
  static let isha = Phase(
    skyTop: dynamic(light: 0xE9EDFF, dark: 0x161932),
    skyBottom: dynamic(light: 0xF5F7FF, dark: 0x272C4D),
    tint: dynamic(light: 0x6872AD, dark: 0xBAC3F2, lightHigh: 0x51598E, darkHigh: 0xD4DBFB))

  /// A color for each appearance; the increased-contrast variants default to the plain ones.
  private static func dynamic(
    light: UInt32, dark: UInt32, lightHigh: UInt32? = nil, darkHigh: UInt32? = nil,
    lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1
  ) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [
          .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ])
        return switch match {
        case .darkAqua: rgb(dark, alpha: darkAlpha)
        case .accessibilityHighContrastDarkAqua: rgb(darkHigh ?? dark, alpha: darkAlpha)
        case .accessibilityHighContrastAqua: rgb(lightHigh ?? light, alpha: lightAlpha)
        default: rgb(light, alpha: lightAlpha)
        }
      })
  }

  private static func rgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
  }
}
