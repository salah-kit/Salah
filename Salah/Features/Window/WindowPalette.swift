import AppKit
import SalahUI
import SwiftUI

/// Colors of Salah's window that AppKit resolves for each appearance, from `SalahPalette`:
/// tints and fills set on controls, outside a view that reads the color scheme.
enum WindowPalette {
  /// `accent.default`: the sidebar's symbols and the window's controls.
  static let accent = dynamic(\.accent)
  /// `accent.fill`: a filled accent control, such as the note's Got It.
  static let accentFill = dynamic(\.accentFill)
  /// `label/on-accent`: text on `accentFill`.
  static let onAccent = dynamic(\.labelOnAccent)

  private static func dynamic(_ token: KeyPath<SalahPalette, ThemeColor> & Sendable) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [
          .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ])
        let palette = SalahPalette(
          isDark: match == .darkAqua || match == .accessibilityHighContrastDarkAqua,
          increasedContrast: match == .accessibilityHighContrastAqua
            || match == .accessibilityHighContrastDarkAqua)
        let color = palette[keyPath: token]
        return NSColor(
          srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.opacity)
      })
  }
}
