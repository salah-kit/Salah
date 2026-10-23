import AppKit
import SalahCore
import SalahUI
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
        .preferredColorScheme(preferences.appearance.colorScheme)
    } label: {
      MenuBarLabel(
        text: prayerManager.menuBarText,
        showIcon: prayerManager.preferences.displayIcon || hasLocationAttention,
        glyph: prayerManager.menuBarGlyph,
        isPlaying: prayerManager.menuBarIsPlaying,
        isApproaching: prayerManager.menuBarStatusTone == .imminent,
        attention: hasLocationAttention,
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
      .preferredColorScheme(preferences.appearance.colorScheme)
    }
    .defaultSize(width: 888, height: 520)
    .windowResizability(.contentMinSize)
    .commands { SalahCommands(locale: appLocale) }
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

/// The menu-bar label: the next prayer's glyph (the one that just began, while it counts
/// up) and the status text, in the system's menu-bar font.
///
/// It's a template, so it follows the menu bar's light or dark appearance, except while a
/// prayer approaches: then it sits on a gold capsule with dark ink, legible on any wallpaper.
/// `MenuBarExtra` draws its label as a template and drops colors, so that state is drawn to a
/// non-template image. While audio plays, a speaker stands in for the glyph. A permission
/// that's off adds a small dot.
private struct MenuBarLabel: View {
  let text: String
  let showIcon: Bool
  let glyph: PrayerKind?
  let isPlaying: Bool
  let isApproaching: Bool
  let attention: Bool
  let layoutDirection: LayoutDirection

  var body: some View {
    if isApproaching {
      approachingImage
    } else {
      content(font: nil, ink: .primary)
    }
  }

  @ViewBuilder
  private func content(font: Font?, ink: Color) -> some View {
    HStack(spacing: 5) {
      if showIcon || isPlaying {
        icon
          .overlay(alignment: .topTrailing) {
            if attention {
              Circle()
                .fill(.orange)
                .frame(width: 6, height: 6)
                .offset(x: 3, y: -2)
            }
          }
      }
      if !text.isEmpty {
        Text(text).monospacedDigit()
      }
    }
    .font(font)
    .foregroundStyle(ink)
    .environment(\.layoutDirection, layoutDirection)
  }

  @ViewBuilder
  private var icon: some View {
    if isPlaying {
      Image(systemName: "speaker.wave.2.fill")
    } else if let glyph {
      PrayerGlyph(kind: glyph)
    } else {
      Image(systemName: "moon.stars")
    }
  }

  /// The approaching state as a non-template image: the label in `label/on-accent` on an
  /// `accent/fill` capsule.
  private var approachingImage: some View {
    let palette = SalahPalette(isDark: false)
    let renderer = ImageRenderer(
      content: content(
        font: .system(size: NSFont.menuBarFont(ofSize: 0).pointSize),
        ink: palette.labelOnAccent.color
      )
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.accentFill.color))
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
        content(font: nil, ink: .primary)
      }
    }
  }
}
