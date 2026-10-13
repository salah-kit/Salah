import Testing

/// Locks the failure taxonomy that drives the whole surfacing policy: if these
/// mappings drift, transient failures could start interrupting the user (or
/// terminal ones could go silent).
@Suite struct FailureCategoryTests {
  @Test func locationFailureCategoryMapping() {
    #expect(LocationFailure.denied.category == .terminal)
    #expect(LocationFailure.restricted.category == .terminal)
    #expect(LocationFailure.network.category == .transient)
    #expect(LocationFailure.unavailable.category == .transient)
  }

  @Test func prayerCalcFailureIsTerminal() {
    #expect(PrayerCalcFailure.timesUnavailable(latitude: 0, longitude: 0).category == .terminal)
  }

  @Test func everyLocationFailureLogsADistinctCause() {
    let causes: [LocationFailure] = [.denied, .restricted, .network, .unavailable]
    let messages = causes.map(\.logMessage)
    #expect(
      Set(messages).count == causes.count, "Each location failure should log a distinct cause")
  }
}
