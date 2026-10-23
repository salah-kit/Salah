import AppKit
import OSLog
import SwiftUI

/// Shows, once, the note that hangs from Salah's menu bar item the first time its last window
/// closes: Salah is still running, and the power button in its dropdown turns it off. Got It,
/// a click elsewhere or the window reopening closes it, and Escape while Salah is active:
/// another app has the keyboard otherwise.
@MainActor
final class CloseNotePresenter: NSObject, NSPopoverDelegate {
  static let shared = CloseNotePresenter()

  private var popover: NSPopover?
  /// An invisible window over the status item that the note hangs from.
  private var anchor: NSWindow?
  private var monitors: [Any] = []

  /// Shows the note from the status item, and returns whether it could find the item.
  ///
  /// The note closes itself rather than as a transient popover: when the last window closes,
  /// Salah leaves the Dock and macOS makes another app active, which would close a transient
  /// popover as it opens.
  func show() -> Bool {
    // A hidden app's windows don't show, so the note waits for the next close.
    guard popover == nil, !NSApp.isHidden, let button = Self.statusItemButton(),
      let itemWindow = button.window
    else {
      let windows = NSApp.windows.map(\.className).joined(separator: " ")
      AppLog.lifecycle.notice(
        "note not shown showing=\(self.popover != nil, privacy: .public) hidden=\(NSApp.isHidden, privacy: .public) windows=\(windows, privacy: .public)"
      )
      return false
    }
    let locale = Locale.app
    let popover = NSPopover()
    popover.behavior = .applicationDefined
    popover.animates = true
    popover.delegate = self
    popover.contentViewController = NSHostingController(
      rootView: CloseNoteView { [weak self] in self?.close() }
        .environment(\.locale, locale)
        .environment(\.layoutDirection, locale.preferredLayoutDirection))
    self.popover = popover
    // The note hangs from a window of its own over the item, not from the item's button:
    // a popover highlights the button it's shown from, and `MenuBarExtra` then opens its
    // dropdown.
    let anchor = NSWindow(
      contentRect: itemWindow.convertToScreen(button.convert(button.bounds, to: nil)),
      styleMask: .borderless, backing: .buffered, defer: false)
    anchor.isReleasedWhenClosed = false
    anchor.isOpaque = false
    anchor.backgroundColor = .clear
    anchor.hasShadow = false
    anchor.ignoresMouseEvents = true
    anchor.level = .statusBar
    anchor.orderFrontRegardless()
    self.anchor = anchor
    guard let view = anchor.contentView else { return false }
    popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    monitorDismissal()
    return true
  }

  /// Closes the note on a click anywhere outside it, in Salah or another app, and on Escape
  /// while Salah is active.
  private func monitorDismissal() {
    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    if let global = NSEvent.addGlobalMonitorForEvents(
      matching: clicks,
      handler: { [weak self] _ in MainActor.assumeIsolated { self?.close() } })
    {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(
      matching: clicks.union(.keyDown),
      handler: { [weak self] event in
        let isEscape = event.type == .keyDown && event.keyCode == 53
        let isClick = event.type != .keyDown
        let window = event.windowNumber
        MainActor.assumeIsolated {
          let note = self?.popover?.contentViewController?.view.window?.windowNumber
          if isEscape || (isClick && window != note) { self?.close() }
        }
        return isEscape ? nil : event
      })
    {
      monitors.append(local)
    }
  }

  /// Closes the note if it's showing: Salah's window is opening.
  func dismiss() {
    close()
  }

  private func close() {
    popover?.performClose(nil)
  }

  func popoverDidClose(_ notification: Notification) {
    monitors.forEach(NSEvent.removeMonitor)
    monitors = []
    popover = nil
    anchor?.close()
    anchor = nil
  }

  /// The button of Salah's status item, the `MenuBarExtra`'s, which lives in a window of
  /// its own.
  private static func statusItemButton() -> NSStatusBarButton? {
    for window in NSApp.windows where window.className.contains("StatusBarWindow") {
      if let button = window.contentView.flatMap(findButton) { return button }
    }
    return nil
  }

  private static func findButton(in view: NSView) -> NSStatusBarButton? {
    if let button = view as? NSStatusBarButton { return button }
    for subview in view.subviews {
      if let button = findButton(in: subview) { return button }
    }
    return nil
  }
}

/// The note's content: Salah's icon and that it's still running, how to turn it off, and
/// Got It.
struct CloseNoteView: View {
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 32, height: 32)
          .accessibilityHidden(true)
        Text("note.stillRunning.title")
          .font(.headline)
          .accessibilityAddTraits(.isHeader)
      }
      Text("note.stillRunning.body")
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button(action: onDismiss) {
          Text("note.gotIt")
        }
        .buttonStyle(AccentPillButtonStyle())
        .keyboardShortcut(.defaultAction)
      }
      .padding(.top, 4)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .frame(width: 300)
  }
}

/// A capsule filled with the accent, as the note's Got It: the push button's shape in
/// Salah's gold.
private struct AccentPillButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.medium))
      .foregroundStyle(WindowPalette.onAccent)
      .padding(.horizontal, 16)
      .frame(height: 24)
      .background(Capsule().fill(WindowPalette.accentFill))
      .opacity(configuration.isPressed ? 0.75 : 1)
      .contentShape(Capsule())
  }
}
