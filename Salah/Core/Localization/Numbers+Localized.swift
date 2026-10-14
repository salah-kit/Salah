import Foundation

extension Int {
  func localizedDigits(minDigits: Int = 1, locale: Locale = .app) -> String {
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.minimumIntegerDigits = minDigits
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
  }
}

// `String.bidiIsolated` lives in Shared/SalahText.swift, which the widget extension
// compiles too.
