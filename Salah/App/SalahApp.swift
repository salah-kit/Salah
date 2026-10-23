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
      let lang = AppLanguage(rawValue: raw)
    {
      if let override = lang.appleLanguagesOverride {
        defaults.set(override, forKey: "AppleLanguages")
      }
      // AppKit lays out right to left only with this default, read at launch.
      if let rightToLeft = lang.appleTextDirectionOverride {
        defaults.set(rightToLeft, forKey: "AppleTextDirection")
      }
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
        .background(WindowAppearanceSetter(setting: preferences.appearance))
        .environment(\.locale, appLocale)
        .environment(\.layoutDirection, appLayoutDirection)
    } label: {
      MenuBarLabel(
        item: prayerManager.menuBarItem(appName: appName, needsAttention: hasLocationAttention),
        layoutDirection: appLayoutDirection
      )
      .background(WindowOpenerBridge())
      .onChange(of: preferences.appearance) { AppAppearance.apply($1) }
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
    .defaultSize(width: 888, height: 411)
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

  func applicationWillFinishLaunching(_ notification: Notification) {
    AppAppearance.apply(Preferences.shared.appearance)
  }

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

/// The menu-bar label (`MenuBarItem`): the glyph or the speaker, and the status text, in the
/// system's menu-bar font.
///
/// It's a template, so it follows the menu bar's light or dark appearance. Two states carry
/// color, which a template drops, so they're drawn to a non-template image: the approaching
/// capsule, `label/on-accent` ink on `accent/fill`, legible on any wallpaper; and the
/// attention dot, `status/warning` in the glyph's top-trailing corner, with ink in the menu
/// bar's appearance.
private struct MenuBarLabel: View {
  let item: MenuBarItem
  let layoutDirection: LayoutDirection

  @Environment(\.colorScheme) private var colorScheme

  /// Whether the menu bar is dark. It follows the wallpaper, not only the app's appearance,
  /// so it's read from the status item's own window, as a template image would be tinted.
  private var menuBarIsDark: Bool {
    let statusWindow = NSApp.windows.first {
      String(describing: type(of: $0)).contains("StatusBar")
    }
    guard let appearance = statusWindow?.effectiveAppearance else { return colorScheme == .dark }
    return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }

  /// The glyph's and the speaker's frames, as Figma draws them.
  private enum Metrics {
    static let spacing: CGFloat = 5
    static let glyph: CGFloat = 20
    static let glyphSize: CGFloat = 11
    static let speaker: CGFloat = 17
    static let speakerSize: CGFloat = 15
    static let dot: CGFloat = 6
    /// The dot's offset inside the glyph's frame, from its top-trailing corner.
    static let dotInset = CGSize(width: 0, height: 2)
  }

  var body: some View {
    Group {
      if item.approaching || item.attention {
        coloredImage
      } else {
        content(ink: .primary, dot: nil)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: item.accessibilityLabel))
  }

  private func content(ink: Color, dot: Color?) -> some View {
    HStack(spacing: Metrics.spacing) {
      switch item.icon {
      case .none:
        EmptyView()
      case .speaker:
        Image(systemName: "speaker.wave.2.fill")
          .font(.system(size: Metrics.speakerSize))
          .frame(width: Metrics.speaker, height: Metrics.speaker)
          .overlay(alignment: .topTrailing) { attentionDot(dot) }
      case .glyph(let kind):
        Group {
          if let kind {
            PrayerGlyph(kind: kind)
          } else {
            Image(systemName: "moon.stars")
          }
        }
        .font(.system(size: Metrics.glyphSize))
        .frame(width: Metrics.glyph, height: Metrics.glyph)
        .overlay(alignment: .topTrailing) { attentionDot(dot) }
      }
      if !item.text.isEmpty {
        Text(verbatim: item.text).monospacedDigit()
      }
    }
    .foregroundStyle(ink)
    .environment(\.layoutDirection, layoutDirection)
  }

  @ViewBuilder
  private func attentionDot(_ color: Color?) -> some View {
    if let color {
      Circle()
        .fill(color)
        .frame(width: Metrics.dot, height: Metrics.dot)
        .offset(x: -Metrics.dotInset.width, y: Metrics.dotInset.height)
    }
  }

  /// The label as a non-template image: on the approaching capsule, or with the attention
  /// dot in its color.
  private var coloredImage: some View {
    let isDark = menuBarIsDark && !item.approaching
    let palette = SalahPalette(isDark: isDark)
    let ink = item.approaching ? palette.labelOnAccent.color : (isDark ? Color.white : .black)
    let renderer = ImageRenderer(
      content: content(ink: ink, dot: item.attention ? palette.warning.color : nil)
        .font(.system(size: NSFont.menuBarFont(ofSize: 0).pointSize))
        .modifier(ApproachingCapsule(isOn: item.approaching, fill: palette.accentFill.color))
    )
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    let nsImage = renderer.nsImage
    nsImage?.isTemplate = false
    return Group {
      if let nsImage {
        Image(nsImage: nsImage).renderingMode(.original)
      } else {
        content(ink: .primary, dot: nil)
      }
    }
  }
}

/// The approaching state's gold capsule: the item's full 24 pt height, 7 pt padding, radius 6.
private struct ApproachingCapsule: ViewModifier {
  let isOn: Bool
  let fill: Color

  func body(content: Content) -> some View {
    if isOn {
      content
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
    } else {
      content
    }
  }
}
