import AppKit
import Testing

/// What the welcome decides and changes, below its window: when it shows, that closing it
/// early changes nothing, and that Choose a City… is kept at once.
@MainActor
@Suite("Onboarding presenter", .serialized)
struct OnboardingPresenterTests {
  private let scratch = ScratchDefaults()

  private func makePresenter(
    _ preferences: Preferences, locationUndetermined: Bool, notificationsUndetermined: Bool,
    presence: PresenceCounter = PresenceCounter()
  ) -> OnboardingPresenter {
    let coordinator = AppWindowCoordinator(
      presence: presence, defaults: scratch.defaults, startOnboarding: { $0() })
    return OnboardingPresenter(
      preferences: preferences, coordinator: { coordinator },
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

  /// Closing the welcome early, then finishing (macOS answering a prompt the welcome asked
  /// before it closed), changes no preference and opens nothing.
  @Test func closingEarlyChangesNothing() {
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.useCurrentLocation = true
    let presence = PresenceCounter()
    let presenter = makePresenter(
      preferences, locationUndetermined: true, notificationsUndetermined: true,
      presence: presence)
    let welcome = makeWindow()
    presenter.adopt(welcome)
    #expect(presence.presences == [.regular], "The welcome is Salah's open window")
    welcome.close()
    presenter.finish(at: .location)
    presenter.finish(at: .today)
    #expect(!preferences.onboardingCompleted)
    #expect(preferences.useCurrentLocation)
    #expect(!preferences.notificationPromptDeferred)
    #expect(presence.bringForwards == 0, "Salah's window doesn't open")
    #expect(presence.presences == [.regular, .menuBar])
  }

  /// Finishing an open welcome marks it done and opens Salah's window.
  @Test func finishingOpensSalah() {
    let preferences = Preferences(defaults: scratch.defaults)
    let presence = PresenceCounter()
    let presenter = makePresenter(
      preferences, locationUndetermined: true, notificationsUndetermined: true,
      presence: presence)
    let welcome = makeWindow()
    defer { welcome.close() }
    presenter.adopt(welcome)
    presenter.finish(at: .today)
    #expect(preferences.onboardingCompleted)
    #expect(presence.bringForwards == 1, "Salah's window opens")
  }

  /// Choose a City… stops following the location at once, so a welcome closed afterwards
  /// doesn't ask for the location again.
  @Test func choosingACityIsKeptAtOnce() async {
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.useCurrentLocation = true
    let presenter = makePresenter(
      preferences, locationUndetermined: true, notificationsUndetermined: true)
    let welcome = makeWindow()
    presenter.adopt(welcome)
    presenter.choseCity()
    welcome.close()
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
private func makeWindow() -> NSWindow {
  _ = NSApplication.shared
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
    styleMask: [.titled, .closable], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.orderFront(nil)
  return window
}

@MainActor
private final class PresenceCounter: AppPresenceControlling {
  var presences: [AppLifecycle.Presence] = []
  var bringForwards = 0

  func setPresence(_ presence: AppLifecycle.Presence) {
    if presences.last != presence { presences.append(presence) }
  }
  func bringForward() { bringForwards += 1 }
  func terminate() {}
}
