import ServiceManagement
import SwiftUI

struct GeneralContent: View {
  @Bindable var prefs = Preferences.shared

  var body: some View {
    Section {
      LanguagePicker()
        .settingsRow()
      MenuBarPreview(language: prefs.appLanguage)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .settingsRow(last: true)
    } header: {
      SettingsHeader("settings.general.language", isFirst: true)
    } footer: {
      SettingsFooter("settings.general.language.footer")
    }

    // The menu-bar item: its icon, and the next prayer's name and time.
    Section {
      Toggle("settings.general.showIcon", isOn: $prefs.displayIcon)
        .settingsRow()
      Toggle("settings.general.showNextPrayer", isOn: $prefs.displayNextPrayer)
        .settingsRow(last: !prefs.displayNextPrayer)
      if prefs.displayNextPrayer {
        Picker("settings.general.nameStyle", selection: $prefs.nextPrayerDisplayName) {
          Text("settings.general.nameStyle.full").tag(NextPrayerDisplayName.full)
          Text("settings.general.nameStyle.abbr").tag(NextPrayerDisplayName.abbreviation)
          Text("settings.general.nameStyle.hidden")
            .tag(NextPrayerDisplayName.none)
            .disabled(prefs.nextPrayerDisplayType == .none)
        }
        .settingsPopUp()
        .settingsRow()
        Picker("settings.general.timeStyle", selection: $prefs.nextPrayerDisplayType) {
          Text("settings.general.timeStyle.countdown").tag(NextPrayerDisplayType.timeUntil)
          Text("settings.general.timeStyle.prayerTime").tag(NextPrayerDisplayType.timeOfPrayer)
          Text("settings.general.nameStyle.hidden")
            .tag(NextPrayerDisplayType.none)
            .disabled(prefs.nextPrayerDisplayName == .none)
        }
        .settingsPopUp()
        .settingsRow(last: true)
      }
    } header: {
      SettingsHeader("settings.general.menubar")
    }

    Section {
      LaunchAtLoginControl()
    } header: {
      SettingsHeader("settings.general.startup")
    }
  }
}

struct LaunchAtLoginControl: View {
  @Bindable private var prefs = Preferences.shared
  @State private var isEnabled = SMAppService.mainApp.status == .enabled
  @State private var requiresApproval = SMAppService.mainApp.status == .requiresApproval
  @State private var errorMessage: String?

  var body: some View {
    Toggle(
      "settings.general.launchAtLogin",
      isOn: Binding(
        get: { isEnabled },
        set: { newValue in
          setEnabled(newValue)
        }
      )
    )
    .settingsRow(last: !requiresApproval && errorMessage == nil)
    // Stale `errorMessage` is frozen in the language it was built in - drop
    // it when the user switches languages so the next attempt rebuilds fresh.
    .onChange(of: prefs.appLanguage) { errorMessage = nil }

    if requiresApproval {
      Button("settings.general.openLoginItems") {
        SMAppService.openSystemSettingsLoginItems()
        refresh()
      }
      .settingsPushButton()
      .settingsRow(last: errorMessage == nil)
    }

    if let errorMessage {
      Label(errorMessage, systemImage: "exclamationmark.triangle")
        .font(.caption)
        .foregroundStyle(.red)
    }
  }

  private func setEnabled(_ newValue: Bool) {
    do {
      if newValue {
        if SMAppService.mainApp.status == .notRegistered {
          try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status == .requiresApproval {
          SMAppService.openSystemSettingsLoginItems()
        }
      } else if SMAppService.mainApp.status != .notRegistered {
        try SMAppService.mainApp.unregister()
      }
      errorMessage = nil
    } catch {
      errorMessage = localizedString("settings.general.loginItemError", locale: .app)
    }

    refresh()
  }

  private func refresh() {
    let status = SMAppService.mainApp.status
    isEnabled = status == .enabled
    requiresApproval = status == .requiresApproval
  }
}
