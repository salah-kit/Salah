import AppKit
import SwiftUI

@main
struct SalahApp: App {
  @NSApplicationDelegateAdaptor(SalahAppDelegate.self) private var appDelegate

  // Run BEFORE @State property initialization so the AppleLanguages override
  // is in place before any Bundle.preferredLocalizations cache forms. This is
  // what makes the system's menus and windows use the localized
  // CFBundleDisplayName (صلاة / Salah) instead of always English.
  init() {
    let defaults = Preferences.sharedDefaults
    if let raw = defaults.string(forKey: Preferences.Key.appLanguage),
      let lang = AppLanguage(rawValue: raw),
      let override = lang.appleLanguagesOverride
    {
      defaults.set(override, forKey: "AppleLanguages")
    }
  }

  @State private var prayerManager = PrayerManager()
  @State private var preferences = Preferences.shared

  private var appLocale: Locale {
    preferences.appLanguage.locale
  }

  private var appLayoutDirection: LayoutDirection {
    appLocale.preferredLayoutDirection
  }

  /// Salah's name in the app's language: صلاة in Arabic.
  private var appName: String {
    String(
      localized: LocalizedStringResource(
        "CFBundleDisplayName", table: "InfoPlist", locale: appLocale,
        bundle: AppResources.localizationBundle))
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarDropdownView(prayerManager: prayerManager)
        .background(WindowTitleSetter(title: appName))
        .environment(\.locale, appLocale)
        .environment(\.layoutDirection, appLayoutDirection)
    } label: {
      MenuBarLabel(
        text: prayerManager.statusBarText,
        showIcon: prayerManager.preferences.displayIcon || hasLocationAttention,
        attention: hasLocationAttention,
        tint: menuBarTint,
        layoutDirection: appLayoutDirection
      )
      .background(WindowOpenerBridge())
    }
    .menuBarExtraStyle(.window)

    // Salah's one window. It opens only when a person asks (`AppWindowCoordinator`), and
    // gives Salah its Dock icon and menus while it's open.
    Window(Text(verbatim: appName), id: AppWindowCoordinator.windowID) {
      SalahWindowView(
        prayerManager: prayerManager, navigation: AppWindowCoordinator.shared.navigation
      )
      .environment(\.locale, appLocale)
      .environment(\.layoutDirection, appLayoutDirection)
    }
    .defaultSize(width: 888, height: 520)
    .windowResizability(.contentMinSize)
    .commands { SalahCommands(locale: appLocale) }
  }

  /// Menu-bar tint for the current state, or `nil` for the normal state. `nil`
  /// keeps the system's default template rendering (the text auto-adapts to a
  /// light or dark menu bar); a non-nil color is drawn explicitly by
  /// `MenuBarLabel`, since `MenuBarExtra` otherwise strips its label's colors.
  private var menuBarTint: Color? {
    switch prayerManager.menuBarStatusTone {
    case .normal: nil
    case .imminent: .red
    case .playingPreReminderAudio: .orange
    case .playingPrayerAudio: .green
    case .playingPostReminderAudio: .purple
    }
  }

  /// A live terminal failure (e.g. location permission denied) badges the
  /// menu-bar icon so the user knows something needs attention - without a modal.
  private var hasLocationAttention: Bool {
    FailureReporter.shared.currentNotice?.category == .terminal
  }
}

/// Salah's lifecycle callbacks, handed to `AppWindowCoordinator`: the launch, Finder's and
/// the Dock's reopen, a widget's link, and quitting.
final class SalahAppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: AppWindowCoordinator { .shared }

  func applicationDidFinishLaunching(_ notification: Notification) {
    coordinator.didFinishLaunching(
      asLoginItem: AppWindowCoordinator.isLoginItemLaunch(
        NSAppleEventManager.shared().currentAppleEvent))
  }

  /// Finder, Spotlight or the Dock icon, while Salah runs: open or focus the window.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    coordinator.open()
    return false
  }

  /// A widget's tap opens Salah's window, as Open Salah does.
  func application(_ application: NSApplication, open urls: [URL]) {
    guard urls.contains(where: { $0.scheme == SalahWidgetConstants.deepLinkScheme }) else { return }
    coordinator.open()
  }

  /// Salah keeps running in the menu bar when its last window closes.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// ⌘Q closes the window to the menu bar; Quit Salah, logout, restart and shutdown quit.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    coordinator.shouldTerminate(appleEvent: NSAppleEventManager.shared().currentAppleEvent)
  }
}

/// The window's menu commands: About and Help open Salah's own, and Settings… (⌘,) opens
/// the window at General.
private struct SalahCommands: Commands {
  let locale: Locale

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button(localizedString("menu.about.help", locale: locale)) {
        AppSupportActions.openAboutPanel()
      }
    }
    CommandGroup(replacing: .appSettings) {
      Button(localizedString("menu.settingsEllipsis", locale: locale)) {
        AppWindowCoordinator.shared.open(.general)
      }
      .keyboardShortcut(",", modifiers: .command)
    }
    CommandGroup(replacing: .help) {
      Button(localizedString("menu.help.help", locale: locale)) {
        AppSupportActions.openHelp()
      }
    }
  }
}

/// The menu-bar label (icon + status text).
///
/// macOS renders a `MenuBarExtra` label as a monochrome *template*: it discards
/// any SwiftUI foreground color, so the imminent-red / count-up-green tint never
/// reached the menu bar (it stayed default-colored). The original app colored the
/// status item via `NSStatusItem`'s `attributedTitle` + `NSForegroundColorAttribute`;
/// we keep the SwiftUI `MenuBarExtra` (and its popover) and get the same result by
/// rasterizing the tinted label to a **non-template** image with `ImageRenderer`,
/// which the status item then shows in full color.
///
/// The normal (untinted) state stays a plain SwiftUI label, so it keeps the
/// system template behavior and auto-adapts to a light or dark menu bar.
private struct MenuBarLabel: View {
  let text: String
  let showIcon: Bool
  let attention: Bool
  /// Non-nil only for a colored state (imminent / playing); `nil` = normal.
  let tint: Color?
  let layoutDirection: LayoutDirection

  var body: some View {
    if let tint {
      tintedImage(tint)
    } else {
      content(font: nil, color: .primary)
    }
  }

  @ViewBuilder
  private func content(font: Font?, color: Color) -> some View {
    HStack(spacing: 4) {
      if showIcon {
        Image(systemName: "moon.stars")
          .overlay(alignment: .topTrailing) {
            if attention {
              Circle()
                .fill(.orange)
                .frame(width: 5, height: 5)
                .offset(x: 3, y: -2)
            }
          }
      }
      if !text.isEmpty {
        Text(text)
      }
    }
    .font(font)
    .foregroundStyle(color)
    .environment(\.layoutDirection, layoutDirection)
  }

  /// Rasterize the tinted label to a non-template image (see the type comment).
  /// The raster needs an explicit menu-bar font since it leaves the live view
  /// tree; the normal path inherits the system menu-bar font as before.
  private func tintedImage(_ tint: Color) -> some View {
    let renderer = ImageRenderer(
      content: content(font: .system(size: NSFont.menuBarFont(ofSize: 0).pointSize), color: tint)
    )
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    let nsImage = renderer.nsImage
    nsImage?.isTemplate = false
    return Group {
      if let nsImage {
        // The image carries the text as pixels only; VoiceOver reads it from here.
        Image(nsImage: nsImage).renderingMode(.original)
          .accessibilityLabel(Text(verbatim: text))
      } else {
        content(font: nil, color: tint)
      }
    }
  }
}
