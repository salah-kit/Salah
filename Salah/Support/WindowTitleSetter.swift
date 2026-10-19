import AppKit
import SwiftUI

/// Keeps a SwiftUI scene's owning window title in sync with the app's language,
/// including the Settings window and the menu-bar dropdown's dialog.
struct WindowTitleSetter: NSViewRepresentable {
  let title: String

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    apply(to: view)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    apply(to: nsView)
  }

  private func apply(to view: NSView) {
    // The view is attached to its owning window on the next run-loop pass.
    let title = title
    DispatchQueue.main.async {
      view.window?.title = title
    }
  }
}
