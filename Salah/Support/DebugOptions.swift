import Foundation
import SalahAlerts
import UserNotifications

#if DEBUG
  /// Launch options of Debug builds, for the tests that run the real app.
  enum DebugOptions {
    /// `-salah.debug.withoutSystemPrompts YES`: skip everything that can bring up a
    /// consent prompt, so a test run never shows one:
    ///
    /// - `PrayerAlertCoordinator` doesn't ask for notification permission before it
    ///   installs a plan.
    /// - The window's Notifications pane doesn't ask either when an alert is on;
    ///   it only reads and shows the current status.
    /// - `AudioPlaybackController` doesn't send Music the Apple Event that pauses it while
    ///   an alert plays.
    ///
    /// Nothing else changes: the app still installs the plan, posts due alerts and plays
    /// their sounds. Without permission, macOS just doesn't schedule or show those
    /// notifications; `withoutSystemNotificationsKey` keeps them from the system's center
    /// altogether.
    static let withoutSystemPromptsKey = "salah.debug.withoutSystemPrompts"

    /// `-salah.debug.scratchPreferences YES`: keep the preferences in a store of their own,
    /// emptied at launch. The app saves the preferences it launches with, so without it a
    /// test's launch arguments (a prayer moved by its adjustment, every alert off) would
    /// replace this Mac's own Salah preferences.
    static let scratchPreferencesKey = "salah.debug.scratchPreferences"

    /// `-salah.debug.showsOnboarding YES`: show the first launch's welcome with all its
    /// pages, whatever was asked before, so a test can walk through it. With
    /// `withoutSystemPromptsKey` its Allow buttons move on without asking.
    static let showsOnboardingKey = "salah.debug.showsOnboarding"

    /// `-salah.debug.now 2026-06-02T13:19:00+03:00`: the minute Salah shows at launch,
    /// running on from there (`AppClock`). The alerts keep the real time.
    nonisolated static let nowKey = "salah.debug.now"

    /// `-salah.debug.windowSize 888x520`: the size Salah's window opens at, in points, its
    /// title bar included. The window's minimum size still applies.
    nonisolated static let windowSizeKey = "salah.debug.windowSize"

    /// The launch's moment, if it asks for one.
    nonisolated static func now(defaults: UserDefaults = .standard) -> Date? {
      defaults.string(forKey: nowKey).flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// The launch's window size, if it asks for one.
    nonisolated static func windowSize(defaults: UserDefaults = .standard) -> CGSize? {
      guard
        let parts = defaults.string(forKey: windowSizeKey)?
          .split(separator: "x", omittingEmptySubsequences: false),
        parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]),
        width.isFinite, height.isFinite, width > 0, height > 0
      else { return nil }
      return CGSize(width: width, height: height)
    }

    /// The scratch store's suite.
    static let scratchSuiteName = "io.github.salah-kit.Salah.debug.scratch"

    /// `-salah.debug.withoutSystemNotifications YES`: the alerts go to a notification center
    /// of their own that holds nothing and reports notifications denied, so a test launch
    /// never adds, removes or shows a notification of this Mac's Salah. Alerts still come
    /// due and play in the app.
    static let withoutSystemNotificationsKey = "salah.debug.withoutSystemNotifications"

    /// The detached center when the launch asks for it; `nil` for the system's.
    static func notificationCenter(defaults: UserDefaults = .standard)
      -> (any PrayerNotificationCenter)?
    {
      defaults.bool(forKey: withoutSystemNotificationsKey) ? DetachedNotificationCenter() : nil
    }

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

  /// A notification center that holds nothing: notifications are denied, and adding or
  /// removing one does nothing.
  nonisolated final class DetachedNotificationCenter: PrayerNotificationCenter,
    @unchecked Sendable
  {
    // @unchecked: the delegate, its one stored property, is read and written only while
    // holding `lock`.
    private let lock = NSLock()
    private weak var storedDelegate: (any UNUserNotificationCenterDelegate)?

    var delegate: (any UNUserNotificationCenterDelegate)? {
      get { lock.withLock { storedDelegate } }
      set { lock.withLock { storedDelegate = newValue } }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { false }
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func pendingNotificationRequests() async throws -> [UNNotificationRequest] { [] }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {}
    func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] { [] }
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}
  }
#endif
