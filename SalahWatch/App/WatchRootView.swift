import SwiftUI

/// The pages, top to bottom, once the iPhone has sent the preferences; until then, where to
/// set Salah up. The language chosen in Salah sets the locale, digits and direction.
struct WatchRootView: View {
  @Environment(WatchAppRuntime.self) private var runtime
  @Environment(IOSAppStore.self) private var store
  @Environment(\.colorSchemeContrast) private var contrast
  private var theme: WatchTheme { WatchTheme(contrast: contrast) }

  var body: some View {
    @Bindable var navigation = runtime.navigation
    NavigationStack {
      if let display = store.display {
        TabView(selection: $navigation.tab) {
          WatchNowView(display: display).tag(WatchTab.now)
          WatchTodayView(display: display).tag(WatchTab.today)
          WatchQiblaView().tag(WatchTab.qibla)
        }
        .tabViewStyle(.verticalPage)
      } else {
        WatchSetupView()
      }
    }
    .environment(\.locale, store.locale)
    .environment(
      \.layoutDirection,
      store.locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    )
    .tint(theme.accentText)
    // Salah draws the watch in its dark design, whatever the watch's appearance.
    .environment(\.colorScheme, .dark)
    .preferredColorScheme(.dark)
  }
}
