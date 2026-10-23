import Foundation

/// How Salah opens, closes and quits: it lives in the menu bar, and has a Dock icon, a place
/// in ⌘-Tab and its own menus only while its window is open.
///
/// These are the decisions alone, so tests can check them; `AppWindowCoordinator` applies
/// them to AppKit. They follow the windows that are open, hidden and minimized ones
/// included, never their visibility or focus.
nonisolated struct AppLifecycle: Equatable, Sendable {
  /// How Salah shows itself.
  enum Presence: Equatable, Sendable {
    /// The menu bar item only: no Dock icon, not in ⌘-Tab, no menus.
    case menuBar
    /// The menu bar item, plus a Dock icon, a place in ⌘-Tab and Salah's menus.
    case regular
  }

  /// Where a request to quit came from.
  enum QuitSource: Equatable, Sendable {
    /// Quit Salah: the dropdown's power button or the button on Today.
    case quitSalah
    /// Logout, restart or shutdown.
    case sessionEnding
    /// Anything else: ⌘Q, the Dock icon's Quit, a quit Apple event.
    case other
  }

  /// The answer to a request to quit.
  enum QuitReply: Equatable, Sendable {
    /// Quit.
    case quit
    /// Keep running in the menu bar, and close the windows instead.
    case closeWindows
  }

  /// The windows open now, hidden and minimized ones included.
  private(set) var openWindows: Set<ObjectIdentifier> = []
  /// Whether the note that Salah keeps running has been shown. It's shown once.
  private(set) var hasShownCloseNote: Bool
  /// Whether Salah is quitting; the windows it closes on the way out show no note.
  private(set) var isQuitting = false

  init(hasShownCloseNote: Bool) {
    self.hasShownCloseNote = hasShownCloseNote
  }

  var presence: Presence { openWindows.isEmpty ? .menuBar : .regular }

  mutating func windowOpened(_ window: ObjectIdentifier) {
    openWindows.insert(window)
  }

  /// Forgets a window that closed, and returns whether to show the note now: the first
  /// time the last window closes, by any route, unless Salah is quitting.
  mutating func windowClosed(_ window: ObjectIdentifier) -> Bool {
    guard openWindows.remove(window) != nil, openWindows.isEmpty, !isQuitting,
      !hasShownCloseNote
    else { return false }
    hasShownCloseNote = true
    return true
  }

  /// Takes back a note that couldn't show, so the next time the last window closes shows it.
  mutating func closeNoteNotShown() {
    hasShownCloseNote = false
  }

  /// Answers a request to quit. Quit Salah and the end of the session quit; anything else
  /// closes the windows while one is open, and quits only when none is.
  mutating func quit(from source: QuitSource) -> QuitReply {
    if source == .other, !openWindows.isEmpty { return .closeWindows }
    isQuitting = true
    return .quit
  }

  /// Whether a launch opens the window: a login launch stays in the menu bar, quietly;
  /// opening Salah from Finder, Spotlight or a link opens it.
  static func opensWindowAtLaunch(asLoginItem: Bool) -> Bool {
    !asLoginItem
  }
}
