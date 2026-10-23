import Testing

/// The first launch's welcome: its pages follow what macOS hasn't asked yet, and it ends
/// on Today, or on the Location pane after Choose a City….
@Suite("Onboarding")
struct OnboardingFlowTests {
  /// A first launch with both permissions unasked: the welcome, then the location, then
  /// the notifications, ending on Today.
  @Test func aFirstLaunchAsksForBothThenOpensToday() {
    var flow = OnboardingFlow(asksForLocation: true, asksForNotifications: true)
    #expect(flow.pages == [.welcome, .location, .notifications])
    #expect(flow.page == .welcome)
    #expect(flow.advance() == nil)
    #expect(flow.page == .location)
    #expect(flow.advance() == nil)
    #expect(flow.page == .notifications)
    #expect(flow.isLastPage)
    #expect(flow.advance() == .today)
  }

  /// Choose a City… skips the location prompt and ends the welcome on the Location pane,
  /// after the notifications page.
  @Test func choosingACityEndsOnTheLocationPane() {
    var flow = OnboardingFlow(asksForLocation: true, asksForNotifications: true)
    _ = flow.advance()
    #expect(flow.chooseCity() == nil)
    #expect(flow.page == .notifications)
    #expect(flow.advance() == .location)

    var withoutNotifications = OnboardingFlow(asksForLocation: true, asksForNotifications: false)
    _ = withoutNotifications.advance()
    #expect(withoutNotifications.chooseCity() == .location)
  }

  /// A page shows only for a permission macOS hasn't asked for; with none to ask for, an
  /// updated Mac skips the welcome.
  @Test func pagesFollowWhatIsLeftToAsk() {
    #expect(
      OnboardingFlow(asksForLocation: false, asksForNotifications: true).pages
        == [.welcome, .notifications])
    #expect(
      OnboardingFlow(asksForLocation: true, asksForNotifications: false).pages
        == [.welcome, .location])
    #expect(OnboardingFlow.isNeeded(asksForLocation: false, asksForNotifications: true))
    #expect(OnboardingFlow.isNeeded(asksForLocation: true, asksForNotifications: false))
    #expect(!OnboardingFlow.isNeeded(asksForLocation: false, asksForNotifications: false))
  }
}
