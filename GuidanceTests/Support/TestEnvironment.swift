import Foundation
import XCTest

/// The bundle's principal class (`INFOPLIST_KEY_NSPrincipalClass`). XCTest creates
/// it on the main thread when it loads the bundle, before any test runs, so the
/// process is configured before anything can touch `Preferences.shared`.
/// `nonisolated` because `NSObject.init()` is; the work hops onto the main actor.
@objc(GuidanceTestEnvironment)
nonisolated final class GuidanceTestEnvironment: NSObject, XCTestObservation {
  override init() {
    super.init()
    // XCTest calls this on the main thread and keeps the instance alive.
    nonisolated(unsafe) let observer = self
    MainActor.assumeIsolated {
      TestEnvironment.configure()
      XCTestObservationCenter.shared.addTestObserver(observer)
    }
  }

  func testBundleDidFinish(_ testBundle: Bundle) {
    MainActor.assumeIsolated { TestEnvironment.tearDown() }
  }
}

/// Process-wide test configuration. Every suite also calls `configure()`, which is
/// idempotent, so ordering never matters.
enum TestEnvironment {
  /// The fixtures' time zone (Makkah). Code that reads the process time zone
  /// (`Calendar.current`, default `DateFormatter`s) sees this one on every machine.
  static let timeZone = TimeZone(identifier: "Asia/Riyadh")!

  private static let sharedSuiteName = "GuidanceTests.Preferences.shared"
  private static var isConfigured = false

  static func configure() {
    guard !isConfigured else { return }
    isConfigured = true

    setenv("TZ", timeZone.identifier, 1)
    tzset()
    NSTimeZone.default = timeZone

    // The non-hosted bundle's main bundle is the xctest runner; the app's catalog
    // and sounds are copied into this bundle instead.
    AppResources.bundle = Bundle(for: GuidanceTestEnvironment.self)

    // `Preferences.shared` (behind `Locale.app`, prayer names, the formatters) gets
    // a throwaway suite: tests never read or write the real preferences.
    let defaults = UserDefaults(suiteName: sharedSuiteName)!
    defaults.removePersistentDomain(forName: sharedSuiteName)
    Preferences.sharedDefaults = defaults
    // Pin the language: `.system` would follow the machine's languages.
    Preferences.shared.appLanguage = .english
  }

  static func tearDown() {
    UserDefaults(suiteName: sharedSuiteName)?.removePersistentDomain(forName: sharedSuiteName)
  }
}

/// A `UserDefaults` suite of its own for one test, emptied when it's taken and
/// when it's released. Every suite leaves a preference file behind, even emptied,
/// so the names come from a small pool that every run reuses: a unique name per
/// test would add hundreds of files to `~/Library/Preferences` on each run.
nonisolated final class ScratchDefaults {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var freeSlots: [Int] = []
  nonisolated(unsafe) private static var slotCount = 0

  let suiteName: String
  let defaults: UserDefaults
  private let slot: Int

  init() {
    slot = Self.lock.withLock {
      if let slot = Self.freeSlots.popLast() { return slot }
      Self.slotCount += 1
      return Self.slotCount
    }
    suiteName = "GuidanceTests.scratch.\(slot)"
    defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
  }

  deinit {
    defaults.removePersistentDomain(forName: suiteName)
    Self.lock.withLock { Self.freeSlots.append(slot) }
  }
}
