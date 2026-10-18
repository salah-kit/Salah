import AppKit
import SalahUI
import SwiftUI

/// The Appearance tab: themes the calm look of the widgets (accent, primary,
/// background) via presets or a guard-railed custom theme, with a live preview
/// rendered from the same shared components the widget uses.
struct AppearanceContent: View {
  @Bindable var prefs = Preferences.shared
  @Environment(\.colorScheme) private var settingsScheme
  @State private var previewSize: SalahWidgetSize = .medium
  @State private var showCustomize = false

  var body: some View {
    Section {
      preview
    } header: {
      Text("settings.appearance.preview")
    }

    Section("settings.appearance.theme") {
      presetRow
    }

    Section {
      DisclosureGroup(isExpanded: $showCustomize) {
        customControls
      } label: {
        Text("settings.appearance.customize")
      }
    }
    .onChange(of: showCustomize) { _, expanded in
      seedCustomFromPresetIfNeeded(expanded)
    }
  }

  // MARK: Live preview

  private var preview: some View {
    VStack(spacing: 12) {
      WidgetPreviewContainer(display: previewDisplay, size: previewSize)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("settings.appearance.preview"))
        .accessibilityIdentifier("appearance.preview")
      Picker("settings.appearance.size", selection: $previewSize) {
        Text("settings.appearance.size.small").tag(SalahWidgetSize.small)
        Text("settings.appearance.size.medium").tag(SalahWidgetSize.medium)
        Text("settings.appearance.size.large").tag(SalahWidgetSize.large)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    .padding(.vertical, 6)
  }

  /// The widget as it is now: the user's real prayer times and language, in the
  /// in-progress theme, built from the same settings the widget mirror holds, so the
  /// preview matches the installed widget exactly.
  private var previewDisplay: SalahDisplay {
    let settings = prefs.mirroredSettings
    return SalahDisplay(date: Date(), settings: settings, schedule: settings.schedule)
  }

  // MARK: Presets

  private var presetRow: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(SalahWidgetTheme.allPresets, id: \.id) { theme in
          PresetSwatch(
            theme: theme,
            name: Self.presetName(theme.id),
            isSelected: prefs.widgetThemeID == theme.id
          ) {
            prefs.widgetThemeID = theme.id
          }
        }
      }
      .padding(.vertical, 4)
    }
  }

  // MARK: Customize

  @ViewBuilder
  private var customControls: some View {
    ColorPicker("settings.appearance.accent", selection: accentBinding, supportsOpacity: false)
    if accentTooClose { warningRow("settings.appearance.hueWarning") }

    ColorPicker("settings.appearance.primary", selection: primaryBinding, supportsOpacity: false)
    if primaryTooClose { warningRow("settings.appearance.hueWarning") }
    if isCustom, primaryHasLowContrast {  // WCAG AA large-text floor for the big countdown
      HStack(spacing: 8) {
        Label("settings.appearance.contrastWarning", systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
        Spacer(minLength: 8)
        Button("settings.appearance.fixContrast") { fixPrimaryContrast() }
          .font(.caption)
          .buttonStyle(.borderless)
      }
    }

    Picker("settings.appearance.background", selection: baseBinding) {
      Text("settings.appearance.base.midnight").tag(SalahWidgetBackgroundBase.midnight)
      Text("settings.appearance.base.sand").tag(SalahWidgetBackgroundBase.sand)
      Text("settings.appearance.base.graphite").tag(SalahWidgetBackgroundBase.graphite)
    }
    Picker("settings.appearance.mode", selection: appearanceBinding) {
      Text("settings.appearance.mode.system").tag(SalahWidgetAppearance.system)
      Text("settings.appearance.mode.dark").tag(SalahWidgetAppearance.alwaysDark)
      Text("settings.appearance.mode.light").tag(SalahWidgetAppearance.alwaysLight)
    }
  }

  private func warningRow(_ key: LocalizedStringKey) -> some View {
    Label(key, systemImage: "exclamationmark.triangle")
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  // MARK: Guardrails

  private var isCustom: Bool { prefs.widgetThemeID == "custom" }

  /// The fixed functional hues a themed color must stay clear of.
  private static let functionalHues: [SalahColorSpec] = [
    SalahColorSpec(1.00, 0.27, 0.23),  // red
    SalahColorSpec(0.20, 0.84, 0.29),  // green
    SalahColorSpec(1.00, 0.62, 0.04),  // orange
    SalahColorSpec(0.75, 0.35, 0.95),  // purple
  ]
  /// SalahUI's check, whose defaults are these guardrails: a 3:1 contrast floor for
  /// the big countdown and a 0.28 distance from every functional hue.
  private func problems(_ color: SalahColorSpec) -> [ContrastCheck.Problem] {
    ContrastCheck().problems(
      foreground: color, background: previewSurface, reserved: Self.functionalHues)
  }
  private func tooClose(_ c: SalahColorSpec) -> Bool {
    problems(c).contains {
      if case .tooCloseToReserved = $0 { return true }
      return false
    }
  }
  private var accentTooClose: Bool { isCustom && tooClose(prefs.widgetCustomAccent) }
  private var primaryTooClose: Bool { isCustom && tooClose(prefs.widgetCustomPrimary) }

  /// The appearance the preview is currently showing.
  private var effectivePreviewScheme: ColorScheme {
    switch prefs.widgetAppearance {
    case .alwaysDark: .dark
    case .alwaysLight: .light
    case .system: settingsScheme
    }
  }
  /// The background the custom primary sits on, for the contrast check (the card
  /// tint is a thin wash over this, so it's a fair approximation of the surface).
  /// Text the widget draws in the primary needs more than this check: `SalahWidgetInk`
  /// moves it to 4.5:1 against the glows and tints under it, keeping its hue.
  private var previewSurface: SalahColorSpec {
    effectivePreviewScheme == .dark
      ? prefs.widgetCustomBase.darkTop : prefs.widgetCustomBase.lightTop
  }
  private var primaryHasLowContrast: Bool {
    problems(prefs.widgetCustomPrimary).contains {
      if case .lowContrast = $0 { return true }
      return false
    }
  }
  private func fixPrimaryContrast() {
    setCustom {
      prefs.widgetCustomPrimary = prefs.widgetCustomPrimary.adjustedForContrast(
        against: previewSurface)
    }
  }

  private var accentBinding: Binding<Color> {
    Binding(
      get: { prefs.widgetCustomAccent.color },
      set: { newValue in setCustom { prefs.widgetCustomAccent = SalahColorSpec(color: newValue) } })
  }
  private var primaryBinding: Binding<Color> {
    Binding(
      get: { prefs.widgetCustomPrimary.color },
      set: { newValue in setCustom { prefs.widgetCustomPrimary = SalahColorSpec(color: newValue) } }
    )
  }
  private var baseBinding: Binding<SalahWidgetBackgroundBase> {
    Binding(
      get: { prefs.widgetCustomBase },
      set: { newValue in setCustom { prefs.widgetCustomBase = newValue } })
  }
  private var appearanceBinding: Binding<SalahWidgetAppearance> {
    Binding(
      get: { prefs.widgetAppearance },
      set: { newValue in setCustom { prefs.widgetAppearance = newValue } })
  }

  /// Editing any custom control activates the custom theme. Batched so the color
  /// edit and the "custom" selection coalesce into a single widget refresh (each
  /// preference's didSet emits `.display`).
  private func setCustom(_ mutate: () -> Void) {
    prefs.batchUpdates {
      mutate()
      prefs.widgetThemeID = "custom"
    }
  }

  /// Opening Customize while on a preset seeds the wells from that preset, so the
  /// user starts from the current look.
  private func seedCustomFromPresetIfNeeded(_ expanded: Bool) {
    guard expanded, prefs.widgetThemeID != "custom",
      let preset = SalahWidgetTheme.preset(id: prefs.widgetThemeID)
    else { return }
    prefs.widgetCustomAccent = preset.dark.accent
    prefs.widgetCustomPrimary = preset.dark.primary
  }

  /// Preset display names are untranslated proper nouns.
  static func presetName(_ id: String) -> String {
    switch id {
    case "nocturne": "Nocturne"
    case "dawn": "Dawn"
    case "oasis": "Oasis"
    case "ink": "Ink"
    case "highContrast": "High Contrast"
    default: id.capitalized
    }
  }
}

// MARK: - Preset swatch

private struct PresetSwatch: View {
  let theme: SalahWidgetTheme
  let name: String
  let isSelected: Bool
  let action: () -> Void
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let colors = theme.colors(for: scheme)
    Button(action: action) {
      VStack(spacing: 6) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
              LinearGradient(
                colors: [colors.backgroundTop, colors.backgroundBottom],
                startPoint: .top, endPoint: .bottom))
          HStack(spacing: 5) {
            Circle().fill(colors.accent).frame(width: 11, height: 11)
            Circle().fill(colors.primary).frame(width: 11, height: 11)
          }
        }
        .frame(width: 60, height: 42)
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
              isSelected ? Color.accentColor : Color.secondary.opacity(0.35),
              lineWidth: isSelected ? 2.5 : 1))
        Text(verbatim: name)
          .font(.caption2)
          .foregroundStyle(isSelected ? Color.primary : Color.secondary)
          .lineLimit(1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(verbatim: name))
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }
}

// MARK: - Color bridge (app-side; uses AppKit)

extension SalahColorSpec {
  fileprivate init(color: Color) {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white.usingColorSpace(.sRGB)!
    self.init(
      Double(ns.redComponent), Double(ns.greenComponent),
      Double(ns.blueComponent), Double(ns.alphaComponent))
  }
}

#Preview("Appearance · dark") {
  Form { AppearanceContent() }
    .formStyle(.grouped)
    .frame(width: 660, height: 480)
    .preferredColorScheme(.dark)
}

#Preview("Appearance · light") {
  Form { AppearanceContent() }
    .formStyle(.grouped)
    .frame(width: 660, height: 480)
    .preferredColorScheme(.light)
}
