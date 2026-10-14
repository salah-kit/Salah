import SwiftUI

/// The dropdown's action bar: the Silent-mode toggle, plus Settings (⌘,) and Quit.
/// Location lives in the header (matching the widget), so the footer is controls
/// only. Each control shows the pointer cursor and a tooltip.
struct MenuDropdownFooter: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  let onToggleSilent: () -> Void
  let onOpenSettings: () -> Void
  let onQuit: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      silentToggle
      Spacer(minLength: 8)
      iconButton(
        system: "gearshape", help: localizedString("menu.settings"), action: onOpenSettings
      )
      .keyboardShortcut(",", modifiers: .command)
      iconButton(system: "power", help: localizedString("menu.quit"), action: onQuit)
    }
  }

  private var silentMode: Bool { display.settings.silentMode }

  private var silentToggle: some View {
    Button(action: onToggleSilent) {
      HStack(spacing: 5) {
        Image(systemName: silentMode ? "bell.slash.fill" : "bell")
        Text(verbatim: display.labels.silent)
      }
      .font(.caption.weight(.medium))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background {
        if silentMode {
          Capsule().fill(colors.accent.opacity(0.18))
        }
      }
      .overlay {
        if silentMode {
          Capsule().strokeBorder(colors.accent.opacity(0.45), lineWidth: 0.75)
        }
      }
      .foregroundStyle(silentMode ? colors.accent : Color.secondary)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .menuPointerCursor()
    .help(Text(verbatim: localizedString("settings.notif.silent")))
    .accessibilityLabel(Text(verbatim: localizedString("settings.notif.silent")))
    .accessibilityAddTraits(silentMode ? .isSelected : [])
  }

  private func iconButton(system: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: system)
        .font(.system(size: 13))
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .menuPointerCursor()
    .help(Text(verbatim: help))
    .accessibilityLabel(Text(verbatim: help))
  }
}
