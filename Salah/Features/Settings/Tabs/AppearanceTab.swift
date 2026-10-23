import SalahUI
import SwiftUI

/// The Appearance pane: light, dark or the system's appearance, and whether the sky
/// follows the time of day, with a live preview of the medium widget, whose colors the
/// dropdown shares.
struct AppearanceContent: View {
  @Bindable var prefs = Preferences.shared

  var body: some View {
    Section("settings.tab.appearance") {
      Picker("settings.appearance.mode", selection: $prefs.appearance) {
        Text("settings.appearance.mode.system").tag(SalahAppearance.system)
        Text("settings.appearance.mode.light").tag(SalahAppearance.light)
        Text("settings.appearance.mode.dark").tag(SalahAppearance.dark)
      }
      .pickerStyle(.menu)
    }

    Section("settings.appearance.colors") {
      Toggle(isOn: $prefs.followsTimeOfDay) {
        Text("settings.appearance.followsTimeOfDay")
        Text("settings.appearance.followsTimeOfDay.detail")
      }
      .toggleStyle(.switch)
    }

    Section("settings.appearance.preview") {
      VStack(spacing: 10) {
        WidgetPreviewContainer(display: previewDisplay, size: .medium)
          .accessibilityElement(children: .contain)
          .accessibilityLabel(Text("settings.appearance.preview"))
          .accessibilityIdentifier("appearance.preview")
        Text("settings.appearance.preview.caption")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 20)
    }
  }

  /// The widget as it is now: the user's prayer times, language and appearance, built from
  /// the settings the widget mirror holds, so the preview matches the installed widget.
  private var previewDisplay: SalahDisplay {
    let settings = prefs.mirroredSettings
    return SalahDisplay(date: Date(), settings: settings, schedule: settings.schedule)
  }
}
