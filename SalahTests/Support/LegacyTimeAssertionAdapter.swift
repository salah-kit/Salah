import Foundation

// Keep the pre-migration assertions unchanged while production styles consume SalahUI's
// Text values. Non-view app strings use this same short formatter and bidi isolation.
nonisolated extension SalahText {
  func time(_ date: Date) -> String {
    timeFormatter().string(from: date).bidiIsolated
  }
}
