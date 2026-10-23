import Foundation

/// The first launch's welcome: which pages it shows and where it leaves Salah. Each
/// permission page gives its reason before macOS asks, and shows only while macOS hasn't
/// asked yet.
struct OnboardingFlow: Equatable {
  enum Page: Equatable, CaseIterable {
    /// What Salah does.
    case welcome
    /// Why Salah wants the location, then macOS's prompt, or a city instead.
    case location
    /// Why Salah wants to alert, then macOS's prompt, or not now.
    case notifications
  }

  /// Where the welcome leaves Salah's window.
  enum Destination: Equatable {
    case today
    /// The Location pane, to choose a city.
    case location
  }

  /// The pages, in order.
  let pages: [Page]
  /// The page shown.
  private(set) var index = 0
  /// Whether Choose a City… was picked: the welcome then ends on the Location pane.
  private(set) var choosesCity = false

  /// The welcome, then each permission macOS hasn't asked for yet: the location only
  /// while Salah follows it.
  init(asksForLocation: Bool, asksForNotifications: Bool) {
    pages =
      [.welcome] + (asksForLocation ? [.location] : [])
      + (asksForNotifications ? [.notifications] : [])
  }

  /// Whether a first launch shows the welcome at all: only while there's a permission to
  /// ask for. A Mac that answered both already, after an update, goes straight to Today.
  static func isNeeded(asksForLocation: Bool, asksForNotifications: Bool) -> Bool {
    asksForLocation || asksForNotifications
  }

  var page: Page { pages[index] }
  var isLastPage: Bool { index == pages.count - 1 }

  /// Moves to the next page, or returns where to go when the welcome ends.
  mutating func advance() -> Destination? {
    guard isLastPage else {
      index += 1
      return nil
    }
    return choosesCity ? .location : .today
  }

  /// Marks the welcome done and returns the pane Salah's window opens on. Choose a City…
  /// stops Salah following the location, so nothing asks for it later and the Location pane
  /// shows the city search; a refused location ends there too, to choose a city.
  @MainActor
  static func complete(
    at destination: Destination, locationWasDenied: Bool, preferences: Preferences
  ) -> WindowPane {
    preferences.onboardingCompleted = true
    if destination == .location { preferences.useCurrentLocation = false }
    return destination == .location || locationWasDenied ? .location : .today
  }

  /// Choose a City… on the location page: no prompt, and the welcome ends on the Location
  /// pane.
  mutating func chooseCity() -> Destination? {
    choosesCity = true
    return advance()
  }
}
