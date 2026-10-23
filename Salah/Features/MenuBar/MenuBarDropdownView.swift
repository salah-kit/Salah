import AppKit
import SalahCore
import SwiftUI

/// The menu-bar dropdown: a themed "Living Schedule" - header → vertical prayer
/// list where the next prayer expands in place into a hero card → end-of-day
/// Tomorrow card → action footer. Rendered from the running app's schedule at each
/// minute, so it matches the on-screen widget while ticking live and staying
/// interactive (per-prayer alert toggles, Silent, Stop). The visual core lives in
/// `MenuDropdownContent`; this root only builds the display and wires the actions.
struct MenuBarDropdownView: View {
  var prayerManager: PrayerManager

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    // `.everyMinute` advances the schedule at each minute boundary (so the focus,
    // tones and minute-resolution countdown stay current while the popover is
    // open); the hero's final-minute per-second tick is handled by the system
    // timer primitive inside `MenuLiveCountdown`, with no per-second tree redraw.
    TimelineView(.everyMinute) { context in
      MenuDropdownContent(
        display: prayerManager.display(at: AppClock.shifted(context.date)),
        lastKnownDay: prayerManager.lastKnownDay,
        attention: attention,
        onToggleAlert: toggleAlert,
        onToggleSilent: toggleSilent,
        onStop: stopAudio,
        onOpenSalah: { openWindow(nil) },
        onOpenSettings: { openWindow(.general) },
        onQuit: { prayerManager.quitSalah() })
    }
    .background(WindowOpenerBridge())
  }

  /// A terminal failure, such as location access denied: the banner's title.
  private var attention: String? {
    guard let notice = FailureReporter.shared.currentNotice, notice.category == .terminal else {
      return nil
    }
    return notice.bannerTitle
  }

  // MARK: - Actions

  /// Flip a prayer's alert. Friday-aware, so toggling Jumu'ah edits the Jumu'ah
  /// settings while the override is on, matching the row's name and state. (Sunrise
  /// never reaches here - `MenuDropdownContent` gives it no toggle.)
  private func toggleAlert(_ event: PrayerEvent) {
    prayerManager.preferences.toggleAlert(for: event)
  }

  private func toggleSilent() {
    prayerManager.preferences.silentMode.toggle()
  }

  private func stopAudio() {
    prayerManager.audioPlaybackController.stop()
  }

  /// Closes the dropdown, then opens Salah's window at `pane`, or at the last pane.
  private func openWindow(_ pane: WindowPane?) {
    dismiss()
    AppWindowCoordinator.shared.open(pane)
  }
}
