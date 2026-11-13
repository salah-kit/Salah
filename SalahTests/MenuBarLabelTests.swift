import AppKit
import SalahCore
import SwiftUI
import Testing

/// The status item's approaching capsule, against the highlight the menu bar draws.
///
/// While a status item's window is open, macOS 27 draws a highlight behind the item: a
/// capsule 24 pt tall that reaches 2 pt past the item at each end. The item's image lies
/// inside the item, so it can never cover the highlight; the gold capsule is drawn to sit
/// inside it instead.
@Suite("Menu bar label")
struct MenuBarLabelTests {
  init() { TestEnvironment.configure() }

  /// The highlight behind an open status item on macOS 27, in points.
  enum Highlight {
    static let height: CGFloat = 24
    /// How far it reaches past the item at each end.
    static let reach: CGFloat = 2
  }

  /// A Retina display's pixels per point.
  static let scale = 2

  /// The approaching label's image, as the status item gets it on a Retina display.
  func image(_ text: String, icon: MenuBarItem.Icon = .glyph(.dhuhr)) throws -> NSImage {
    let item = MenuBarItem(
      icon: icon, text: text, attention: false, approaching: true, accessibilityLabel: "")
    let label = MenuBarLabel(item: item, layoutDirection: .leftToRight)
    return try #require(label.image(menuBarIsDark: false, scale: CGFloat(Self.scale)))
  }

  /// An image's pixels, covered or not, in rows from the top.
  struct Coverage {
    let width: Int
    let height: Int
    let alpha: [UInt8]

    /// The first and the last pixel a row covers by half or more.
    func span(ofRow row: Int) -> ClosedRange<Int>? {
      let covered = (0..<width).filter { alpha[row * width + $0] >= 128 }
      guard let first = covered.first, let last = covered.last else { return nil }
      return first...last
    }
  }

  func coverage(_ image: NSImage) throws -> Coverage {
    let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let png = try #require(
      NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
    let pixels = try #require(PixelComparison.rgba(png))
    try #require(pixels.height == Int(image.size.height) * Self.scale)
    return Coverage(
      width: pixels.width, height: pixels.height,
      alpha: stride(from: 3, to: pixels.bytes.count, by: 4).map { pixels.bytes[$0] })
  }

  /// The highlight shows above and below the capsule as far as it reaches past the item's
  /// ends, so it frames the capsule rather than sticking out at its sides.
  @Test func theHighlightShowsAboveAndBelowTheCapsule() throws {
    let image = try image("Jumu’ah 22s")
    #expect(image.size.height == Highlight.height - 2 * Highlight.reach)
  }

  /// The capsule's ends are half circles, as the highlight's are: at each end, every row of
  /// the image starts or ends within a pixel of a circle as tall as the image.
  @Test func theCapsulesEndsAreHalfCircles() throws {
    let pixels = try coverage(image("Jumu’ah 22s"))
    let radius = Double(pixels.height) / 2
    // How far a row's edge at `x` lies from the circle around `centerX`, in pixels.
    func offCircle(_ x: Int, _ row: Int, centerX: Double) -> Double {
      abs(hypot(Double(x) - centerX, Double(row) + 0.5 - radius) - radius)
    }
    let offRows = try (0..<pixels.height).filter { row in
      let span = try #require(pixels.span(ofRow: row), "row \(row) is empty")
      // A row starts where its first covered pixel does, and ends where its last one does.
      return offCircle(span.lowerBound, row, centerX: radius) > 1
        || offCircle(span.upperBound + 1, row, centerX: Double(pixels.width) - radius) > 1
    }
    #expect(offRows.isEmpty, "rows \(offRows) of \(pixels.height) start or end off the circle")
  }

  /// A status item is a whole number of points wide, so an image half a point wider can't
  /// lie in its middle, and the highlight would show wider on one side of the capsule.
  @Test func theCapsuleIsWholePointsWide() throws {
    for text in ["", "10m", "Asr 10m", "A 10m", "Jumu’ah 22s"] {
      let width = try image(text).size.width
      #expect(width == width.rounded(), "\(text): \(width) pt")
    }
    // The Name + time display has no glyph.
    let width = try image("Asr 3:35", icon: .none).size.width
    #expect(width == width.rounded(), "Asr 3:35, without the glyph: \(width) pt")
  }
}
