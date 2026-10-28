import SalahCore
import SwiftUI

/// Salah's glyph for a prayer or sunrise: a custom symbol from the asset catalog, which
/// sizes with `.font` and tints with the foreground style.
nonisolated struct PrayerGlyph: View {
  let kind: PrayerKind
  var observance: PrayerObservance = .ordinary

  var assetName: String {
    kind == .dhuhr && observance == .jumuah ? "salah.jumuah" : "salah.\(kind.rawValue)"
  }

  var body: some View {
    Image(assetName, bundle: AppResources.bundle)
      .symbolRenderingMode(.hierarchical)
  }
}
