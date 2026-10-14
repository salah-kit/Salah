import Foundation

#if DEBUG
  /// Launch options of Debug builds, for the tests that run the real app.
  enum DebugOptions {
    /// `-salah.debug.withoutSystemPrompts YES`: skip everything that can bring up a
    /// consent prompt, so a test run never shows one:
    ///
    /// - `PrayerAlertCoordinator` doesn't ask for notification permission before it
    ///   installs a plan.
    /// - The Settings window's Notifications tab doesn't ask either when an alert is on;
    ///   it only reads and shows the current status.
    /// - `AudioPlaybackController` doesn't send Music the Apple Event that pauses it while
    ///   an alert plays.
    ///
    /// Nothing else changes: the app still installs the plan, posts due alerts and plays
    /// their sounds. Without permission, macOS just doesn't schedule or show those
    /// notifications.
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
