import Foundation
import Testing

/// What the welcome decides and changes, below its window: when it shows, that closing it
/// early changes nothing, and that Choose a City… is kept at once.
@MainActor
@Suite("Onboarding presenter", .serialized)
struct OnboardingPresenterTests {
  private let scratch = ScratchDefaults()

  private func makePresenter(
    _ preferences: Preferences, locationUndetermined: Bool, notificationsUndetermined: Bool,
    coordinatorUses: UseCounter = UseCounter()
  ) -> OnboardingPresenter {
    OnboardingPresenter(
      preferences: preferences,
      coordinator: {
        coordinatorUses.count += 1
        return AppWindowCoordinator(presence: NoPresence(), defaults: ScratchDefaults().defaults)
      },
      locationUndetermined: { locationUndetermined },
      notificationsUndetermined: { notificationsUndetermined })
  }

  /// An unfinished welcome shows a page for each permission macOS hasn't asked for.
  @Test func anUnfinishedWelcomeShowsWhatIsLeftToAsk() async {
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.useCurrentLocation = true
    let presenter = makePresenter(
      preferences, locationUndetermined: true, notificationsUndetermined: true)
    let flow = await presenter.decide()
    #expect(flow?.pages == [.welcome, .location, .notifications])
    #expect(!preferences.onboardingCompleted, "Showing it doesn't finish it")
  }

  /// With nothing left to ask, as on a Mac that answered both, or after a city was chosen,
  /// the welcome is marked done and doesn't show.
  @Test func nothingLeftToAskMarksTheWelcomeDone() async {
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.useCurrentLocation = false
    let presenter = makePresenter(
      preferences, locationUndetermined: true, notificationsUndetermined: false)
    #expect(!preferences.onboardingCompleted)
    #expect(await presenter.decide() == nil)
    #expect(preferences.onboardingCompleted)
  }

  /// A finished welcome never shows again, whatever macOS says.
  @Test func aFinishedWelcomeStaysDone() async {
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.onboardingCompleted = true
    preferences.useCurrentLocation = true
    let presenter = makePresenter(
      preferences, locationUndetermined: true, notificationsUndetermined: true)
    #expect(await presenter.decide() == nil)
  }

  /// Closing the welcome early, or finishing after it closed (macOS answering a prompt the
  /// welcome asked before it closed), changes no preference and opens nothing.
  @Test func closingEarlyChangesNothing() {
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.useCurrentLocation = true
    let uses = UseCounter()
    let presenter = makePresenter(
      preferences, locationUndetermined: true, notificationsUndetermined: true,
      coordinatorUses: uses)
    presenter.windowWillClose()
    presenter.finish(at: .location)
    presenter.finish(at: .today)
    #expect(!preferences.onboardingCompleted)
    #expect(preferences.useCurrentLocation)
    #expect(!preferences.notificationPromptDeferred)
    #expect(uses.count == 0, "Salah's window doesn't open")
  }

  /// Choose a City… stops following the location at once, so a welcome closed afterwards
  /// doesn't ask for the location again.
  @Test func choosingACityIsKeptAtOnce() async {
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.useCurrentLocation = true
    let presenter = makePresenter(
      preferences, locationUndetermined: true, notificationsUndetermined: true)
    presenter.choseCity()
    presenter.windowWillClose()
    #expect(!preferences.useCurrentLocation)
    #expect(await presenter.decide()?.pages == [.welcome, .notifications])
  }

  /// Salah follows the location on its own only once the welcome is done or macOS has
  /// answered: before that, the welcome's page is the first to ask.
  @Test func salahFollowsTheLocationOnceTheWelcomeOrMacOSHasDecided() {
    #expect(!OnboardingFlow.mayFollowLocation(onboardingCompleted: false, locationDecided: false))
    #expect(OnboardingFlow.mayFollowLocation(onboardingCompleted: false, locationDecided: true))
    #expect(OnboardingFlow.mayFollowLocation(onboardingCompleted: true, locationDecided: false))
  }
}

@MainActor
private final class UseCounter {
  var count = 0
}

@MainActor
private final class NoPresence: AppPresenceControlling {
  func setPresence(_ presence: AppLifecycle.Presence) {}
  func bringForward() {}
  func terminate() {}
}
