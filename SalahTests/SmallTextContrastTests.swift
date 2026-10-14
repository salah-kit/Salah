import Foundation
import SalahUI
import SwiftUI
import Testing

/// Measures the opaque color after SwiftUI resolves it against the composed widget
/// backdrop and the menu/large-widget hero surface. Caption labels need 4.5:1, even
/// when the theme's decorative accent passes the editor's large-text 3:1 floor.
@Suite("Small accent text contrast")
struct SmallTextContrastTests {
  init() { TestEnvironment.configure() }

  @Test func smallAccentInkPassesComposedSurfaces() throws {
    for theme in SalahWidgetTheme.allPresets {
      for scheme in [ColorScheme.light, .dark] {
        // The public contrast trait is read-only; this test-only backing key is
        // present in the local SwiftUI interface and drives its actual renderer.
        for contrast in [ColorSchemeContrast.standard, .increased] {
          let colors = theme.colors(for: scheme)
          let inkPNG = try BaselineRenderer.stablePNG {
            Rectangle().fill(colors.accentText).frame(width: 8, height: 8)
              .environment(\.colorScheme, scheme)
              .environment(\._colorSchemeContrast, contrast)
          }
          let inkPixels = try #require(PixelComparison.rgba(inkPNG))
          let ink = Self.color(inkPixels.bytes, at: 0)
          for tone in [SalahWidgetTone.normal, .imminent, .silent] {
            for hero in [false, true] {
              func face(showsText: Bool) -> some View {
                VStack(alignment: .leading, spacing: 0) {
                  EyebrowLabel(text: "NEXT PRAYER", accent: colors.accentText)
                    .opacity(showsText ? 1 : 0)
                    .padding(12)
                    .frame(width: 306, alignment: .leading)
                    .background {
                      if hero {
                        Color.clear.salahHeroCard(
                          toneColor: tone.color(colors), accent: colors.accent)
                      }
                    }
                    .padding(.top, 40)
                  Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(width: 338, height: 354)
                .background { SalahWidgetBackground(tone: tone, colors: colors) }
                .environment(\.colorScheme, scheme)
                .environment(\._colorSchemeContrast, contrast)
              }
              // Hide only the label ink, retaining its layout. The difference mask
              // locates the real caption glyphs, so bright decorations elsewhere
              // in a card cannot be confused with a background behind text.
              let shown = try #require(
                PixelComparison.rgba(
                  BaselineRenderer.stablePNG {
                    face(showsText: true)
                  }))
              let hidden = try #require(
                PixelComparison.rgba(
                  BaselineRenderer.stablePNG {
                    face(showsText: false)
                  }))
              var lowest = Double.infinity
              var glyphPixels = 0
              for offset in stride(from: 0, to: shown.bytes.count, by: 4) {
                if (0..<3).contains(where: {
                  abs(Int(shown.bytes[offset + $0]) - Int(hidden.bytes[offset + $0])) > 2
                }) {
                  glyphPixels += 1
                  lowest = min(
                    lowest, ThemeColor.contrastRatio(ink, Self.color(hidden.bytes, at: offset)))
                }
              }
              #expect(glyphPixels > 20, "The probe must observe actual caption glyphs")
              #expect(
                lowest >= 4.5,
                "\(theme.id) \(scheme) \(contrast) \(tone) hero=\(hero): \(lowest)")
              print(
                "small-text-contrast \(theme.id) \(scheme) \(contrast) \(tone) hero=\(hero): \(lowest)"
              )

            }
          }
        }
      }
    }
  }

  private static func color(_ bytes: [UInt8], at offset: Int) -> ThemeColor {
    ThemeColor(
      red: Double(bytes[offset]) / 255, green: Double(bytes[offset + 1]) / 255,
      blue: Double(bytes[offset + 2]) / 255)
  }

  @Test func silentModeInkPassesItsComposedCapsule() throws {
    for theme in SalahWidgetTheme.allPresets {
      for scheme in [ColorScheme.light, .dark] {
        for contrast in [ColorSchemeContrast.standard, .increased] {
          let colors = theme.colors(for: scheme)
          let inkPNG = try BaselineRenderer.stablePNG {
            Rectangle().fill(colors.accentText).frame(width: 8, height: 8)
              .environment(\.colorScheme, scheme)
              .environment(\._colorSchemeContrast, contrast)
          }
          let inkPixels = try #require(PixelComparison.rgba(inkPNG))
          let ink = Self.color(inkPixels.bytes, at: 0)
          // The footer's capsule is decorative accent at 18% over the dropdown
          // background. Measure the interior behind its caption, clear of the rim.
          let png = try BaselineRenderer.stablePNG {
            VStack {
              Spacer()
              HStack {
                Capsule().fill(colors.accent.opacity(0.18)).frame(width: 74, height: 24)
                Spacer()
              }
              .padding(16)
            }
            .frame(width: 338, height: 354)
            .background { SalahWidgetBackground(tone: .silent, colors: colors) }
            .environment(\.colorScheme, scheme)
            .environment(\._colorSchemeContrast, contrast)
          }
          let pixels = try #require(PixelComparison.rgba(png))
          let bare = try #require(
            PixelComparison.rgba(
              BaselineRenderer.stablePNG {
                SalahWidgetBackground(tone: .silent, colors: colors)
                  .frame(width: 338, height: 354)
                  .environment(\.colorScheme, scheme)
                  .environment(\._colorSchemeContrast, contrast)
              }))
          var xs: [Int] = []
          var ys: [Int] = []
          for offset in stride(from: 0, to: pixels.bytes.count, by: 4) {
            if (0..<3).contains(where: {
              abs(Int(pixels.bytes[offset + $0]) - Int(bare.bytes[offset + $0])) > 2
            }) {
              xs.append(offset / 4 % pixels.width)
              ys.append(offset / 4 / pixels.width)
            }
          }
          let left = try #require(xs.min())
          let right = try #require(xs.max())
          let top = try #require(ys.min())
          let bottom = try #require(ys.max())
          #expect(right - left > 60 && bottom - top > 18, "The probe must observe the capsule")
          var lowest = Double.infinity
          for y in (top + 5)..<(bottom - 4) {
            for x in (left + 8)..<(right - 7) {
              let offset = (y * pixels.width + x) * 4
              lowest = min(
                lowest, ThemeColor.contrastRatio(ink, Self.color(pixels.bytes, at: offset)))
            }
          }
          #expect(lowest >= 4.5, "\(theme.id) \(scheme) \(contrast) silent capsule: \(lowest)")
          print("silent-caption-contrast \(theme.id) \(scheme) \(contrast): \(lowest)")
        }
      }
    }
  }
}
