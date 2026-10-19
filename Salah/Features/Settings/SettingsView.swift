import AppKit
import SwiftUI

struct SettingsView: View {
  @Bindable var prefs = Preferences.shared
  @State private var selectedTab: SettingsTab = .general

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      content
    }
    .frame(width: 660, height: 480)
    .background(
      // Forces the Settings NSWindow's title to track `appLanguage`. The system
      // builds the default title from `CFBundleDisplayName` + the OS-localized
      // "Settings" word at window-creation time and never refreshes when our
      // `AppleLanguages` override changes mid-session, so we override it here.
      WindowTitleSetter(
        title: localizedString("settings.window.title", locale: prefs.appLanguage.locale))
    )
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      VStack(spacing: 2) {
        ForEach(SettingsTab.allCases) { tab in
          SidebarRow(tab: tab, isSelected: selectedTab == tab) {
            selectedTab = tab
          }
        }
      }
      .padding(10)

      Spacer()

      VStack(spacing: 2) {
        SettingsSidebarActionRow(
          title: "menu.help.help",
          systemImage: "questionmark.circle",
          action: AppSupportActions.openHelp
        )
        SettingsSidebarActionRow(
          title: "menu.about.help",
          systemImage: "info.circle",
          action: AppSupportActions.openAboutPanel
        )
      }
      .padding(.horizontal, 10)
      .padding(.bottom, 8)

      Text(versionLabel)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    .frame(width: 190)
    .background(.ultraThickMaterial)
  }

  private var versionLabel: String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let locale = prefs.appLanguage.locale
    let format = localizedString("app.versionLabel", locale: locale)
    return String(format: format, locale: locale, version)
  }

  private var content: some View {
    Form {
      switch selectedTab {
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
    .id(selectedTab)
  }
}

private struct SettingsSidebarActionRow: View {
  let title: LocalizedStringKey
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: 20, height: 20)
        Text(title)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
  }
}
