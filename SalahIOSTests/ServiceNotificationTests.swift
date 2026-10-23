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
    let service = IOSNotificationService(center: center, files: files, now: { now })
    await service.refresh(
      schedule: preferences.mirror?.schedule, preferences: preferences, now: now)
    center.insertExternal("unrelated")
    center.setAuthorization(.denied)
    await service.refresh(
      schedule: preferences.mirror?.schedule, preferences: preferences, now: now)
    #expect(service.status == .denied)
    #expect(service.report?.confirmed.isEmpty == true)
    #expect(try await center.pendingNotificationRequests().map(\.identifier) == ["unrelated"])
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
