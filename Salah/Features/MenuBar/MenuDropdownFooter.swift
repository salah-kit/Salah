import SalahUI
import SwiftUI

/// The dropdown's footer: the Silent toggle, then Open Salah, which opens Salah's window,
/// and Quit Salah, the power button. Each control shows the pointer cursor and a tooltip.
/// ⌘, opens the window at General, as it does from the window.
struct MenuDropdownFooter: View {
  let display: SalahDisplay
  let colors: SalahColors
  let onToggleSilent: () -> Void
  let onOpenSalah: () -> Void
  let onOpenSettings: () -> Void
  let onQuit: () -> Void

  private var palette: SalahPalette { colors.palette }

  var body: some View {
    HStack(spacing: 6) {
      silentToggle
      Spacer(minLength: 8)
      openSalahButton
      quitButton
    }
    .padding(.top, 2)
    .background {
      Button(action: onOpenSettings) { EmptyView() }
        .keyboardShortcut(",", modifiers: .command)
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
  }

  private var silentMode: Bool { display.settings.silentMode }

  private var silentToggle: some View {
    Button(action: onToggleSilent) {
      HStack(spacing: 5) {
        Image(systemName: silentMode ? "bell.slash.fill" : "bell")
          .font(.system(size: 11))
          .frame(width: 12, height: 12)
        Text(verbatim: display.labels.silent)
          .font(.caption)
      }
      .foregroundStyle((silentMode ? palette.accentText : palette.labelSecondary).color)
      .padding(.leading, 9)
      .padding(.trailing, 10)
      .padding(.vertical, 4)
      // Off, the 1 pt border lies outside the padding, as Figma lays it out.
      .padding(silentMode ? 0 : 1)
      .background {
        if silentMode {
          Capsule().fill(palette.accentSubtle.color)
        } else {
          Capsule().strokeBorder(palette.separator.color, lineWidth: 1)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .menuPointerCursor()
    .help(Text(verbatim: localizedString("settings.notif.silent")))
    .accessibilityLabel(Text(verbatim: localizedString("settings.notif.silent")))
    .accessibilityAddTraits(silentMode ? .isSelected : [])
  }

  private var openSalahButton: some View {
    let title = localizedString("menu.openSalah", locale: display.locale)
    return Button(action: onOpenSalah) {
      HStack(spacing: 5) {
        Image(systemName: "macwindow")
          .font(.system(size: 10))
          .frame(width: 12, height: 12)
        Text(verbatim: title)
          .font(.caption)
      }
      .foregroundStyle(palette.labelOnAccent.color)
      .padding(.leading, 9)
      .padding(.trailing, 10)
      .padding(.vertical, 4)
      .background(Capsule().fill(palette.accentFill.color))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .menuPointerCursor()
    .help(Text(verbatim: title))
    .accessibilityLabel(Text(verbatim: title))
  }

  /// Quit Salah: stops it completely, the menu bar item included.
  private var quitButton: some View {
    let title = localizedString("menu.quit", locale: display.locale)
    return Button(action: onQuit) {
      Image(systemName: "power")
        .font(.system(size: 11))
        .frame(width: 13, height: 13)
        .foregroundStyle(palette.labelSecondary.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .menuPointerCursor()
    .help(Text(verbatim: title))
    .accessibilityLabel(Text(verbatim: title))
  }
}
