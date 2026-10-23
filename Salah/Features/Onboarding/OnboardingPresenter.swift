import AppKit
import CoreLocation
import OSLog
import SalahAlerts
import SwiftUI
import UserNotifications

/// Shows the welcome in a small window of its own, which gives Salah its Dock icon while
/// it's open, and opens Salah's window when it ends. Until it ends, Salah asks for no
/// permission on its own.
@MainActor
final class OnboardingPresenter {
  static let shared = OnboardingPresenter()

  private var window: NSWindow?
  private var closeObserver: (any NSObjectProtocol)?
  /// The welcome is ending through its buttons; a later close changes nothing.
  private var isFinishing = false
  /// macOS refused the location: the welcome ends on the Location pane, to choose a city.
  private var locationWasDenied = false
  private let preferences: Preferences
  private let coordinator: () -> AppWindowCoordinator
  /// Whether macOS hasn't asked for the location yet.
  private let locationUndetermined: () -> Bool
  /// Whether macOS hasn't asked to post notifications yet.
  private let notificationsUndetermined: () async -> Bool

  /// The defaults are the running app's; the tests pass their own.
  init(
    preferences: Preferences = .shared,
    coordinator: @escaping () -> AppWindowCoordinator = { .shared },
    locationUndetermined: (() -> Bool)? = nil,
    notificationsUndetermined: (() async -> Bool)? = nil
  ) {
    self.preferences = preferences
    self.coordinator = coordinator
    self.locationUndetermined =
      locationUndetermined ?? { CLLocationManager().authorizationStatus == .notDetermined }
    self.notificationsUndetermined =
      notificationsUndetermined ?? {
        await Self.notificationCenter.authorizationStatus() == .notDetermined
      }
  }

  /// Shows the welcome while it's unfinished and there's a permission to ask for; otherwise
  /// calls `otherwise`, which opens Salah's window.
  func start(otherwise: @escaping @MainActor () -> Void) {
    guard Self.isForced(preferences) || !preferences.onboardingCompleted else {
      otherwise()
      return
    }
    Task {
      if let flow = await decide() {
        present(flow)
      } else {
        otherwise()
      }
    }
  }

  /// The welcome to show, or nil when it's done. An unfinished welcome with nothing left to
  /// ask, as on a Mac that answered both already, is marked done.
  func decide() async -> OnboardingFlow? {
    let forced = Self.isForced(preferences)
    guard forced || !preferences.onboardingCompleted else { return nil }
    let asksForLocation = forced || (preferences.useCurrentLocation && locationUndetermined())
    let asksForNotifications = await notificationsUndetermined() || forced
    guard
      OnboardingFlow.isNeeded(
        asksForLocation: asksForLocation, asksForNotifications: asksForNotifications)
    else {
      preferences.onboardingCompleted = true
      return nil
    }
    return OnboardingFlow(
      asksForLocation: asksForLocation, asksForNotifications: asksForNotifications)
  }

  // MARK: - Window

  private func present(_ flow: OnboardingFlow) {
    let view = OnboardingView(
      flow: flow,
      allowLocation: { [weak self] in await self?.requestLocation() },
      allowNotifications: { [weak self] in await self?.requestNotifications() },
      chooseCity: { [weak self] in self?.choseCity() },
      deferNotifications: { [weak self] in self?.preferences.notificationPromptDeferred = true },
      finish: { [weak self] destination in self?.finish(at: destination) }
    )
    .environment(\.locale, .app)
    .environment(\.layoutDirection, Locale.app.preferredLayoutDirection)
    .preferredColorScheme(preferences.appearance.colorScheme)

    let window = NSWindow(
      contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.title = localizedString("onboarding.window", locale: .app)
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    // The content starts below the title bar, whose height the window adds as its safe area.
    window.contentViewController = NSHostingController(rootView: view)
    window.center()
    closeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.windowWillClose() }
    }
    self.window = window
    coordinator().attachOnboarding(window)
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    AppLog.lifecycle.notice("onboarding shown pages=\(flow.pages.count, privacy: .public)")
  }

  /// The welcome ends: it's done for good, and Salah's window opens on the destination. The
  /// welcome closes once that window is up, so Salah keeps its Dock icon throughout.
  func finish(at destination: OnboardingFlow.Destination) {
    // Closed while macOS was asking: nothing more opens.
    guard window != nil, !isFinishing else { return }
    isFinishing = true
    let pane = OnboardingFlow.complete(
      at: destination, locationWasDenied: locationWasDenied, preferences: preferences)
    coordinator().endOnboarding()
    coordinator().open(pane)
  }

  /// Choose a City… is a decision, kept at once: Salah stops following the location, so
  /// nothing asks for it later, even if the welcome then closes early.
  func choseCity() {
    preferences.useCurrentLocation = false
  }

  /// Closing the welcome early leaves it unfinished: Salah stays in the menu bar and asks for
  /// nothing on its own. The welcome shows again the first time Salah opens in a later run
  /// (`AppWindowCoordinator.open`), while there's still a permission to ask for.
  func windowWillClose() {
    if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    closeObserver = nil
    window = nil
  }

  // MARK: - Permissions

  private func requestLocation() async {
    if Self.withoutPrompts(preferences) { return }
    preferences.useCurrentLocation = true
    await LocationPermission().request()
    let status = CLLocationManager().authorizationStatus
    locationWasDenied = status == .denied || status == .restricted
    NotificationCenter.default.post(name: .startLocationUpdate, object: nil)
  }

  private func requestNotifications() async {
    if Self.withoutPrompts(preferences) { return }
    do {
      _ = try await Self.notificationCenter.requestAuthorization(options: [.alert, .sound])
    } catch {
      AppLog.notifications.error(
        "Failed to request notification authorization: \(error.localizedDescription, privacy: .public)"
      )
    }
    // Replan, so the alerts reach the system's center now that Salah may post them.
    notifyChange()
  }

  private static var notificationCenter: any PrayerNotificationCenter {
    #if DEBUG
      DebugOptions.notificationCenter() ?? UNUserNotificationCenter.current()
    #else
      UNUserNotificationCenter.current()
    #endif
  }

  private static func isForced(_ preferences: Preferences) -> Bool {
    #if DEBUG
      preferences.defaults.bool(forKey: DebugOptions.showsOnboardingKey)
    #else
      false
    #endif
  }

  private static func withoutPrompts(_ preferences: Preferences) -> Bool {
    #if DEBUG
      preferences.defaults.bool(forKey: DebugOptions.withoutSystemPromptsKey)
    #else
      false
    #endif
  }
}

/// Asks macOS for the location once, and returns when it has answered.
@MainActor
private final class LocationPermission: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var continuation: CheckedContinuation<Void, Never>?

  func request() async {
    guard manager.authorizationStatus == .notDetermined else { return }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      manager.delegate = self
      manager.requestWhenInUseAuthorization()
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    Task { @MainActor in
      guard status != .notDetermined else { return }
      self.continuation?.resume()
      self.continuation = nil
    }
  }
}
