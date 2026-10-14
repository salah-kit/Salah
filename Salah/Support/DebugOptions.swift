import Foundation

#if DEBUG
  /// Launch options of Debug builds, for the tests that run the real app.
  enum DebugOptions {
    /// `-salah.debug.withoutSystemPrompts YES`: never ask for notification permission and
    /// never send Apple Events to pause Music, so a test run can't bring up a consent
    /// prompt. Alerts still play in the app; macOS just isn't asked to deliver them.
    static let withoutSystemPromptsKey = "salah.debug.withoutSystemPrompts"

    /// `-salah.debug.scratchPreferences YES`: keep the preferences in a store of their own,
    /// emptied at launch. The app saves the preferences it launches with, so without it a
    /// test's launch arguments (a prayer moved by its adjustment, every alert off) would
    /// replace this Mac's own Salah preferences.
    static let scratchPreferencesKey = "salah.debug.scratchPreferences"

    /// The scratch store's suite.
    static let scratchSuiteName = "io.github.salah-kit.Salah.debug.scratch"

    /// The scratch store, emptied, when the launch asks for it. Launch arguments still
    /// read through it: the argument domain comes first in every store.
    static func scratchPreferences() -> UserDefaults? {
      guard UserDefaults.standard.bool(forKey: scratchPreferencesKey),
        let suite = UserDefaults(suiteName: scratchSuiteName)
      else { return nil }
      suite.removePersistentDomain(forName: scratchSuiteName)
      return suite
    }
  }
#endif
