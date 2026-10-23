import AppKit
import SwiftUI

/// Keeps a SwiftUI scene's owning window title in sync with the app's language,
/// such as the menu-bar dropdown's dialog.
struct WindowTitleSetter: NSViewRepresentable {
  let title: String

  func makeNSView(context: Context) -> TitleView {
    let view = TitleView(frame: .zero)
    view.title = title
    return view
  }

  func updateNSView(_ nsView: TitleView, context: Context) {
    nsView.title = title
  }

  final class TitleView: NSView {
    var title = "" {
      didSet { window?.title = title }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.title = title
    }
  }
}
