import Foundation
import Testing

/// Contract for the single shared timer formatter used by the menu bar and every
/// widget size. Guards the three tiers (seconds / minutes / clock h:mm), the
/// floor (not ceil) boundary behavior, the count-up "+" prefix, localized digits,
/// and the optional FSI/PDI bidi wrap. Runs in the SalahTests target, which
/// compiles the app's sources directly.
@Suite struct RelativeDurationFormatterTests {
  private let en = Locale(identifier: "en")

  /// Arabic with the Arabic-Indic numbering system applied, mirroring how the app
  /// (`Locale.app`) and the widget (`SalahWidgetSnapshot.resolvedLocale`) build
  /// the locale they hand the formatter.
  private var ar: Locale {
    var c = Locale.Components(locale: Locale(identifier: "ar"))
    c.numberingSystem = Locale.NumberingSystem("arab")
    return Locale(components: c)
  }

  private func down(_ s: TimeInterval, _ loc: Locale) -> String {
    RelativeDurationFormatter.string(seconds: s, direction: .down, locale: loc)
  }
  private func up(_ s: TimeInterval, _ loc: Locale) -> String {
    RelativeDurationFormatter.string(seconds: s, direction: .up, locale: loc)
  }

  @Test func englishTiersAndBoundaries() {
    #expect(down(0, en) == "0s")
    #expect(down(1, en) == "1s")
    #expect(down(59, en) == "59s")
    #expect(down(60, en) == "1m")  // 60s crosses into the minutes tier
    #expect(down(61, en) == "1m")  // floors, never rounds up
    #expect(down(3599, en) == "59m")
    #expect(down(3600, en) == "1:00")  // clock tier, minutes zero-padded
    #expect(down(3661, en) == "1:01")
    #expect(down(10_140, en) == "2:49")  // 2h49m
  }

  @Test func countUpPrefix() {
    #expect(up(45, en) == "+45s")
    #expect(up(16 * 60, en) == "+16m")
    #expect(up(10_140, en) == "+2:49")
  }

  @Test func arabicDigitsUnitsAndPrefix() {
    #expect(down(49 * 60, ar) == "٤٩د")
    #expect(down(10_140, ar) == "٢:٤٩")
    #expect(down(3600, ar) == "١:٠٠")
    #expect(up(45, ar) == "+٤٥ث")
  }

  @Test func negativeIntervalClampsToZero() {
    #expect(down(-5, en) == "0s")
  }

  @Test func bidiIsolationWrap() {
    #expect(
      RelativeDurationFormatter.string(
        seconds: 3600, direction: .down, locale: en, bidiIsolated: true)
        == "\u{2068}1:00\u{2069}")
  }
}
