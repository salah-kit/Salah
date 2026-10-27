import Foundation
import SalahAlerts
import SalahCore
import Testing
@preconcurrency import UserNotifications

@Suite("iOS native notification installation")
@MainActor struct ServiceNotificationTests {
  private let now = Date(timeIntervalSince1970: 1_791_280_800)

  @Test func refreshReadsNativeRequestsBackRespectsTotalBudgetAndMuteKeepsBanners() async throws {
    let center = ServiceNotificationCenter()
    for index in 0..<12 { center.insertExternal("other.\(index)") }
    let files = temporaryFiles()
    defer {
      try? FileManager.default.removeItem(at: files.audioDirectory.deletingLastPathComponent())
    }
    var preferences = preferences()
    for kind in PrayerKind.allCases {
      preferences.notifications[kind] = IOSPrayerAlertSettings(
        atTime: true, sound: .system, beforeEnabled: true, beforeMinutes: 10,
        beforeSound: .softTone, afterEnabled: true, afterMinutes: 5, afterSound: .none)
    }
    let service = IOSNotificationService(center: center, files: files, now: { now })
    await service.refresh(
      schedule: preferences.mirror?.schedule, preferences: preferences, now: now)
    let pending = try await center.pendingNotificationRequests()
    #expect(pending.count <= 64)
    #expect(pending.filter { IOSNotificationService.owns($0.identifier) }.count <= 52)
    #expect(service.report?.failures.isEmpty == true)
    #expect(service.report?.confirmed.isEmpty == false)
    let identities = Set(
      pending.filter { IOSNotificationService.owns($0.identifier) }.map(\.identifier))
    preferences.muteSounds = true
    await service.refresh(
      schedule: preferences.mirror?.schedule, preferences: preferences, now: now)
    let muted = try await center.pendingNotificationRequests().filter {
      IOSNotificationService.owns($0.identifier)
    }
    #expect(Set(muted.map(\.identifier)) == identities)
    #expect(muted.allSatisfy { $0.content.sound == nil })
    #expect(muted.allSatisfy { !$0.content.title.isEmpty && !$0.content.body.isEmpty })
    #expect(service.foregroundPresentationOptions().contains(.banner))
    #expect(!service.foregroundPresentationOptions().contains(.sound))
  }

  @Test func permissionDenialClearsOnlyOwnedRequestsAndNeverClaimsCoverage() async throws {
    let center = ServiceNotificationCenter()
    let files = temporaryFiles()
    defer {
      try? FileManager.default.removeItem(at: files.audioDirectory.deletingLastPathComponent())
    }
    let preferences = preferences()
    let zone = try #require(preferences.location?.timeZone)
    // After Isha, so the next alert is tomorrow's Fajr: a denied read-back still reports
    // coverage up to it, which would read as all of today being scheduled.
    let evening = now.addingTimeInterval(9 * 3_600)
    let service = IOSNotificationService(center: center, files: files, now: { evening })
    await service.refresh(
      schedule: preferences.mirror?.schedule, preferences: preferences, now: evening)
    #expect(service.lastFullyScheduledDay(in: zone) != nil)
    center.insertExternal("unrelated")
    center.setAuthorization(.denied)
    await service.refresh(
      schedule: preferences.mirror?.schedule, preferences: preferences, now: evening)
    #expect(service.status == .denied)
    #expect(service.report?.confirmed.isEmpty == true)
    #expect(service.lastFullyScheduledDay(in: zone) == nil)
    #expect(try await center.pendingNotificationRequests().map(\.identifier) == ["unrelated"])
  }

  @Test func coverageShowsOnlyDaysWhoseEveryAlertIsInstalled() async throws {
    let center = ServiceNotificationCenter()
    let files = temporaryFiles()
    defer {
      try? FileManager.default.removeItem(at: files.audioDirectory.deletingLastPathComponent())
    }
    var preferences = preferences()
    for kind in PrayerKind.allCases where kind != .sunrise {
      preferences.notifications[kind] = IOSPrayerAlertSettings(
        atTime: true, sound: .system, beforeEnabled: true, beforeMinutes: 10,
        beforeSound: .system, afterEnabled: true, afterMinutes: 5, afterSound: .system)
    }
    let zone = try #require(preferences.location?.timeZone)
    let service = IOSNotificationService(center: center, files: files, now: { now })
    await service.refresh(
      schedule: preferences.mirror?.schedule, preferences: preferences, now: now)
    // Every kind is reserved for two days, so the reminders stop during Oct 8's afternoon.
    let coverage = try #require(service.report?.confirmedCoveredUntil)
    #expect(CivilDay(containing: coverage, in: zone) == CivilDay(year: 2026, month: 10, day: 8))
    #expect(service.lastFullyScheduledDay(in: zone) == CivilDay(year: 2026, month: 10, day: 7))

    let today = CivilDay(year: 2026, month: 10, day: 6)
    func report(coveredUntil: Date) -> NotificationApplyReport {
      NotificationApplyReport(
        verifiedAt: now, confirmed: [], failures: [:], superseded: false,
        confirmedCoveredUntil: coveredUntil)
    }
    let midnight = today.adding(days: 2).start(in: zone)
    #expect(
      IOSNotificationService.lastFullyScheduledDay(report(coveredUntil: midnight), in: zone)
        == today.adding(days: 1))
    let tonight = today.start(in: zone).addingTimeInterval(20 * 3_600)
    #expect(
      IOSNotificationService.lastFullyScheduledDay(report(coveredUntil: tonight), in: zone)
        == nil)
  }

  @Test func cancelledNewestRefreshStillInstallsItsPlan() async throws {
    let center = ServiceNotificationCenter()
    let files = temporaryFiles()
    defer {
      try? FileManager.default.removeItem(at: files.audioDirectory.deletingLastPathComponent())
    }
    var preferences = preferences()
    let service = IOSNotificationService(center: center, files: files, now: { now })
    await service.refresh(
      schedule: preferences.mirror?.schedule, preferences: preferences, now: now)
    preferences.muteSounds = true
    let muted = preferences
    // A scene that leaves the foreground cancels the refresh that superseded the others.
    let refresh = Task {
      await service.refresh(schedule: muted.mirror?.schedule, preferences: muted, now: now)
    }
    refresh.cancel()
    await refresh.value
    let owned = try await center.pendingNotificationRequests().filter {
      IOSNotificationService.owns($0.identifier)
    }
    #expect(!owned.isEmpty)
    #expect(owned.allSatisfy { $0.content.sound == nil })
  }

  /// Without a schedule, as when the stored settings can't be read, the installed alerts stay:
  /// they're still the user's, and nothing replaces them.
  @Test func aMissingScheduleKeepsTheInstalledAlerts() async throws {
    let center = ServiceNotificationCenter()
    let files = temporaryFiles()
    defer {
      try? FileManager.default.removeItem(at: files.audioDirectory.deletingLastPathComponent())
    }
    let preferences = preferences()
    let service = IOSNotificationService(center: center, files: files, now: { now })
    await service.refresh(
      schedule: preferences.mirror?.schedule, preferences: preferences, now: now)
    let installed = try await center.pendingNotificationRequests().map(\.identifier).sorted()
    #expect(!installed.isEmpty)
    await service.refresh(schedule: nil, preferences: IOSPreferences(), now: now)
    let kept = try await center.pendingNotificationRequests().map(\.identifier).sorted()
    #expect(kept == installed)
  }

  @Test func nativeAddFailureRemainsVisibleRatherThanClaimedAsInstalled() async {
    let center = ServiceNotificationCenter()
    center.failAdds = true
    let files = temporaryFiles()
    defer {
      try? FileManager.default.removeItem(at: files.audioDirectory.deletingLastPathComponent())
    }
    let preferences = preferences()
    let service = IOSNotificationService(center: center, files: files, now: { now })
    await service.refresh(
      schedule: preferences.mirror?.schedule, preferences: preferences, now: now)
    #expect(service.report?.confirmed.isEmpty == true)
    #expect(service.report?.failures.isEmpty == false)
    #expect(service.errorMessage != nil)
  }

  private func preferences() -> IOSPreferences {
    var preferences = IOSPreferences()
    preferences.location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262, timeZone: TimeZone(identifier: "Asia/Riyadh") ?? .gmt,
      countryCode: "SA", name: "Makkah")
    preferences.language = .english
    return preferences
  }

  private func temporaryFiles() -> IOSAudioFiles {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return IOSAudioFiles(
      audioDirectory: directory.appendingPathComponent("Audio"),
      soundsDirectory: directory.appendingPathComponent("Sounds"))
  }
}

/// The lock covers native request state; each request copies its content before storage.
nonisolated final class ServiceNotificationCenter: IOSNotificationCenter, @unchecked Sendable {
  private let lock = NSLock()
  private var authorization: UNAuthorizationStatus = .authorized
  private var pending: [String: UNNotificationRequest] = [:]
  private var storedDelegate: (any UNUserNotificationCenterDelegate)?
  private var shouldFailAdds = false
  var failAdds: Bool {
    get { lock.withLock { shouldFailAdds } }
    set { lock.withLock { shouldFailAdds = newValue } }
  }
  var delegate: (any UNUserNotificationCenterDelegate)? {
    get { lock.withLock { storedDelegate } }
    set { lock.withLock { storedDelegate = newValue } }
  }
  func authorizationStatus() async -> UNAuthorizationStatus { lock.withLock { authorization } }
  func setAuthorization(_ value: UNAuthorizationStatus) { lock.withLock { authorization = value } }
  func pendingNotificationRequests() async throws -> [UNNotificationRequest] {
    lock.withLock { Array(pending.values) }
  }
  func add(_ request: UNNotificationRequest) async throws {
    try lock.withLock {
      if shouldFailAdds { throw CocoaError(.fileWriteUnknown) }
      pending[request.identifier] = request
    }
  }
  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
    lock.withLock { for identifier in identifiers { pending.removeValue(forKey: identifier) } }
  }
  func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] { [] }
  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    await authorizationStatus() == .authorized
  }
  func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
  func insertExternal(_ identifier: String) {
    lock.withLock {
      pending[identifier] = UNNotificationRequest(
        identifier: identifier, content: UNMutableNotificationContent(), trigger: nil)
    }
  }
}
