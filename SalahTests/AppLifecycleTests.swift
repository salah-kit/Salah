import AppKit
import Testing

/// How Salah shows itself, opens, closes and quits: in the menu bar only, or with a Dock
/// icon, ⌘-Tab and its menus while its window is open.
@Suite("App lifecycle decisions")
struct AppLifecycleTests {
  // The objects stay alive for the test, so their identifiers stay distinct.
  private let windows = (NSObject(), NSObject())
  private var first: ObjectIdentifier { ObjectIdentifier(windows.0) }
  private var second: ObjectIdentifier { ObjectIdentifier(windows.1) }

  @Test func startsInTheMenuBarOnly() {
    let lifecycle = AppLifecycle(hasShownCloseNote: false)
    #expect(lifecycle.presence == .menuBar)
    #expect(lifecycle.openWindows.isEmpty)
  }

  @Test func anOpenWindowGivesTheDockIconUntilTheLastOneCloses() {
    var lifecycle = AppLifecycle(hasShownCloseNote: true)
    lifecycle.windowOpened(first)
    #expect(lifecycle.presence == .regular)
    lifecycle.windowOpened(second)
    _ = lifecycle.windowClosed(first)
    #expect(lifecycle.presence == .regular, "One window is still open")
    _ = lifecycle.windowClosed(second)
    #expect(lifecycle.presence == .menuBar)
  }

  @Test func theNoteShowsTheFirstTimeTheLastWindowClosesOnly() {
    var lifecycle = AppLifecycle(hasShownCloseNote: false)
    lifecycle.windowOpened(first)
    lifecycle.windowOpened(second)
    let notLast = lifecycle.windowClosed(first)
    #expect(!notLast, "Not the last window")
    let last = lifecycle.windowClosed(second)
    #expect(last)
    #expect(lifecycle.hasShownCloseNote)

    lifecycle.windowOpened(first)
    let again = lifecycle.windowClosed(first)
    #expect(!again, "Shown once")
  }

  @Test func aShownNoteStaysShownAcrossLaunches() {
    var lifecycle = AppLifecycle(hasShownCloseNote: true)
    lifecycle.windowOpened(first)
    let showsNote = lifecycle.windowClosed(first)
    #expect(!showsNote)
  }

  @Test func closingAWindowItDoesNotKnowChangesNothing() {
    var lifecycle = AppLifecycle(hasShownCloseNote: false)
    let showsNote = lifecycle.windowClosed(first)
    #expect(!showsNote)
    #expect(!lifecycle.hasShownCloseNote)
    #expect(lifecycle.presence == .menuBar)
  }

  @Test func commandQWithTheWindowOpenClosesItToTheMenuBar() {
    var lifecycle = AppLifecycle(hasShownCloseNote: false)
    lifecycle.windowOpened(first)
    let reply = lifecycle.quit(from: .other)
    #expect(reply == .closeWindows)
    #expect(!lifecycle.isQuitting)
    let showsNote = lifecycle.windowClosed(first)
    #expect(showsNote, "Closing by ⌘Q shows the note like any close")
    #expect(lifecycle.presence == .menuBar)
  }

  @Test func aQuitWithNoWindowOpenQuits() {
    var lifecycle = AppLifecycle(hasShownCloseNote: false)
    let reply = lifecycle.quit(from: .other)
    #expect(reply == .quit)
    #expect(lifecycle.isQuitting)
  }

  @Test(arguments: [AppLifecycle.QuitSource.quitSalah, .sessionEnding])
  func quitSalahAndTheEndOfTheSessionQuitWithTheWindowOpen(_ source: AppLifecycle.QuitSource) {
    var lifecycle = AppLifecycle(hasShownCloseNote: false)
    lifecycle.windowOpened(first)
    let reply = lifecycle.quit(from: source)
    #expect(reply == .quit)
    let showsNote = lifecycle.windowClosed(first)
    #expect(!showsNote, "Windows closed on the way out show no note")
    #expect(!lifecycle.hasShownCloseNote)
  }

  @Test func onlyALoginLaunchStaysQuiet() {
    #expect(!AppLifecycle.opensWindowAtLaunch(asLoginItem: true))
    #expect(AppLifecycle.opensWindowAtLaunch(asLoginItem: false))
  }
}

/// The coordinator applies those decisions to the app and its window: real windows, and a
/// recorder in the app's place.
@MainActor
@Suite("Window coordinator", .serialized)
struct AppWindowCoordinatorTests {
  private let scratch = ScratchDefaults()
  private let presence = PresenceRecorder()

  private func makeCoordinator(noteShows: Bool = true, notes: NoteCounter = NoteCounter())
    -> AppWindowCoordinator
  {
    AppWindowCoordinator(
      presence: presence, defaults: scratch.defaults,
      showCloseNote: {
        notes.count += 1
        return noteShows
      },
      dismissCloseNote: { notes.dismissals += 1 })
  }

  @Test func theWindowGivesTheDockIconAndClosingItTakesItAway() {
    let notes = NoteCounter()
    let coordinator = makeCoordinator(notes: notes)
    let window = makeWindow()
    coordinator.attach(window)
    #expect(presence.presences == [.regular])
    #expect(window.accessibilityIdentifier() == AppWindowCoordinator.windowAccessibilityIdentifier)
    #expect(!window.isRestorable, "A login launch must never bring the window back")

    window.close()
    #expect(presence.presences == [.regular, .menuBar])
    #expect(notes.count == 1)
    #expect(scratch.defaults.bool(forKey: AppWindowCoordinator.closeNoteShownKey))
  }

  @Test func hidingOrMinimizingKeepsTheDockIcon() {
    let coordinator = makeCoordinator()
    let window = makeWindow()
    defer { window.close() }
    coordinator.attach(window)
    window.orderOut(nil)
    window.miniaturize(nil)
    #expect(presence.presences == [.regular], "Visibility never decides the presence")
    #expect(coordinator.lifecycle.presence == .regular)
  }

  @Test func attachingTheSameWindowTwiceCountsItOnce() {
    let coordinator = makeCoordinator()
    let window = makeWindow()
    coordinator.attach(window)
    coordinator.attach(window)
    window.close()
    #expect(presence.presences == [.regular, .menuBar])
  }

  @Test func aReopenedWindowGivesTheDockIconAgain() {
    let coordinator = makeCoordinator()
    let window = makeWindow()
    defer { window.close() }
    coordinator.attach(window)
    window.close()
    // SwiftUI shows the same window again when Salah's window reopens.
    window.orderFront(nil)
    coordinator.attach(window)
    #expect(presence.presences == [.regular, .menuBar, .regular])
    #expect(coordinator.lifecycle.presence == .regular)
  }

  @Test func theNoteShowsOnceAcrossCoordinators() {
    let notes = NoteCounter()
    let firstRun = makeCoordinator(notes: notes)
    let window = makeWindow()
    firstRun.attach(window)
    window.close()

    let secondRun = makeCoordinator(notes: notes)
    let another = makeWindow()
    secondRun.attach(another)
    another.close()
    #expect(notes.count == 1)
  }

  @Test func aNoteThatCouldNotShowIsTriedAgainOnTheNextClose() {
    let notes = NoteCounter()
    let coordinator = makeCoordinator(noteShows: false, notes: notes)
    let window = makeWindow()
    coordinator.attach(window)
    window.close()
    #expect(notes.count == 1)
    #expect(!scratch.defaults.bool(forKey: AppWindowCoordinator.closeNoteShownKey))

    window.orderFront(nil)
    coordinator.attach(window)
    window.close()
    #expect(notes.count == 2)
  }

  @Test func commandQClosesTheWindowAndKeepsSalahRunning() {
    let notes = NoteCounter()
    let coordinator = makeCoordinator(notes: notes)
    let window = makeWindow()
    coordinator.attach(window)

    #expect(coordinator.shouldTerminate(appleEvent: nil) == .terminateCancel)
    #expect(!window.isVisible)
    #expect(presence.presences == [.regular, .menuBar])
    #expect(notes.count == 1)
    #expect(presence.terminations == 0)
  }

  @Test func quitSalahQuitsWithTheWindowOpenAndShowsNoNote() {
    let notes = NoteCounter()
    let coordinator = makeCoordinator(notes: notes)
    let window = makeWindow()
    coordinator.attach(window)

    coordinator.quitSalah()
    #expect(presence.terminations == 1)
    #expect(coordinator.shouldTerminate(appleEvent: nil) == .terminateNow)
    window.close()
    #expect(notes.count == 0)
  }

  @Test(arguments: [
    kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart, kAEShowShutdownDialog,
    kAEShutDown,
  ])
  func logoutRestartAndShutdownQuitWithTheWindowOpen(_ reason: UInt32) {
    let coordinator = makeCoordinator()
    let window = makeWindow()
    defer { window.close() }
    coordinator.attach(window)
    #expect(coordinator.shouldTerminate(appleEvent: quitEvent(reason: reason)) == .terminateNow)
  }

  @Test func aQuitEventWithoutASessionReasonClosesTheWindow() {
    let coordinator = makeCoordinator()
    let window = makeWindow()
    coordinator.attach(window)
    #expect(coordinator.shouldTerminate(appleEvent: quitEvent(reason: nil)) == .terminateCancel)
    #expect(!window.isVisible)
  }

  @Test func aQuitWithNoWindowQuits() {
    let coordinator = makeCoordinator()
    #expect(coordinator.shouldTerminate(appleEvent: nil) == .terminateNow)
  }

  @Test func openSalahShowsTodayFirstThenTheLastPane() {
    let notes = NoteCounter()
    let coordinator = makeCoordinator(notes: notes)
    let opener = OpenCounter()
    coordinator.register { opener.count += 1 }

    coordinator.open()
    #expect(coordinator.navigation.pane == .today)
    #expect(opener.count == 1)
    #expect(presence.bringForwards == 1)
    #expect(notes.dismissals == 1, "Opening the window closes the note")

    coordinator.navigation.pane = .notifications
    coordinator.open()
    #expect(coordinator.navigation.pane == .notifications, "The last pane")

    coordinator.open(.general)
    #expect(coordinator.navigation.pane == .general, "⌘, opens General")
  }

  @Test func openingAnOpenWindowBringsItForwardWithoutASecondOne() {
    let coordinator = makeCoordinator()
    let opener = OpenCounter()
    coordinator.register { opener.count += 1 }
    let window = makeWindow()
    defer { window.close() }
    coordinator.attach(window)

    coordinator.open()
    #expect(opener.count == 0, "Never a second window")
    #expect(presence.bringForwards == 1)
    #expect(window.isVisible)
  }

  @Test func anOpenRequestedBeforeTheScenesAreReadyWaitsForThem() {
    let coordinator = makeCoordinator()
    let opener = OpenCounter()
    coordinator.open()
    #expect(opener.count == 0)
    coordinator.register { opener.count += 1 }
    #expect(opener.count == 1)
  }

  @Test func aLoginLaunchStaysQuiet() {
    let coordinator = makeCoordinator()
    let opener = OpenCounter()
    coordinator.register { opener.count += 1 }
    coordinator.didFinishLaunching(asLoginItem: true)
    #expect(opener.count == 0)
    #expect(presence.bringForwards == 0, "No focus change")

    // A window SwiftUI opens by itself meanwhile (macOS 14) closes again.
    let window = makeWindow()
    window.orderFront(nil)
    coordinator.attach(window)
    #expect(!window.isVisible)
    #expect(presence.presences.isEmpty, "No Dock icon")

    // A person opening Salah later gets the window.
    coordinator.open()
    #expect(opener.count == 1)
    let opened = makeWindow()
    defer { opened.close() }
    coordinator.attach(opened)
    #expect(presence.presences == [.regular])
  }

  @Test func anotherLaunchOpensTheWindow() {
    let coordinator = makeCoordinator()
    let opener = OpenCounter()
    coordinator.register { opener.count += 1 }
    coordinator.didFinishLaunching(asLoginItem: false)
    #expect(opener.count == 1)
    #expect(presence.bringForwards == 1)
  }

  @Test func readsALoginItemLaunch() {
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
      targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID))
    #expect(!AppWindowCoordinator.isLoginItemLaunch(event))
    event.setParam(
      NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
      forKeyword: AEKeyword(keyAEPropData))
    #expect(AppWindowCoordinator.isLoginItemLaunch(event))
    #expect(!AppWindowCoordinator.isLoginItemLaunch(nil))
    #expect(!AppWindowCoordinator.isLoginItemLaunch(quitEvent(reason: nil)))
  }

  // MARK: - Helpers

  private func makeWindow() -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.orderFront(nil)
    return window
  }

  private func quitEvent(reason: UInt32?) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEQuitApplication),
      targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID))
    if let reason {
      event.setAttribute(
        NSAppleEventDescriptor(enumCode: OSType(reason)), forKeyword: AEKeyword(kAEQuitReason))
    }
    return event
  }
}

/// Records what the coordinator asks of the app.
@MainActor
private final class PresenceRecorder: AppPresenceControlling {
  var presences: [AppLifecycle.Presence] = []
  var bringForwards = 0
  var terminations = 0

  /// Records changes only, as the app sees them.
  func setPresence(_ presence: AppLifecycle.Presence) {
    if presences.last != presence { presences.append(presence) }
  }

  func bringForward() { bringForwards += 1 }
  func terminate() { terminations += 1 }
}

@MainActor
private final class NoteCounter {
  var count = 0
  var dismissals = 0
}

@MainActor
private final class OpenCounter {
  var count = 0
}
