import Foundation
import XCTest

/// The bundle's principal class (`INFOPLIST_KEY_NSPrincipalClass`). XCTest creates
/// it on the main thread when it loads the bundle, before any test runs, so the
/// process is configured before anything can touch `Preferences.shared`.
/// `nonisolated` because `NSObject.init()` is; the work hops onto the main actor.
@objc(SalahTestEnvironment)
nonisolated final class SalahTestEnvironment: NSObject, XCTestObservation {
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

  /// This run's preference files. A suite named by an absolute path keeps its plist
  /// at that path, so every defaults suite the tests use lives here: none lands in
  /// `~/Library/Preferences`, two test runs at once never share a suite, and
  /// `tearDown()` deletes the folder.
  nonisolated static let preferencesDirectory: URL = {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "SalahTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  static let sharedSuiteName = preferencesDirectory.appending(path: "Preferences.shared").path
  private static var isConfigured = false

  static func configure() {
    guard !isConfigured else { return }
    isConfigured = true

    setenv("TZ", timeZone.identifier, 1)
    tzset()
    NSTimeZone.default = timeZone

    // The non-hosted bundle's main bundle is the xctest runner; the app's catalog
    // and sounds are copied into this bundle instead.
    AppResources.bundle = Bundle(for: SalahTestEnvironment.self)

    // `Preferences.shared` (behind `Locale.app`, prayer names, the formatters) gets
    // a throwaway suite: tests never read or write the real preferences.
    Preferences.sharedDefaults = UserDefaults(suiteName: sharedSuiteName)!
    // Pin the language: `.system` would follow the machine's languages.
    Preferences.shared.appLanguage = .english
  }

  static func tearDown() {
    UserDefaults(suiteName: sharedSuiteName)?.removePersistentDomain(forName: sharedSuiteName)
    try? FileManager.default.removeItem(at: preferencesDirectory)
  }
}

/// A `UserDefaults` suite of its own for one test, in this run's preferences
/// folder (`TestEnvironment.preferencesDirectory`), emptied when released.
nonisolated final class ScratchDefaults {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var count = 0

  let suiteName: String
  let defaults: UserDefaults

  init() {
    let number = Self.lock.withLock {
      Self.count += 1
      return Self.count
    }
    suiteName = TestEnvironment.preferencesDirectory.appending(path: "scratch-\(number)").path
    defaults = UserDefaults(suiteName: suiteName)!
  }

  deinit {
    defaults.removePersistentDomain(forName: suiteName)
  }
}
