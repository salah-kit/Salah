import Foundation
import SalahAlerts
import SalahCore
import Testing
import UserNotifications

@Suite("Clock rollback after an early report")
struct ClockRollbackTests {
  init() { TestEnvironment.configure() }

  @Test func deliveredEarlyOccurrenceStaysExcludedAfterASubsecondRollback() async throws {
    let fire = Fixture.event(.asr).time
    let rig = PrayerAlertCoordinatorTests.Harness(
      now: fire.addingTimeInterval(-60), settings: [.asr: .alert(sound: .makkah)],
      othersOff: true)
    await rig.update()
    let identifier = PrayerAlertCoordinatorTests.identifier(.asr, .atTime)
    rig.clock.now = fire.addingTimeInterval(-1)
    rig.coordinator.resync()
    await rig.settle()
    #expect(rig.audio.plays.count == 1)
    #expect(rig.pendingIdentifiers.contains(identifier))

    // A normal replan in the early window must keep the system's pending request.
    await rig.update()
    #expect(rig.pendingIdentifiers.contains(identifier))
    await rig.wake(at: fire.addingTimeInterval(-1))
    #expect(rig.pendingIdentifiers.contains(identifier))
    let pending = try #require(rig.center.pendingRequest(identifier))
    // Model the system moving the request from pending to delivered at its fire date.
    rig.clock.now = fire
    try await rig.center.add(
      UNNotificationRequest(identifier: identifier, content: pending.content, trigger: nil))
    #expect(
      rig.center.delivered == [DeliveredNotificationRecord(identifier: identifier, date: fire)])
    #expect(!rig.pendingIdentifiers.contains(identifier))

    // This rollback is later than the early report but earlier than actual delivery.
    rig.clock.now = fire.addingTimeInterval(-0.5)
    rig.coordinator.catchUp(schedule: Fixture.schedule(), afterClockChange: true)
    await rig.settle()
    #expect(!rig.pendingIdentifiers.contains(identifier))
    #expect(rig.center.posted.count == 1)  // Only the simulated system delivery above.
    #expect(rig.audio.plays.count == 1)
  }

  @Test func newlyReportedEarlyOccurrenceKeepsItsPendingRequestOnWake() async {
    let fire = Fixture.event(.asr).time
    let rig = PrayerAlertCoordinatorTests.Harness(
      now: fire.addingTimeInterval(-60), settings: [.asr: .alert(sound: .makkah)],
      othersOff: true)
    await rig.update()
    await rig.wake(at: fire.addingTimeInterval(-1))
    #expect(rig.audio.plays.count == 1)
    #expect(rig.pendingIdentifiers.contains(PrayerAlertCoordinatorTests.identifier(.asr, .atTime)))
    #expect(rig.center.posted.isEmpty)
  }
}
