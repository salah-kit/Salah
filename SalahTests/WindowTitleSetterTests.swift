import AppKit
import SwiftUI
import Testing

/// The title belongs to the window that currently owns the hosted content, even when
/// SwiftUI creates or updates that content before AppKit attaches it to a window.
@MainActor
@Suite("Window title ownership", .serialized)
struct WindowTitleSetterTests {
  @Test(arguments: ["Salah", "صلاة"])
  func titleIsAppliedAfterDetachedWorkHasDrained(_ title: String) async throws {
    let hostingView = NSHostingView(rootView: WindowTitleSetter(title: title))
    try materialize(hostingView)
    await drainMainQueue()
    #expect(hostingView.window == nil)

    let window = makeWindow()
    defer { close(window) }
    window.contentView = hostingView

    #expect(hostingView.window === window)
    #expect(window.title == title, "Attaching existing content must name its owning window")
    await drainMainQueue()
    #expect(window.title == title)
  }

  @Test
  func titleUpdatesWhileAttached() async throws {
    let hostingView = NSHostingView(rootView: WindowTitleSetter(title: "Salah"))
    let window = makeWindow()
    defer { close(window) }
    window.contentView = hostingView
    try materialize(hostingView)
    await drainMainQueue()
    #expect(window.title == "Salah")

    hostingView.rootView = WindowTitleSetter(title: "صلاة")
    try materialize(hostingView)
    await drainMainQueue()
    #expect(window.title == "صلاة", "Changing the localized title must update the same window")
  }

  @Test
  func latestDetachedTitleIsUsedAfterReattachment() async throws {
    let hostingView = NSHostingView(rootView: WindowTitleSetter(title: "Salah"))
    let firstWindow = makeWindow()
    let secondWindow = makeWindow()
    defer {
      close(secondWindow)
      close(firstWindow)
    }
    firstWindow.contentView = hostingView
    try materialize(hostingView)
    await drainMainQueue()
    #expect(firstWindow.title == "Salah")

    firstWindow.contentView = nil
    #expect(hostingView.window == nil)
    hostingView.rootView = WindowTitleSetter(title: "صلاة")
    try materialize(hostingView)
    await drainMainQueue()
    #expect(hostingView.window == nil)
    #expect(firstWindow.title == "Salah", "Detached updates must not rename the previous owner")

    secondWindow.contentView = hostingView
    #expect(hostingView.window === secondWindow)
    #expect(secondWindow.title == "صلاة", "Reattachment must use the latest detached title")
    #expect(firstWindow.title == "Salah")
    await drainMainQueue()
    #expect(secondWindow.title == "صلاة")
    #expect(firstWindow.title == "Salah")
  }

  /// Force public SwiftUI sizing and layout while keeping attachment under the test's
  /// control. A missing native descendant makes the setup fail rather than claiming to
  /// have exercised a representable that SwiftUI never created.
  private func materialize(_ hostingView: NSHostingView<WindowTitleSetter>) throws {
    hostingView.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
    _ = hostingView.fittingSize
    hostingView.needsLayout = true
    hostingView.layoutSubtreeIfNeeded()
    try #require(!hostingView.subviews.isEmpty, "SwiftUI must materialize the native root view")
  }

  /// A queue barrier drains the old bridge's one deferred write before attachment; it
  /// does not depend on an arbitrary delay or a particular run-loop speed.
  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }

  private func makeWindow() -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }

  private func close(_ window: NSWindow) {
    window.contentView = nil
    window.close()
  }
}
