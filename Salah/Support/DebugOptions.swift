import Foundation

#if DEBUG
  /// Launch options of Debug builds, for the tests that run the real app.
  enum DebugOptions {
    /// `-salah.debug.withoutSystemPrompts YES`: never ask for notification permission and
    /// never send Apple Events to pause Music, so a test run can't bring up a consent
    /// prompt. Alerts still play in the app; macOS just isn't asked to deliver them.
    static let withoutSystemPromptsKey = "salah.debug.withoutSystemPrompts"
  }
#endif
