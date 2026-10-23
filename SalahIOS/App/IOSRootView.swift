import SwiftUI

/// One navigation owner per tab; settings paths also accept widget and notification links.
struct IOSRootView: View {
  @Environment(IOSAppStore.self) private var store
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    Group {
      if store.needsOnboarding && horizontalSizeClass != .regular {
        IOSOnboardingView()
      } else {
        appTabs
          .sheet(isPresented: onboardingFormSheet) {
            IOSOnboardingView(presentation: .formSheet)
              .environment(\.locale, store.locale)
              .environment(
                \.layoutDirection,
                store.locale.language.characterDirection == .rightToLeft
                  ? .rightToLeft : .leftToRight
              )
              .preferredColorScheme(preferredColorScheme)
              .tint(IOSTheme.accentText)
              // Fitted sizing adopts this viewport, rather than letting a navigation
              // container grow beyond a raw size proposal. A smaller window can constrain it.
              .frame(idealWidth: 540, maxWidth: 540, idealHeight: 760, maxHeight: 760)
              .presentationSizing(.fitted)
              .presentationCornerRadius(38)
              .presentationDragIndicator(.hidden)
              .interactiveDismissDisabled(store.needsOnboarding)
          }
      }
    }
    .environment(\.locale, store.locale)
    .environment(
      \.layoutDirection,
      store.locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    )
    .preferredColorScheme(preferredColorScheme)
    .tint(IOSTheme.accentText)
    .safeAreaInset(edge: .top) {
      if store.persistenceFailed {
        Label(
          IOSL10n.text(
            "Changes could not be saved. Please try again.",
            arabic: "تعذر حفظ التغييرات. حاول مرة أخرى.", locale: store.locale),
          systemImage: "exclamationmark.triangle"
        )
        .font(.footnote)
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .accessibilityIdentifier("persistence.error")
      }
    }
  }

  /// The system owns dimming, focus and presentation. Completion is the only dismissal.
  private var onboardingFormSheet: Binding<Bool> {
    Binding(
      get: { horizontalSizeClass == .regular && store.needsOnboarding },
      set: { _ in })
  }

  private var appTabs: some View {
    @Bindable var store = store
    return TabView(selection: $store.selectedTab) {
      Tab(value: IOSTab.today) {
        NavigationStack { IOSTodayView() }
      } label: {
        Label(
          IOSL10n.text("Today", arabic: "اليوم", locale: store.locale),
          systemImage: "sun.horizon.fill"
        )
        .accessibilityIdentifier("tab.today")
      }
      Tab(value: IOSTab.times) {
        NavigationStack { IOSTimesView() }
      } label: {
        Label(
          IOSL10n.text("Times", arabic: "المواقيت", locale: store.locale),
          systemImage: "list.bullet"
        )
        .accessibilityIdentifier("tab.times")
      }
      Tab(value: IOSTab.qibla) {
        NavigationStack { IOSQiblaView() }
      } label: {
        Label(
          IOSL10n.text("Qibla", arabic: "القبلة", locale: store.locale),
          systemImage: "location.north.line.fill"
        )
        .accessibilityIdentifier("tab.qibla")
      }
      Tab(value: IOSTab.settings) {
        IOSSettingsNavigationView()
      } label: {
        Label(
          IOSL10n.text("Settings", arabic: "الإعدادات", locale: store.locale),
          systemImage: "gearshape.fill"
        )
        .accessibilityIdentifier("tab.settings")
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .defaultAdaptableTabBarPlacement(.tabBar)
    .accessibilityIdentifier("app.tabs")
  }

  private var preferredColorScheme: ColorScheme? {
    switch store.preferences.appearance {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}
