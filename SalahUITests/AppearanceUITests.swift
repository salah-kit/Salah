import AppKit
import XCTest

/// The Appearance setting in the real app: Light and Dark draw Salah's window that way, and
/// going back to System follows macOS again.
final class AppearanceUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testTheWindowFollowsTheSettingAndBackToTheSystem() throws {
    let app = XCUIApplication()
    app.launchArguments =
      SalahUITests.quietLaunch + ["-salah.appearance", "light", "-salah.debug.pane", "appearance"]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    let window = app.salahWindow
    XCTAssertTrue(window.waitForExistence(timeout: 30), app.debugDescription)
    XCTAssertEqual(isLight(window), true, "Light")

    choose("Dark", in: app)
    XCTAssertTrue(wait { self.isLight(window) == false }, "Dark")

    choose("System", in: app)
    let systemIsLight =
      NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
    XCTAssertTrue(wait { self.isLight(window) == systemIsLight }, "System")

    choose("Light", in: app)
    XCTAssertTrue(wait { self.isLight(window) == true }, "Light again")
  }

  /// Picks an Appearance in the pane's pop-up.
  @MainActor
  private func choose(_ title: String, in app: XCUIApplication) {
    let popUp = app.popUpButtons["appearance.mode"]
    XCTAssertTrue(popUp.waitForExistence(timeout: 10), app.debugDescription)
    popUp.click()
    let item = app.menuItems[title]
    XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
    item.click()
  }

  /// Whether the window's background, near its bottom trailing corner, is light.
  @MainActor
  private func isLight(_ window: XCUIElement) -> Bool? {
    let image = window.screenshot().image
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    let x = bitmap.pixelsWide - bitmap.pixelsWide / 20
    let y = bitmap.pixelsHigh - bitmap.pixelsHigh / 20
    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
    return color.redComponent + color.greenComponent + color.blueComponent > 1.5
  }

  @MainActor
  private func wait(_ condition: @escaping @MainActor () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      if condition() { return true }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return condition()
  }
}
