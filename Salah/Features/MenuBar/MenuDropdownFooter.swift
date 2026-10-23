import SwiftUI

/// The dropdown's action bar: the Silent-mode toggle, then Open Salah, which opens Salah's
/// window, and Quit Salah, the power button. Location lives in the header (matching the
/// widget), so the footer is controls only. Each control shows the pointer cursor and a
/// tooltip. ⌘, opens the window at General, as it does from the window.
struct MenuDropdownFooter: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  let onToggleSilent: () -> Void
  let onOpenSalah: () -> Void
  let onOpenSettings: () -> Void
  let onQuit: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      silentToggle
      Spacer(minLength: 8)
      openSalahButton
      quitButton
    }
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
          .salahInk(silentInk.glyph)
        Text(verbatim: display.labels.silent)
          .salahInk(silentInk)
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
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .menuPointerCursor()
    .help(Text(verbatim: localizedString("settings.notif.silent")))
    .accessibilityLabel(Text(verbatim: localizedString("settings.notif.silent")))
    .accessibilityAddTraits(silentMode ? .isSelected : [])
  }

  private var silentInk: SalahWidgetInk {
    silentMode ? .primary.onAccent(opacity: 0.18) : .secondary
  }

  /// Open Salah, a pill in the theme's accent. Its fill is the 18% accent the contrast
  /// tests check its ink over, as Silent's when it's on.
  private var openSalahButton: some View {
    let title = localizedString("menu.openSalah", locale: display.locale)
    let ink = SalahWidgetInk.primary.onAccent(opacity: 0.18)
    return Button(action: onOpenSalah) {
      HStack(spacing: 5) {
        Image(systemName: "macwindow")
          .salahInk(ink.glyph)
        Text(verbatim: title)
          .salahInk(ink)
      }
      .font(.caption.weight(.medium))
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(Capsule().fill(colors.accent.opacity(0.18)))
      .overlay(Capsule().strokeBorder(colors.accent.opacity(0.45), lineWidth: 0.75))
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
        .font(.system(size: 13))
        .salahInk(.secondary.glyph)
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .menuPointerCursor()
    .help(Text(verbatim: title))
    .accessibilityLabel(Text(verbatim: title))
  }
}
