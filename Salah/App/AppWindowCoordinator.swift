import AppKit
import OSLog
import SwiftUI

/// What the coordinator changes in the running app. Test seam: the unit tests pass a
/// recorder instead of the app.
@MainActor
protocol AppPresenceControlling: AnyObject {
  /// Shows Salah in the Dock, ⌘-Tab and the menu bar's menus, or in the menu bar only.
  func setPresence(_ presence: AppLifecycle.Presence)
  /// Unhides Salah and makes it the active app.
  func bringForward()
  /// Asks the app to quit, through `applicationShouldTerminate`.
  func terminate()
}

/// The running app.
@MainActor
final class SystemAppPresence: AppPresenceControlling {
  func setPresence(_ presence: AppLifecycle.Presence) {
    let policy: NSApplication.ActivationPolicy = presence == .regular ? .regular : .accessory
    guard NSApp.activationPolicy() != policy else { return }
    NSApp.setActivationPolicy(policy)
  }

  func bringForward() {
    NSApp.unhide(nil)
    NSApp.activate()
  }

  func terminate() {
    NSApp.terminate(nil)
  }
}

/// Owns Salah's window and how Salah shows itself: in the menu bar only, or, while the
/// window is open (hidden or minimized included), with a Dock icon, a place in ⌘-Tab and its
/// own menus. It applies `AppLifecycle`'s decisions.
///
/// Only a person's action opens the window or brings it forward: Open Salah, ⌘,, the Dock
/// icon, Finder, Spotlight, a widget's link. The prayer schedule, the alerts and the audio
/// live outside the window, in `PrayerManager`, so they never restart when it opens or closes.
@MainActor
final class AppWindowCoordinator {
  static let shared = AppWindowCoordinator()

  /// The window scene's identifier.
  static let windowID = "salah"
  /// The window's accessibility identifier.
  static let windowAccessibilityIdentifier = "salah.window"
  /// Whether the note that Salah keeps running has been shown, in `Preferences.sharedDefaults`.
  static let closeNoteShownKey = "salah.closeNoteShown"

  /// The pane the window shows.
  let navigation = WindowNavigation()
  private(set) var lifecycle: AppLifecycle

  private let presence: any AppPresenceControlling
  private let defaults: UserDefaults
  /// Shows the note, and returns whether it could.
  private let showCloseNote: @MainActor () -> Bool
  /// Closes the note if it's showing.
  private let dismissCloseNote: @MainActor () -> Void

  private var openWindow: (() -> Void)?
  private var hasPendingOpen = false
  private var windows: [ObjectIdentifier: NSWindow] = [:]
  private var closeObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]
  /// A login launch, until a person opens the window: a window SwiftUI opens by itself
  /// meanwhile closes again (macOS 14 opens the window scene at launch).
  private var isQuietLaunch = false
  private var isQuitSalahRequested = false
  /// When macOS last said the session is ending. A logout another app cancels leaves it
  /// set, so it counts for two minutes only.
  private var sessionEndingSince: Date?
  private var isSessionEnding: Bool {
    sessionEndingSince.map { Date().timeIntervalSince($0) < 120 } ?? false
  }
  private var powerOffObserver: (any NSObjectProtocol)?

  init(
    presence: any AppPresenceControlling = SystemAppPresence(),
    defaults: UserDefaults = Preferences.sharedDefaults,
    showCloseNote: @escaping @MainActor () -> Bool = { CloseNotePresenter.shared.show() },
    dismissCloseNote: @escaping @MainActor () -> Void = { CloseNotePresenter.shared.dismiss() }
  ) {
    self.presence = presence
    self.defaults = defaults
    self.showCloseNote = showCloseNote
    self.dismissCloseNote = dismissCloseNote
    lifecycle = AppLifecycle(hasShownCloseNote: defaults.bool(forKey: Self.closeNoteShownKey))
  }

  // MARK: - Launch

  /// Called once the app has finished launching: opens the window unless macOS launched
  /// Salah as a login item.
  func didFinishLaunching(asLoginItem: Bool) {
    // Logout, restart and shutdown never wait for Salah, even if their quit event says
    // nothing about why it was sent.
    powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.sessionEndingSince = Date() }
    }
    if AppLifecycle.opensWindowAtLaunch(asLoginItem: asLoginItem) {
      open()
    } else {
      isQuietLaunch = true
    }
  }

  /// Registered by the scenes once SwiftUI's `openWindow` is available.
  func register(openWindow: @escaping () -> Void) {
    self.openWindow = openWindow
    if hasPendingOpen {
      hasPendingOpen = false
      openWindow()
    }
  }

  // MARK: - Opening

  /// Opens the window, or brings it forward and restores it if it's minimized; never a
  /// second one. It shows `pane`, or the last pane without one (Today the first time).
  func open(_ pane: WindowPane? = nil) {
    if let pane { navigation.pane = pane }
    isQuietLaunch = false
    sessionEndingSince = nil
    dismissCloseNote()
    presence.bringForward()
    if let window = windows.values.first {
      if window.isMiniaturized { window.deminiaturize(nil) }
      window.makeKeyAndOrderFront(nil)
    } else if let openWindow {
      openWindow()
    } else {
      hasPendingOpen = true
    }
  }

  /// Called by the window's content once AppKit has put it in a window.
  func attach(_ window: NSWindow) {
    let id = ObjectIdentifier(window)
    guard windows[id] == nil else { return }
    guard !isQuietLaunch else {
      window.close()
      return
    }
    windows[id] = window
    window.isRestorable = false
    window.tabbingMode = .disallowed
    window.setAccessibilityIdentifier(Self.windowAccessibilityIdentifier)
    closeObservers[id] = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.windowWillClose(id) }
    }
    lifecycle.windowOpened(id)
    presence.setPresence(lifecycle.presence)
    AppLog.lifecycle.notice("window opened windows=\(self.windows.count, privacy: .public)")
  }

  private func windowWillClose(_ id: ObjectIdentifier) {
    windows[id] = nil
    if let observer = closeObservers.removeValue(forKey: id) {
      NotificationCenter.default.removeObserver(observer)
    }
    let showsNote = lifecycle.windowClosed(id)
    presence.setPresence(lifecycle.presence)
    let shown = showsNote && showCloseNote()
    if shown {
      defaults.set(true, forKey: Self.closeNoteShownKey)
    } else if showsNote {
      lifecycle.closeNoteNotShown()
    }
    AppLog.lifecycle.notice(
      "window closed windows=\(self.windows.count, privacy: .public) note=\(showsNote, privacy: .public) shown=\(shown, privacy: .public)"
    )
  }

  // MARK: - Quitting

  /// Quit Salah: stops it completely, the menu bar item, the countdown and the adhan included.
  func quitSalah() {
    isQuitSalahRequested = true
    presence.terminate()
  }

  /// The answer to `applicationShouldTerminate`: quit for Quit Salah and the end of the
  /// session; otherwise, while the window is open, close it and keep running in the menu bar.
  func shouldTerminate(appleEvent: NSAppleEventDescriptor?) -> NSApplication.TerminateReply {
    let source: AppLifecycle.QuitSource =
      if isQuitSalahRequested {
        .quitSalah
      } else if isSessionEnding || Self.endsSession(appleEvent) {
        .sessionEnding
      } else {
        .other
      }
    switch lifecycle.quit(from: source) {
    case .quit:
      return .terminateNow
    case .closeWindows:
      for window in Array(windows.values) { window.close() }
      return .terminateCancel
    }
  }

  // MARK: - Apple events

  /// Whether a launch's Apple event says macOS opened Salah as a login item.
  nonisolated static func isLoginItemLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
    guard let event, event.eventClass == AEEventClass(kCoreEventClass),
      event.eventID == AEEventID(kAEOpenApplication)
    else { return false }
    return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
      == OSType(keyAELaunchedAsLogInItem)
  }

  /// Whether a quit Apple event comes from logout, restart or shutdown.
  nonisolated static func endsSession(_ event: NSAppleEventDescriptor?) -> Bool {
    guard let event, event.eventClass == AEEventClass(kCoreEventClass),
      event.eventID == AEEventID(kAEQuitApplication),
      let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
    else { return false }
    let sessionReasons: [OSType] = [
      kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart, kAEShowShutdownDialog,
      kAEShutDown,
    ]
    return sessionReasons.contains(reason)
  }
}

/// Zero-size view that captures SwiftUI's `openWindow` from a live scene (the menu-bar
/// label and the dropdown) for `AppWindowCoordinator`, which AppKit's callbacks reach
/// without a SwiftUI environment.
struct WindowOpenerBridge: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .accessibilityHidden(true)
      .onAppear {
        AppWindowCoordinator.shared.register {
          openWindow(id: AppWindowCoordinator.windowID)
        }
      }
  }
}

/// Hands the window that hosts it to `AppWindowCoordinator`: once AppKit has put the
/// content in one, and each time the window comes back on screen, since SwiftUI shows the
/// same window again when Salah's window reopens.
struct WindowAttacher: NSViewRepresentable {
  let attach: (NSWindow) -> Void

  func makeNSView(context: Context) -> AttachingView {
    let view = AttachingView()
    view.attach = attach
    return view
  }

  func updateNSView(_ nsView: AttachingView, context: Context) {
    nsView.attach = attach
  }

  final class AttachingView: NSView {
    var attach: ((NSWindow) -> Void)?
    private var shownObserver: (any NSObjectProtocol)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let shownObserver {
        NotificationCenter.default.removeObserver(shownObserver)
        self.shownObserver = nil
      }
      guard let window else { return }
      attach?(window)
      shownObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, let window = self.window, window.isVisible else { return }
          self.attach?(window)
        }
      }
    }
  }
}
