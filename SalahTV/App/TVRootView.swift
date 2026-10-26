import SwiftUI

/// Setup until there's a location, then the three tabs. The adhan and the room display
/// take the whole screen over either.
struct TVRootView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(TVNavigation.self) private var navigation
  @Environment(TVAppRuntime.self) private var runtime

  var body: some View {
    Group {
      if store.needsOnboarding {
        NavigationStack { TVOnboardingView() }
      } else {
        tabs
      }
    }
    .fullScreenCover(item: fullScreen) { moment in
      Group {
        switch moment {
        case .roomDisplay: TVRoomDisplayView()
        case .adhan(let event): TVAdhanView(event: event)
        }
      }
      .tvAppearance(store)
    }
    .tvAppearance(store)
  }

  private var tabs: some View {
    @Bindable var navigation = navigation
    return TabView(selection: $navigation.selectedTab) {
      Tab(value: TVTab.today) {
        TVTodayView()
      } label: {
        Label(copy("Today", "اليوم"), systemImage: "sun.max")
      }
      Tab(value: TVTab.week) {
        TVWeekView()
      } label: {
        Label(copy("Week", "الأسبوع"), systemImage: "calendar")
      }
      Tab(value: TVTab.settings) {
        TVSettingsView()
      } label: {
        Label(copy("Settings", "الإعدادات"), systemImage: "gearshape")
      }
    }
    // The tab content stops short of the bottom edge, so the sky also runs behind the tabs.
    .background {
      TVSkyBackground(
        phase: navigation.selectedTab == .settings ? .neutral : (store.display?.phase ?? .neutral))
    }
  }

  private var fullScreen: Binding<TVFullScreen?> {
    Binding(
      get: { navigation.fullScreen },
      set: {
        guard $0 == nil else { return }
        // The system closing the adhan stops it, so it never plays on without its screen.
        if case .adhan = navigation.fullScreen {
          runtime.stopAdhan()
        } else {
          navigation.dismissFullScreen()
        }
      })
  }

  private var copy: TVCopy { TVCopy(locale: store.locale) }
}

extension View {
  /// The language, direction and appearance chosen in Salah.
  func tvAppearance(_ store: IOSAppStore) -> some View {
    environment(\.locale, store.locale)
      .environment(
        \.layoutDirection,
        store.locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
      )
      .preferredColorScheme(store.preferences.appearance.colorScheme)
  }
}
