import AppKit
import SwiftUI

/// Gives a scene's owning window the Appearance setting's look, such as the menu-bar
/// dropdown's panel: macOS draws a status item's panel in the menu bar's appearance, not
/// the app's (`AppAppearance`), so the panel takes it explicitly. System leaves it to macOS.
struct WindowAppearanceSetter: NSViewRepresentable {
  let setting: SalahAppearance

  func makeNSView(context: Context) -> AppearanceView {
    let view = AppearanceView(frame: .zero)
    view.setting = setting
    return view
  }

  func updateNSView(_ nsView: AppearanceView, context: Context) {
    nsView.setting = setting
  }

  final class AppearanceView: NSView {
    var setting = SalahAppearance.system {
      didSet { apply() }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      apply()
    }

    private func apply() {
      window?.appearance = AppAppearance.appearance(for: setting)
    }
  }
}
