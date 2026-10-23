import AppKit
import CoreLocation
import OSLog
import SalahAlerts
import SwiftUI
import UserNotifications

/// Shows the first launch's welcome in a small window of its own, which gives Salah its
/// Dock icon while it's open, and opens Salah's window when it ends.
@MainActor
final class OnboardingPresenter {
  static let shared = OnboardingPresenter()

  private var window: NSWindow?
  private var closeObserver: (any NSObjectProtocol)?
  /// The welcome is ending on its own terms, not closed early.
  private var isFinishing = false
  /// macOS refused the location: the welcome ends on the Location pane, to choose a city.
  private var locationWasDenied = false
  private let preferences: Preferences

  init(preferences: Preferences = .shared) {
    self.preferences = preferences
  }

  /// Shows the welcome when this is the first launch and there's a permission to ask for;
  /// otherwise marks it done and calls `otherwise`, which opens Salah's window.
  func start(otherwise: @escaping @MainActor () -> Void) {
    let forced = Self.isForced(preferences)
    guard forced || !preferences.onboardingCompleted else {
      otherwise()
      return
    }
    Task {
      let asksForLocation =
        forced
        || (preferences.useCurrentLocation
          && CLLocationManager().authorizationStatus == .notDetermined)
      let notificationStatus = await notificationCenter.authorizationStatus()
      let asksForNotifications = forced || notificationStatus == .notDetermined
      guard
        OnboardingFlow.isNeeded(
          asksForLocation: asksForLocation, asksForNotifications: asksForNotifications)
      else {
        preferences.onboardingCompleted = true
        otherwise()
        return
      }
      present(
        OnboardingFlow(
          asksForLocation: asksForLocation, asksForNotifications: asksForNotifications))
    }
  }

  // MARK: - Window

  private func present(_ flow: OnboardingFlow) {
    let view = OnboardingView(
      flow: flow,
      allowLocation: { [weak self] in await self?.requestLocation() },
      allowNotifications: { [weak self] in await self?.requestNotifications() },
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
    AppWindowCoordinator.shared.attachOnboarding(window)
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    AppLog.lifecycle.notice("onboarding shown pages=\(flow.pages.count, privacy: .public)")
  }

  /// The welcome ends: it's done for good, and Salah's window opens on the destination. The
  /// welcome closes once that window is up, so Salah keeps its Dock icon throughout.
  private func finish(at destination: OnboardingFlow.Destination) {
    // Closed while macOS was asking: nothing more opens.
    guard window != nil, !isFinishing else { return }
    isFinishing = true
    preferences.onboardingCompleted = true
    // Choose a City…: Salah stops following the location, so nothing asks for it later and
    // the Location pane shows the city search.
    if destination == .location { preferences.useCurrentLocation = false }
    AppWindowCoordinator.shared.endOnboarding()
    AppWindowCoordinator.shared.open(
      destination == .location || locationWasDenied ? .location : .today)
  }

  /// Closing the welcome early counts as done, and as Not Now for what it didn't ask: Salah
  /// stays in the menu bar and asks for nothing on its own.
  private func windowWillClose() {
    if !isFinishing {
      preferences.notificationPromptDeferred = true
      if preferences.useCurrentLocation,
        CLLocationManager().authorizationStatus == .notDetermined
      {
        preferences.useCurrentLocation = false
      }
    }
    preferences.onboardingCompleted = true
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
      _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
    } catch {
      AppLog.notifications.error(
        "Failed to request notification authorization: \(error.localizedDescription, privacy: .public)"
      )
    }
    // Replan, so the alerts reach the system's center now that Salah may post them.
    notifyChange()
  }

  private var notificationCenter: any PrayerNotificationCenter {
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
