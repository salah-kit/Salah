import Foundation
import SalahUI
import SwiftUI
import Testing

/// Measures the nominal ink after SwiftUI composites it onto the actual widget
/// background and hero/capsule surface. Caption text needs 4.5:1 even when the
/// decorative theme accent meets the editor's large-text 3:1 floor.
@Suite("Small accent text contrast")
struct SmallTextContrastTests {
  init() { TestEnvironment.configure() }

  @Test func smallAccentInkPassesComposedSurfaces() throws {
    for theme in SalahWidgetTheme.allPresets {
      for scheme in [ColorScheme.light, .dark] {
        // The public trait is read-only; the local SwiftUI interface exposes its
        // test-only backing key. Read back the public trait before measuring.
        for contrast in [ColorSchemeContrast.standard, .increased] {
          let colors = theme.colors(for: scheme)
          let trait = try #require(
            PixelComparison.rgba(
              BaselineRenderer.stablePNG {
                ContrastTraitReadback(expected: contrast)
                  .environment(\._colorSchemeContrast, contrast)
              }))
          #expect(Array(trait.bytes.prefix(4)) == [255, 255, 255, 255])
          for tone in [SalahWidgetTone.normal, .imminent, .silent] {
            for hero in [false, true] {
              func face(showsText: Bool, paintsInk: Bool = false) -> some View {
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
                .overlay { if paintsInk { Rectangle().fill(colors.accentText) } }
                .environment(\.colorScheme, scheme)
                .environment(\._colorSchemeContrast, contrast)
              }
              // Hiding only the ink preserves layout. This mask finds actual
              // caption glyphs; bright decoration elsewhere is not text background.
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
              let painted = try #require(
                PixelComparison.rgba(
                  BaselineRenderer.stablePNG {
                    face(showsText: false, paintsInk: true)
                  }))
              var lowest = Double.infinity
              var glyphPixels = 0
              for offset in stride(from: 0, to: shown.bytes.count, by: 4) {
                if (0..<3).contains(where: {
                  abs(Int(shown.bytes[offset + $0]) - Int(hidden.bytes[offset + $0])) > 2
                }) {
                  glyphPixels += 1
                  lowest = min(lowest, Self.contrast(painted.bytes, over: hidden.bytes, at: offset))
                }
              }
              #expect(glyphPixels > 20, "The probe must observe actual caption glyphs")
              #expect(
                lowest >= 4.5, "\(theme.id) \(scheme) \(contrast) \(tone) hero=\(hero): \(lowest)")
              print(
                "small-text-contrast \(theme.id) \(scheme) \(contrast) \(tone) hero=\(hero): \(lowest)"
              )
            }
          }
        }
      }
    }
  }

  @Test func silentModeInkPassesItsComposedCapsule() throws {
    for theme in SalahWidgetTheme.allPresets {
      for scheme in [ColorScheme.light, .dark] {
        for contrast in [ColorSchemeContrast.standard, .increased] {
          let colors = theme.colors(for: scheme)
          // The footer uses this 18% decorative capsule. Keep its layout when
          // hidden, then measure the interior behind its caption, clear of the rim.
          func face(showsCapsule: Bool, paintsInk: Bool = false) -> some View {
            VStack {
              Spacer()
              HStack {
                Capsule().fill(colors.accent.opacity(0.18)).frame(width: 74, height: 24)
                  .opacity(showsCapsule ? 1 : 0)
                Spacer()
              }
              .padding(16)
            }
            .frame(width: 338, height: 354)
            .background { SalahWidgetBackground(tone: .silent, colors: colors) }
            .overlay { if paintsInk { Rectangle().fill(colors.accentText) } }
            .environment(\.colorScheme, scheme)
            .environment(\._colorSchemeContrast, contrast)
          }
          let pixels = try #require(
            PixelComparison.rgba(
              BaselineRenderer.stablePNG {
                face(showsCapsule: true)
              }))
          let bare = try #require(
            PixelComparison.rgba(
              BaselineRenderer.stablePNG {
                face(showsCapsule: false)
              }))
          let painted = try #require(
            PixelComparison.rgba(
              BaselineRenderer.stablePNG {
                face(showsCapsule: true, paintsInk: true)
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
              lowest = min(lowest, Self.contrast(painted.bytes, over: pixels.bytes, at: offset))
            }
          }
          #expect(lowest >= 4.5, "\(theme.id) \(scheme) \(contrast) silent capsule: \(lowest)")
          print("silent-caption-contrast \(theme.id) \(scheme) \(contrast): \(lowest)")
        }
      }
    }
  }

  private static func contrast(_ painted: [UInt8], over surface: [UInt8], at offset: Int) -> Double
  {
    // PixelComparison stores premultipliedLast. Both layers must already be opaque:
    // SwiftUI has composited the semantic ink, including its alpha, on this exact
    // surface. This avoids assuming an encoded/linear sRGB blending convention.
    #expect(painted[offset + 3] == 255 && surface[offset + 3] == 255)
    func color(_ bytes: [UInt8]) -> ThemeColor {
      ThemeColor(
        red: Double(bytes[offset]) / 255, green: Double(bytes[offset + 1]) / 255,
        blue: Double(bytes[offset + 2]) / 255)
    }
    return ThemeColor.contrastRatio(color(painted), color(surface))
  }
}

private struct ContrastTraitReadback: View {
  @Environment(\.colorSchemeContrast) private var contrast
  let expected: ColorSchemeContrast
  var body: some View {
    Rectangle().fill(contrast == expected ? Color.white : Color.black).frame(width: 1, height: 1)
  }
}
