import AppKit

/// Salah's Appearance setting, applied to the whole app through `NSApp.appearance`: the
/// window, the dropdown, the note and every panel follow it, and System follows macOS as it
/// changes. A scene's `preferredColorScheme` can't do this: a window it made light stays
/// light when it goes back to nil.
@MainActor
enum AppAppearance {
  /// The app's appearance for a setting: none for System, so macOS's applies.
  static func appearance(for setting: SalahAppearance) -> NSAppearance? {
    switch setting {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }

  static func apply(_ setting: SalahAppearance, to app: NSApplication = .shared) {
    app.appearance = appearance(for: setting)
  }
}
