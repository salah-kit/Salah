import SalahUI
import SwiftUI

/// The Appearance pane: light, dark or the system's appearance, and whether the sky
/// follows the time of day, with a live preview of the medium widget, whose colors the
/// dropdown shares.
struct AppearanceContent: View {
  @Bindable var prefs = Preferences.shared

  var body: some View {
    let preview = previewDisplay
    Section {
      Picker("settings.appearance.mode", selection: $prefs.appearance) {
        Text("settings.appearance.mode.system").tag(SalahAppearance.system)
        Text("settings.appearance.mode.light").tag(SalahAppearance.light)
        Text("settings.appearance.mode.dark").tag(SalahAppearance.dark)
      }
      .settingsPopUp()
      .accessibilityIdentifier("appearance.mode")
      .settingsRow(last: true)
    } header: {
      SettingsHeader("settings.tab.appearance", isFirst: true)
    }

    Section {
      Toggle(isOn: $prefs.followsTimeOfDay) {
        Text("settings.appearance.followsTimeOfDay")
        Text("settings.appearance.followsTimeOfDay.detail")
      }
      .settingsRow(detail: true, last: true)
    } header: {
      SettingsHeader("settings.appearance.colors")
    }

    Section {
      VStack(spacing: 10) {
        WidgetPreviewContainer(display: preview, size: .medium)
          // The widget's timers count against the real clock: at a moment a Debug launch
          // asks for, they hold still at it instead.
          .environment(\.salahTimerPause, AppClock.isShifted ? preview.date : nil)
          .accessibilityElement(children: .contain)
          .accessibilityLabel(Text("settings.appearance.preview"))
          .accessibilityIdentifier("appearance.preview")
        Text("settings.appearance.preview.caption")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .settingsRow(height: 227, last: true)
    } header: {
      SettingsHeader("settings.appearance.preview")
    }
  }

  /// The widget as it is now: the user's prayer times, language and appearance, built from
  /// the settings the widget mirror holds, so the preview matches the installed widget.
  private var previewDisplay: SalahDisplay {
    let settings = prefs.mirroredSettings
    return SalahDisplay(date: AppClock.now, settings: settings, schedule: settings.schedule)
  }
}
