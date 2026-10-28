import Foundation
import SalahCore

/// Watch wording in the language chosen in Salah on the iPhone: the design's Arabic, and the
/// String Catalog for the other languages.
nonisolated struct WatchCopy: Sendable {
  let locale: Locale

  func callAsFunction(_ english: String, _ arabic: String) -> String {
    IOSL10n.text(english, arabic: arabic, locale: locale, bundle: AppResources.bundle)
  }

  /// A catalog sentence with its arguments, keeping numbers in the language's digits.
  func format(_ english: String, _ arabic: String, _ arguments: CVarArg...) -> String {
    String(format: self(english, arabic), locale: locale, arguments: arguments)
  }
}
