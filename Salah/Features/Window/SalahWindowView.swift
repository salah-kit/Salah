import SwiftUI

/// Salah's one window: a sidebar with Today, then the six settings panes under a Settings
/// header, and the selected pane beside it. The window comes and goes; the prayer schedule,
/// the alerts and the audio keep running in `PrayerManager` whatever it does.
struct SalahWindowView: View {
  var prayerManager: PrayerManager
  @Bindable var navigation: WindowNavigation
  @Bindable var prefs = Preferences.shared

  private var locale: Locale { prefs.appLanguage.locale }

  var body: some View {
    NavigationSplitView {
      List(selection: selection) {
        row(.today)
        Section("menu.settings") {
          ForEach(WindowPane.settings) { pane in row(pane) }
        }
      }
      .navigationSplitViewColumnWidth(220)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      detail
        .navigationTitle(localizedString(dynamicKey: navigation.pane.titleKey, locale: locale))
    }
    .tint(WindowPalette.accent)
    .frame(minWidth: 780, minHeight: 440)
    .background(WindowAttacher { AppWindowCoordinator.shared.attach($0) })
  }

  /// The sidebar always has a pane selected: clicking the selected one keeps it.
  private var selection: Binding<WindowPane?> {
    Binding(
      get: { navigation.pane },
      set: { if let pane = $0 { navigation.pane = pane } })
  }

  /// A sidebar row: the pane's symbol in the accent, and its name.
  private func row(_ pane: WindowPane) -> some View {
    Label {
      Text(LocalizedStringKey(pane.titleKey))
    } icon: {
      Image(systemName: pane.icon)
        .foregroundStyle(WindowPalette.accent)
    }
    .tag(pane)
  }

  @ViewBuilder
  private var detail: some View {
    switch navigation.pane {
    case .today:
      TodayView(prayerManager: prayerManager)
    case let pane:
      Form {
        switch pane {
        case .today: EmptyView()
        case .general: GeneralContent()
        case .location: LocationContent()
        case .calculation: CalculationContent()
        case .adjustments: AdjustmentsContent()
        case .notifications: NotificationsContent()
        case .appearance: AppearanceContent()
        }
      }
      .formStyle(.grouped)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .id(pane)
    }
  }
}
