import AppKit
import SwiftUI

enum AppSupportActions {
  static func openHelp() {
    if let url = URL(string: "https://github.com/salah-kit/Salah#readme") {
      NSWorkspace.shared.open(url)
    }
  }

  static func openAboutPanel() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: aboutPanelOptions)
  }

  private static var aboutPanelOptions: [NSApplication.AboutPanelOptionKey: Any] {
    [
      .credits: aboutCredits
    ]
  }

  private static var aboutCredits: NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.baseWritingDirection =
      Locale.app.preferredLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight

    let regular: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12),
      .paragraphStyle: paragraphStyle,
    ]
    let bold: [NSAttributedString.Key: Any] = [
      .font: NSFont.boldSystemFont(ofSize: 12),
      .paragraphStyle: paragraphStyle,
    ]
    let link: [NSAttributedString.Key: Any] = regular.merging([
      .foregroundColor: NSColor.linkColor
    ]) { _, new in new }

    func linked(_ string: String, url: String) -> NSAttributedString {
      var attributes = link
      attributes[.link] = URL(string: url)
      return NSAttributedString(string: string, attributes: attributes)
    }

    let credits = NSMutableAttributedString()
    func append(_ string: String, attributes: [NSAttributedString.Key: Any]) {
      credits.append(NSAttributedString(string: string, attributes: attributes))
    }

    append(
      "\n\(localizedString("about.credits.development", locale: .app)):\n",
      attributes: bold
    )
    credits.append(
      linked("The Salah Kit Authors\n\n\n", url: "https://github.com/salah-kit/Salah"))
    append(
      "\(localizedString("about.credits.calculationSource", locale: .app))\n",
      attributes: regular
    )
    credits.append(
      linked("github.com/batoulapps/Adhan", url: "https://github.com/batoulapps/Adhan"))
    return credits
  }
}
