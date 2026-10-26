import Foundation
import Observation
import SalahCore

nonisolated enum TVTab: String, CaseIterable, Sendable {
  case today, week, settings
}

/// The moments that take the whole screen and hide the tab bar. Back leaves them.
nonisolated enum TVFullScreen: Hashable, Identifiable, Sendable {
  /// The day's times kept on screen, with the screen saver off.
  case roomDisplay
  /// A prayer's adhan, playing while Salah is open.
  case adhan(PrayerEvent)

  var id: String {
    switch self {
    case .roomDisplay: "room"
    case .adhan(let event): "adhan/" + event.id
    }
  }
}

/// Where the app is: the selected tab, a full-screen moment and the Settings stack. Links
/// from the Top Shelf arrive here.
@MainActor @Observable
final class TVNavigation {
  var selectedTab: TVTab = .today
  var settingsPath: [TVSettingsRoute] = []
  private(set) var fullScreen: TVFullScreen?
  /// The room display the adhan took over, to return to when it ends.
  @ObservationIgnored private var resumesRoomDisplay = false

  func open(_ route: TVRoute) {
    switch route {
    case .today: show(tab: .today)
    case .week: show(tab: .week)
    case .settings: show(tab: .settings)
    case .roomDisplay:
      if case .adhan = fullScreen {
        resumesRoomDisplay = true
      } else {
        fullScreen = .roomDisplay
      }
    }
  }

  /// Opens a link such as `salah://room`; anything else is ignored.
  func handle(url: URL) {
    guard let route = TVRoute(url: url) else { return }
    open(route)
  }

  func showRoomDisplay() { open(.roomDisplay) }

  /// Shows the adhan over whatever is on screen, the room display included.
  func showAdhan(for event: PrayerEvent) {
    if fullScreen == .roomDisplay { resumesRoomDisplay = true }
    fullScreen = .adhan(event)
  }

  /// Leaves the adhan; the room display comes back if the adhan interrupted it.
  func adhanEnded() {
    guard case .adhan = fullScreen else { return }
    fullScreen = resumesRoomDisplay ? .roomDisplay : nil
    resumesRoomDisplay = false
  }

  /// Back from a full-screen moment.
  func dismissFullScreen() {
    resumesRoomDisplay = false
    fullScreen = nil
  }

  /// A tab from a link. The adhan stays up with the tab selected underneath, and ends on it.
  private func show(tab: TVTab) {
    if case .adhan = fullScreen {
      resumesRoomDisplay = false
    } else {
      dismissFullScreen()
    }
    selectedTab = tab
  }
}
